import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';
import 'android_target_provider.dart';

final class WorkspaceTlsService {
  WorkspaceTlsService({
    required String workspaceRoot,
    required this.provider,
    this.opensslExecutable = 'openssl',
    AndroidCommandRunner commandRunner = const SystemAndroidCommandRunner(),
    DateTime Function()? nowUtc,
  }) : store = FileSystemWorkspaceStore(workspaceRoot: workspaceRoot),
       _runner = commandRunner,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static const String _statePath = 'android/tls-v1.json';
  static const String _tlsDirectory = 'android/tls';

  final FileSystemWorkspaceStore store;
  final AndroidTargetProvider provider;
  final String opensslExecutable;
  final AndroidCommandRunner _runner;
  final DateTime Function() _nowUtc;

  Future<AndroidLifecycleReport> install({
    required AndroidTargetDescriptor target,
    required bool apply,
  }) async {
    _managed(target);
    final existing = _readState();
    if (existing != null &&
        existing.target.serial == target.serial &&
        existing.target.avdName == target.avdName &&
        await _verifyState(existing, remote: apply)) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.bootstrap,
        mode: apply ? AndroidLifecycleMode.apply : AndroidLifecycleMode.dryRun,
        changed: false,
        verified: true,
        actions: const <String>['reuse unexpired workspace certificate trust'],
        target: target,
        artifactDigest: existing.caCertificateDigest,
      );
    }
    const actions = <String>[
      'generate workspace-scoped CA and leaf certificate',
      'install public CA only on the owned emulator',
      'record expiration and exact undo path',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.bootstrap,
        mode: AndroidLifecycleMode.dryRun,
        changed: true,
        verified: false,
        actions: actions,
        target: target,
      );
    }
    if (existing != null) {
      await _removeRemote(existing);
      _deleteLocal();
    }
    final material = await _generate();
    final remotePath =
        '/data/misc/user/0/cacerts-added/${material.subjectHash}.0';
    final stagingPath = '/data/local/tmp/workspace-${material.subjectHash}.cer';
    final state = _WorkspaceTlsState(
      target: target,
      createdAt: material.createdAt,
      expiresAt: material.expiresAt,
      remotePath: remotePath,
      caCertificateDigest: material.caCertificateDigest,
      leafCertificateDigest: material.leafCertificateDigest,
    );
    store.withExclusiveLock(() => _writeState(state));
    var remoteMayExist = false;
    try {
      await provider.runManagedAdb(target, const <String>['root']);
      await provider.runManagedAdb(target, const <String>['wait-for-device']);
      await provider.runManagedAdb(target, <String>[
        'push',
        material.caCertificate.path,
        stagingPath,
      ]);
      try {
        await provider.runManagedAdb(target, const <String>[
          'shell',
          'mkdir',
          '-p',
          '/data/misc/user/0/cacerts-added',
        ]);
        remoteMayExist = true;
        await provider.runManagedAdb(target, <String>[
          'shell',
          'cp',
          stagingPath,
          remotePath,
        ]);
        await provider.runManagedAdb(target, <String>[
          'shell',
          'chmod',
          '0644',
          remotePath,
        ]);
        await provider.runManagedAdb(target, <String>[
          'shell',
          'restorecon',
          remotePath,
        ]);
      } finally {
        await provider.runManagedAdb(target, <String>[
          'shell',
          'rm',
          '-f',
          stagingPath,
        ]);
      }
      if (!await _verifyState(state, remote: true)) {
        throw StateError(
          'Workspace TLS trust did not pass post-install verify',
        );
      }
    } on Object {
      if (!remoteMayExist) {
        store.withExclusiveLock(_deleteLocal);
      } else {
        try {
          await _removeRemote(state);
          store.withExclusiveLock(_deleteLocal);
        } on Object {
          throw StateError(
            'Workspace TLS install failed and recovery state was preserved for exact undo',
          );
        }
      }
      rethrow;
    }
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.bootstrap,
      mode: AndroidLifecycleMode.apply,
      changed: true,
      verified: true,
      actions: actions,
      target: target,
      artifactDigest: state.caCertificateDigest,
    );
  }

  Future<AndroidLifecycleReport> verify() async {
    final state = _readState();
    if (state == null) {
      throw StateError('Workspace TLS trust is not installed');
    }
    final verified = await _verifyState(state, remote: true);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.verify,
      mode: AndroidLifecycleMode.inspect,
      changed: false,
      verified: verified,
      actions: const <String>[
        'verify public certificate digest and expiry',
        'verify exact emulator trust path',
      ],
      target: state.target,
      artifactDigest: state.caCertificateDigest,
    );
  }

  Future<AndroidLifecycleReport> remove({required bool apply}) async {
    final state = _readState();
    if (state == null) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.remove,
        mode: apply ? AndroidLifecycleMode.apply : AndroidLifecycleMode.dryRun,
        changed: false,
        verified: true,
        actions: const <String>['no owned workspace TLS trust'],
      );
    }
    const actions = <String>[
      'remove exact emulator trust certificate',
      'delete owned workspace private material',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.remove,
        mode: AndroidLifecycleMode.dryRun,
        changed: true,
        verified: false,
        actions: actions,
        target: state.target,
        artifactDigest: state.caCertificateDigest,
      );
    }
    await _removeRemote(state);
    store.withExclusiveLock(_deleteLocal);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.remove,
      mode: AndroidLifecycleMode.apply,
      changed: true,
      verified: true,
      actions: actions,
      target: state.target,
      artifactDigest: state.caCertificateDigest,
    );
  }

  Future<_CertificateMaterial> _generate() async {
    final root = Directory(p.join(store.stateRoot, _tlsDirectory));
    if (Link(root.path).existsSync()) {
      throw FileSystemException('TLS material directory cannot be a symlink');
    }
    root.createSync(recursive: true);
    final caKey = File(p.join(root.path, 'ca-key.pem'));
    final caCertificate = File(p.join(root.path, 'ca-cert.pem'));
    final leafKey = File(p.join(root.path, 'leaf-key.pem'));
    final leafRequest = File(p.join(root.path, 'leaf.csr'));
    final leafCertificate = File(p.join(root.path, 'leaf-cert.pem'));
    final extension = File(p.join(root.path, 'leaf.ext'));
    extension.writeAsStringSync('''basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2
''', flush: true);
    final workspaceBinding = Digest.semantic(<String, Object?>{
      'workspaceRoot': store.workspaceRoot,
    }).value.substring(7, 19);
    await _openssl(<String>[
      'genpkey',
      '-algorithm',
      'RSA',
      '-pkeyopt',
      'rsa_keygen_bits:2048',
      '-out',
      caKey.path,
    ]);
    await _openssl(<String>[
      'req',
      '-x509',
      '-new',
      '-key',
      caKey.path,
      '-sha256',
      '-days',
      '30',
      '-subj',
      '/CN=Abel Workspace $workspaceBinding',
      '-out',
      caCertificate.path,
    ]);
    await _openssl(<String>[
      'genpkey',
      '-algorithm',
      'RSA',
      '-pkeyopt',
      'rsa_keygen_bits:2048',
      '-out',
      leafKey.path,
    ]);
    await _openssl(<String>[
      'req',
      '-new',
      '-key',
      leafKey.path,
      '-subj',
      '/CN=localhost',
      '-out',
      leafRequest.path,
    ]);
    await _openssl(<String>[
      'x509',
      '-req',
      '-in',
      leafRequest.path,
      '-CA',
      caCertificate.path,
      '-CAkey',
      caKey.path,
      '-CAcreateserial',
      '-out',
      leafCertificate.path,
      '-days',
      '7',
      '-sha256',
      '-extfile',
      extension.path,
    ]);
    caKey.setLastModifiedSync(_nowUtc());
    leafKey.setLastModifiedSync(_nowUtc());
    if (!Platform.isWindows) {
      await _chmod600(caKey.path);
      await _chmod600(leafKey.path);
    }
    final hashOutput = await _openssl(<String>[
      'x509',
      '-subject_hash_old',
      '-in',
      caCertificate.path,
      '-noout',
    ]);
    final subjectHash = hashOutput.stdoutText.trim();
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(subjectHash)) {
      throw StateError('OpenSSL returned an invalid certificate subject hash');
    }
    final createdAt = _nowUtc();
    return _CertificateMaterial(
      caCertificate: caCertificate,
      subjectHash: subjectHash,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 6, hours: 23)),
      caCertificateDigest: Digest.bytes(caCertificate.readAsBytesSync()),
      leafCertificateDigest: Digest.bytes(leafCertificate.readAsBytesSync()),
    );
  }

  Future<AndroidCommandOutput> _openssl(List<String> arguments) async {
    final output = await _runner.run(
      opensslExecutable,
      arguments,
      timeout: const Duration(seconds: 30),
    );
    if (output.exitCode != 0) {
      throw ProcessException(
        opensslExecutable,
        arguments,
        output.stderrText.trim(),
        output.exitCode,
      );
    }
    return output;
  }

  Future<void> _chmod600(String path) async {
    final output = await _runner.run('chmod', <String>[
      '0600',
      path,
    ], timeout: const Duration(seconds: 10));
    if (output.exitCode != 0) {
      throw ProcessException('chmod', <String>['0600', path], 'chmod failed');
    }
  }

  Future<bool> _verifyState(
    _WorkspaceTlsState state, {
    required bool remote,
  }) async {
    if (!state.expiresAt.isAfter(_nowUtc().add(const Duration(hours: 1)))) {
      return false;
    }
    final caCertificate = File(
      p.join(store.stateRoot, _tlsDirectory, 'ca-cert.pem'),
    );
    final leafCertificate = File(
      p.join(store.stateRoot, _tlsDirectory, 'leaf-cert.pem'),
    );
    if (!caCertificate.existsSync() || !leafCertificate.existsSync()) {
      return false;
    }
    if (Digest.bytes(caCertificate.readAsBytesSync()) !=
            state.caCertificateDigest ||
        Digest.bytes(leafCertificate.readAsBytesSync()) !=
            state.leafCertificateDigest) {
      return false;
    }
    for (final certificate in <File>[caCertificate, leafCertificate]) {
      final check = await _runner.run(opensslExecutable, <String>[
        'x509',
        '-checkend',
        '3600',
        '-noout',
        '-in',
        certificate.path,
      ], timeout: const Duration(seconds: 10));
      if (check.exitCode != 0) return false;
    }
    if (!remote) return true;
    try {
      final observed = await provider.runManagedAdb(state.target, <String>[
        'shell',
        'test',
        '-f',
        state.remotePath,
      ]);
      return observed.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> _removeRemote(_WorkspaceTlsState state) async {
    _managed(state.target);
    await provider.runManagedAdb(state.target, const <String>['root']);
    await provider.runManagedAdb(state.target, const <String>[
      'wait-for-device',
    ]);
    await provider.runManagedAdb(state.target, <String>[
      'shell',
      'rm',
      '-f',
      state.remotePath,
    ]);
  }

  _WorkspaceTlsState? _readState() {
    final bytes = store.readStateBytes(_statePath);
    return bytes == null
        ? null
        : _WorkspaceTlsState.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  void _writeState(_WorkspaceTlsState state) {
    final canonical = const JcsCanonicalizer().canonicalize(state.toJson());
    store.atomicWrite(_statePath, utf8.encode('$canonical\n'));
  }

  void _deleteLocal() {
    final state = File(p.join(store.stateRoot, _statePath));
    if (state.existsSync()) state.deleteSync();
    final directory = Directory(p.join(store.stateRoot, _tlsDirectory));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _CertificateMaterial {
  const _CertificateMaterial({
    required this.caCertificate,
    required this.subjectHash,
    required this.createdAt,
    required this.expiresAt,
    required this.caCertificateDigest,
    required this.leafCertificateDigest,
  });

  final File caCertificate;
  final String subjectHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Digest caCertificateDigest;
  final Digest leafCertificateDigest;
}

final class _WorkspaceTlsState {
  const _WorkspaceTlsState({
    required this.target,
    required this.createdAt,
    required this.expiresAt,
    required this.remotePath,
    required this.caCertificateDigest,
    required this.leafCertificateDigest,
  });

  final AndroidTargetDescriptor target;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String remotePath;
  final Digest caCertificateDigest;
  final Digest leafCertificateDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'target': target.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'remotePath': remotePath,
    'caCertificateDigest': caCertificateDigest.value,
    'leafCertificateDigest': leafCertificateDigest.value,
  };

  factory _WorkspaceTlsState.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> || value['schemaVersion'] != 1) {
      throw const FormatException('Invalid workspace TLS state');
    }
    const fields = <String>{
      'schemaVersion',
      'target',
      'createdAt',
      'expiresAt',
      'remotePath',
      'caCertificateDigest',
      'leafCertificateDigest',
    };
    if (value.length != fields.length ||
        value.keys.any((key) => key is! String || !fields.contains(key))) {
      throw const FormatException('Unknown workspace TLS state field');
    }
    final target = AndroidTargetDescriptor.fromJson(value['target']);
    _managed(target);
    final createdAt = _utc(value['createdAt'], 'createdAt');
    final expiresAt = _utc(value['expiresAt'], 'expiresAt');
    final remotePath = value['remotePath'];
    if (remotePath is! String ||
        !RegExp(
          r'^/data/misc/user/0/cacerts-added/[0-9a-f]{8}\.0$',
        ).hasMatch(remotePath)) {
      throw const FormatException('Invalid workspace TLS remotePath');
    }
    return _WorkspaceTlsState(
      target: target,
      createdAt: createdAt,
      expiresAt: expiresAt,
      remotePath: remotePath,
      caCertificateDigest: Digest(_string(value, 'caCertificateDigest')),
      leafCertificateDigest: Digest(_string(value, 'leafCertificateDigest')),
    );
  }
}

void _managed(AndroidTargetDescriptor target) {
  if (target.ownership != AndroidTargetOwnership.managed) {
    throw StateError('Workspace TLS trust requires a managed Android emulator');
  }
}

DateTime _utc(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid TLS $field');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('Invalid TLS $field');
  }
  return parsed;
}

String _string(Map<Object?, Object?> value, String field) {
  final item = value[field];
  if (item is! String) throw FormatException('Invalid TLS $field');
  return item;
}
