import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';

final class AndroidCommandOutput {
  AndroidCommandOutput({
    required this.exitCode,
    required List<int> stdout,
    required List<int> stderr,
  }) : stdout = List<int>.unmodifiable(stdout),
       stderr = List<int>.unmodifiable(stderr);

  final int exitCode;
  final List<int> stdout;
  final List<int> stderr;

  String get stdoutText => utf8.decode(stdout, allowMalformed: true);
  String get stderrText => utf8.decode(stderr, allowMalformed: true);
}

abstract interface class AndroidCommandRunner {
  Future<AndroidCommandOutput> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  });
}

final class SystemAndroidCommandRunner implements AndroidCommandRunner {
  const SystemAndroidCommandRunner({this.maxOutputBytes = 512 * 1024 * 1024});

  final int maxOutputBytes;

  @override
  Future<AndroidCommandOutput> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
    );
    final stdout = BytesBuilder(copy: false);
    final stderr = BytesBuilder(copy: false);
    var outputBytes = 0;
    var overflow = false;
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    void append(BytesBuilder target, List<int> bytes) {
      outputBytes += bytes.length;
      if (outputBytes > maxOutputBytes) {
        overflow = true;
        return;
      }
      target.add(bytes);
    }

    process.stdout.listen(
      (bytes) => append(stdout, bytes),
      onError: stdoutDone.completeError,
      onDone: stdoutDone.complete,
    );
    process.stderr.listen(
      (bytes) => append(stderr, bytes),
      onError: stderrDone.completeError,
      onDone: stderrDone.complete,
    );
    final exit = process.exitCode;
    late final int exitCode;
    try {
      exitCode = await exit.timeout(timeout);
    } on TimeoutException {
      process.kill();
      try {
        await exit.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        if (!Platform.isWindows) process.kill(ProcessSignal.sigkill);
        await exit.timeout(const Duration(seconds: 5));
      }
      await Future.wait(<Future<void>>[stdoutDone.future, stderrDone.future]);
      throw TimeoutException(
        'Android command exceeded ${timeout.inSeconds} seconds',
        timeout,
      );
    }
    await Future.wait(<Future<void>>[stdoutDone.future, stderrDone.future]);
    if (overflow) {
      throw StateError('Android command output exceeded the bounded budget');
    }
    return AndroidCommandOutput(
      exitCode: exitCode,
      stdout: stdout.takeBytes(),
      stderr: stderr.takeBytes(),
    );
  }
}

final class AndroidTargetProvider {
  AndroidTargetProvider({
    required String sdkRoot,
    AndroidCommandRunner runner = const SystemAndroidCommandRunner(),
  }) : this._(
         sdkRoot: Directory(sdkRoot).absolute.resolveSymbolicLinksSync(),
         runner: runner,
       );

  AndroidTargetProvider._({required this.sdkRoot, required this._runner}) {
    if (!File(adbExecutable).existsSync()) {
      throw FileSystemException(
        'Android adb executable not found',
        adbExecutable,
      );
    }
  }

  final String sdkRoot;
  final AndroidCommandRunner _runner;

  String get adbExecutable => p.join(sdkRoot, 'platform-tools', 'adb');
  String get emulatorExecutable => p.join(sdkRoot, 'emulator', 'emulator');

  Future<String> adbVersion() async {
    final output = await _adb(const <String>['version']);
    final line = const LineSplitter()
        .convert(output.stdoutText)
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => 'unknown');
    if (line.length > 512) throw StateError('ADB version output is oversized');
    return line;
  }

  Future<List<String>> listAvds() async {
    if (!File(emulatorExecutable).existsSync()) {
      throw FileSystemException(
        'Android emulator executable not found',
        emulatorExecutable,
      );
    }
    final output = await _checked(emulatorExecutable, const <String>[
      '-list-avds',
    ], timeout: const Duration(seconds: 30));
    final avds = const LineSplitter()
        .convert(output.stdoutText)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (avds.any(
      (value) =>
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$').hasMatch(value),
    )) {
      throw StateError('Android emulator returned an invalid AVD name');
    }
    avds.sort();
    return avds;
  }

  Future<List<AndroidTargetDescriptor>> discover({
    Set<String> managedSerials = const <String>{},
  }) async {
    final result = await _adb(const <String>['devices', '-l']);
    final serials = <String>[];
    for (final line in const LineSplitter().convert(result.stdoutText)) {
      final match = RegExp(
        r'^(emulator-[0-9]{4,5})\s+device(?:\s|$)',
      ).firstMatch(line.trim());
      if (match != null) serials.add(match.group(1)!);
    }
    serials.sort();
    final targets = <AndroidTargetDescriptor>[];
    for (final serial in serials) {
      targets.add(
        await inspect(
          serial,
          ownership: managedSerials.contains(serial)
              ? AndroidTargetOwnership.managed
              : AndroidTargetOwnership.attached,
        ),
      );
    }
    return targets;
  }

  Future<bool> isConnected(String serial) async {
    _serial(serial);
    final result = await _adb(const <String>['devices']);
    return const LineSplitter()
        .convert(result.stdoutText)
        .any(
          (line) => RegExp(
            '^${RegExp.escape(serial)}\\s+device(?:\\s|\$)',
          ).hasMatch(line.trim()),
        );
  }

  Future<AndroidTargetDescriptor> inspect(
    String serial, {
    AndroidTargetOwnership ownership = AndroidTargetOwnership.attached,
  }) async {
    _serial(serial);
    final values = await Future.wait(<Future<AndroidCommandOutput>>[
      _adbFor(serial, const <String>[
        'shell',
        'getprop',
        'ro.build.version.sdk',
      ]),
      _adbFor(serial, const <String>['shell', 'getprop', 'ro.product.cpu.abi']),
      _adbFor(serial, const <String>['emu', 'avd', 'name']),
    ]);
    final apiLevel = int.tryParse(values[0].stdoutText.trim());
    if (apiLevel == null) {
      throw StateError('Android target returned an invalid API level');
    }
    final avdName = values[2].stdoutText
        .split(RegExp(r'[\r\n]+'))
        .firstWhere((line) => line.trim().isNotEmpty)
        .trim();
    return AndroidTargetDescriptor(
      serial: serial,
      avdName: avdName,
      apiLevel: apiLevel,
      abi: values[1].stdoutText.trim(),
      ownership: ownership,
      capabilities: const <String>{
        'android.capture.png',
        'android.install.apk',
        'android.launch.intent',
        'android.reset.package',
        'gateway.adb-reverse',
        'gateway.emulator-host-alias',
      },
    );
  }

  Future<bool> hasReverse(String serial, AndroidGatewayPairing pairing) async {
    _serial(serial);
    if (pairing.strategy != AndroidGatewayRouteStrategy.adbReverse) {
      return true;
    }
    final output = await _adbFor(serial, const <String>['reverse', '--list']);
    final target = 'tcp:${pairing.targetPort}';
    final host = 'tcp:${pairing.hostPort}';
    return const LineSplitter().convert(output.stdoutText).any((line) {
      final fields = line.trim().split(RegExp(r'\s+'));
      return fields.length >= 2 &&
          fields[fields.length - 2] == target &&
          fields.last == host;
    });
  }

  Future<bool> ensurePairing(
    String serial,
    AndroidGatewayPairing pairing,
  ) async {
    _serial(serial);
    if (pairing.strategy == AndroidGatewayRouteStrategy.emulatorHostAlias) {
      return false;
    }
    if (await hasReverse(serial, pairing)) return false;
    await _adbFor(serial, <String>[
      'reverse',
      'tcp:${pairing.targetPort}',
      'tcp:${pairing.hostPort}',
    ]);
    if (!await hasReverse(serial, pairing)) {
      throw StateError('ADB reverse did not become observable');
    }
    return true;
  }

  Future<bool> removePairing(
    String serial,
    AndroidGatewayPairing pairing,
  ) async {
    _serial(serial);
    if (pairing.strategy == AndroidGatewayRouteStrategy.emulatorHostAlias ||
        !await hasReverse(serial, pairing)) {
      return false;
    }
    await _adbFor(serial, <String>[
      'reverse',
      '--remove',
      'tcp:${pairing.targetPort}',
    ]);
    if (await hasReverse(serial, pairing)) {
      throw StateError('ADB reverse remained after cleanup');
    }
    return true;
  }

  Future<void> installApk(String serial, String apkPath) async {
    _serial(serial);
    final file = File(apkPath).absolute;
    if (!file.existsSync() || Link(file.path).existsSync()) {
      throw FileSystemException(
        'APK does not exist or is a symlink',
        file.path,
      );
    }
    if (!file.path.endsWith('.apk') || file.lengthSync() > 1024 * 1024 * 1024) {
      throw const FormatException('APK must be a file no larger than 1 GiB');
    }
    await _adbFor(serial, <String>[
      'install',
      '-r',
      '--no-streaming',
      file.path,
    ], timeout: const Duration(minutes: 5));
  }

  Future<void> launch(String serial, AndroidLaunchRequest request) async {
    _serial(serial);
    await forceStop(serial, request.packageName);
    final values = <String, String>{
      'GATEWAY_ORIGIN': request.pairing.targetOrigin.toString(),
      ...request.overlay.values,
    };
    final arguments = <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      request.component,
    ];
    final keys = values.keys.toList()..sort();
    for (final key in keys) {
      if (!RegExp(r'^[A-Z][A-Z0-9_]{1,63}$').hasMatch(key)) {
        throw FormatException('Invalid Android overlay key');
      }
      final value = values[key]!;
      if (value.length > 4096 || value.contains('\u0000')) {
        throw FormatException('Invalid Android overlay value');
      }
      arguments.addAll(<String>['--es', key, value]);
    }

    await _adbFor(serial, arguments, timeout: const Duration(minutes: 2));
    await _waitForPackageReady(
      serial,
      request,
      timeout: const Duration(minutes: 1),
    );
  }

  Future<void> _waitForPackageReady(
    String serial,
    AndroidLaunchRequest request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final process = await _adbFor(serial, <String>[
          'shell',
          'pidof',
          request.packageName,
        ], timeout: const Duration(seconds: 5));
        final pids = process.stdoutText.trim();
        if (RegExp(r'^\d+(?:\s+\d+)*$').hasMatch(pids)) {
          final activity = await _adbFor(serial, const <String>[
            'shell',
            'dumpsys',
            'activity',
            'activities',
          ], timeout: const Duration(seconds: 5));
          final ready = const LineSplitter()
              .convert(activity.stdoutText)
              .where(
                (line) =>
                    line.contains('topResumedActivity=') ||
                    line.contains('mResumedActivity:'),
              )
              .any((line) => line.contains(request.component));
          if (ready) return;
        }
      } on ProcessException {
        // The package may not have a process while Android finishes launch.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException(
      'Android package did not expose its requested resumed activity',
      timeout,
    );
  }

  Future<void> resetPackage(String serial, String packageName) async {
    _serial(serial);
    _package(packageName);
    final output = await _adbFor(serial, <String>[
      'shell',
      'pm',
      'clear',
      packageName,
    ]);
    if (output.stdoutText.trim() != 'Success') {
      throw StateError('Android package reset did not succeed');
    }
  }

  Future<void> forceStop(String serial, String packageName) async {
    _serial(serial);
    _package(packageName);
    await _adbFor(serial, <String>['shell', 'am', 'force-stop', packageName]);
  }

  Future<List<int>> capturePng(String serial) async {
    _serial(serial);
    final output = await _adbFor(serial, const <String>[
      'exec-out',
      'screencap',
      '-p',
    ], timeout: const Duration(seconds: 30));
    if (output.stdout.length < 24 || output.stdout.length > 64 * 1024 * 1024) {
      throw StateError('Android capture has an invalid size');
    }
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (var index = 0; index < signature.length; index++) {
      if (output.stdout[index] != signature[index]) {
        throw StateError('Android capture is not a lossless PNG');
      }
    }
    return output.stdout;
  }

  Future<AndroidCommandOutput> runManagedAdb(
    AndroidTargetDescriptor target,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (target.ownership != AndroidTargetOwnership.managed) {
      throw StateError('Privileged ADB operation requires a managed emulator');
    }
    return _adbFor(target.serial, arguments, timeout: timeout);
  }

  Future<void> waitForBoot(
    String serial, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    _serial(serial);
    final deadline = DateTime.now().add(timeout);
    await _adbFor(serial, const <String>['wait-for-device'], timeout: timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final completed = await _adbFor(serial, const <String>[
          'shell',
          'getprop',
          'sys.boot_completed',
        ], timeout: const Duration(seconds: 5));
        final animation = await _adbFor(serial, const <String>[
          'shell',
          'getprop',
          'init.svc.bootanim',
        ], timeout: const Duration(seconds: 5));
        if (completed.stdoutText.trim() == '1' &&
            animation.stdoutText.trim() == 'stopped') {
          await _adbFor(serial, const <String>[
            'shell',
            'cmd',
            'package',
            'list',
            'packages',
            '--user',
            '0',
          ], timeout: const Duration(seconds: 30));
          return;
        }
      } on Object {
        // The daemon can restart while the emulator is booting.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('Android emulator did not finish booting', timeout);
  }

  Future<void> stopManaged(AndroidTargetDescriptor target) async {
    if (target.ownership != AndroidTargetOwnership.managed) {
      throw StateError('Refusing to stop an attached Android emulator');
    }
    await _adbFor(target.serial, const <String>['emu', 'kill']);
  }

  Future<AndroidCommandOutput> _adb(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) => _checked(adbExecutable, arguments, timeout: timeout);

  Future<AndroidCommandOutput> _adbFor(
    String serial,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    _serial(serial);
    return _adb(<String>['-s', serial, ...arguments], timeout: timeout);
  }

  Future<AndroidCommandOutput> _checked(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final result = await _runner.run(
      executable,
      List<String>.unmodifiable(arguments),
      timeout: timeout,
    );
    if (result.exitCode != 0) {
      final message = result.stderrText.trim();
      throw ProcessException(
        executable,
        arguments,
        message.isEmpty ? 'Android command failed' : message,
        result.exitCode,
      );
    }
    return result;
  }
}

abstract interface class AndroidEmulatorLauncher {
  Future<int> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });
}

final class SystemAndroidEmulatorLauncher implements AndroidEmulatorLauncher {
  const SystemAndroidEmulatorLauncher();

  @override
  Future<int> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }
}

final class AndroidManagedEmulatorService {
  AndroidManagedEmulatorService({
    required String workspaceRoot,
    required AndroidTargetProvider provider,
    AndroidEmulatorLauncher launcher = const SystemAndroidEmulatorLauncher(),
    bool Function(int processId)? processExists,
  }) : this._(
         store: FileSystemWorkspaceStore(workspaceRoot: workspaceRoot),
         provider: provider,
         launcher: launcher,
         processExists: processExists ?? _systemProcessExists,
       );

  AndroidManagedEmulatorService._({
    required this.store,
    required this.provider,
    required this._launcher,
    required this._processExists,
  });

  static const String _statePath = 'android/managed-emulator-v1.json';

  final AndroidTargetProvider provider;
  final FileSystemWorkspaceStore store;
  final AndroidEmulatorLauncher _launcher;
  final bool Function(int processId) _processExists;

  Future<AndroidLifecycleReport> start({
    required String avdName,
    required int port,
    required bool apply,
    bool headless = true,
    bool wipeData = false,
    String? renderer,
  }) async {
    if (port < 5554 || port > 5682 || port.isOdd) {
      throw ArgumentError.value(
        port,
        'port',
        'must be an even emulator console port from 5554 through 5682',
      );
    }
    final available = await provider.listAvds();
    if (!available.contains(avdName)) {
      throw StateError('Requested Android AVD is not installed');
    }
    final serial = 'emulator-$port';
    final existingState = _readState();
    if (existingState != null) {
      final target = await _ownedTarget(existingState);
      if (existingState.avdName == avdName &&
          existingState.serial == serial &&
          target != null) {
        return AndroidLifecycleReport(
          operation: AndroidLifecycleOperation.start,
          mode: apply
              ? AndroidLifecycleMode.apply
              : AndroidLifecycleMode.dryRun,
          changed: false,
          verified: true,
          actions: const <String>['reuse owned managed emulator'],
          target: target,
        );
      }
      if (existingState.avdName == avdName &&
          existingState.serial == serial &&
          target == null &&
          !_processExists(existingState.processId)) {
        if (!apply) {
          return AndroidLifecycleReport(
            operation: AndroidLifecycleOperation.start,
            mode: AndroidLifecycleMode.dryRun,
            changed: true,
            verified: false,
            actions: const <String>[
              'replace stale ownership for the same managed AVD',
              'start explicit AVD on an unused console port',
              'wait for Android boot completion',
              'persist managed ownership atomically',
            ],
            target: existingState.target,
          );
        }
        store.withExclusiveLock(_deleteState);
      } else {
        throw StateError(
          'A different or still-running managed Android emulator is already owned',
        );
      }
    }
    if ((await provider.discover()).any((target) => target.serial == serial)) {
      throw StateError('Requested emulator port is already attached or in use');
    }
    const actions = <String>[
      'start explicit AVD on an unused console port',
      'wait for Android boot completion',
      'persist managed ownership atomically',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.start,
        mode: AndroidLifecycleMode.dryRun,
        changed: true,
        verified: false,
        actions: actions,
      );
    }
    final arguments = <String>[
      '-avd',
      avdName,
      '-port',
      '$port',
      '-no-snapshot-save',
      if (wipeData) '-no-snapshot',
      if (wipeData) '-wipe-data',
      '-no-boot-anim',
      '-no-audio',
      if (renderer != null) ...<String>['-gpu', renderer],
      if (headless) '-no-window',
    ];
    final processId = await _launcher.start(
      provider.emulatorExecutable,
      arguments,
      workingDirectory: provider.sdkRoot,
    );
    final pending = _ManagedEmulatorState(
      avdName: avdName,
      serial: serial,
      processId: processId,
      startedAt: DateTime.now().toUtc(),
    );
    store.withExclusiveLock(() => _writeState(pending));
    try {
      await provider.waitForBoot(serial);
      final target = await provider.inspect(
        serial,
        ownership: AndroidTargetOwnership.managed,
      );
      if (target.avdName != avdName) {
        throw StateError(
          'Started emulator identity does not match requested AVD',
        );
      }
      store.withExclusiveLock(() => _writeState(pending.withTarget(target)));
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.start,
        mode: AndroidLifecycleMode.apply,
        changed: true,
        verified: true,
        actions: actions,
        target: target,
      );
    } on Object {
      final target = await _ownedTarget(pending);
      if (target != null) {
        await provider.stopManaged(target);
      }
      store.withExclusiveLock(_deleteState);
      rethrow;
    }
  }

  Future<AndroidLifecycleReport> status() async {
    final state = _readState();
    if (state == null) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.discover,
        mode: AndroidLifecycleMode.inspect,
        changed: false,
        verified: true,
        actions: const <String>['no managed emulator owned'],
      );
    }
    final target = await _ownedTarget(state);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.discover,
      mode: AndroidLifecycleMode.inspect,
      changed: false,
      verified: target != null,
      actions: const <String>['verify persisted emulator ownership'],
      target: target,
    );
  }

  Future<AndroidTargetDescriptor?> ownedTarget() async {
    final state = _readState();
    return state == null ? null : _ownedTarget(state);
  }

  Future<AndroidLifecycleReport> stop({required bool apply}) async {
    final state = _readState();
    if (state == null) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.stop,
        mode: apply ? AndroidLifecycleMode.apply : AndroidLifecycleMode.dryRun,
        changed: false,
        verified: true,
        actions: const <String>['no managed emulator owned'],
      );
    }
    final target = await _ownedTarget(state);
    if (target == null) {
      if (_processExists(state.processId)) {
        throw StateError(
          'Managed emulator process is alive but its identity cannot be verified',
        );
      }
      final tlsState = File(p.join(store.stateRoot, 'android', 'tls-v1.json'));
      if (tlsState.existsSync()) {
        throw StateError(
          'Managed AVD must be restarted with the same name and port to remove persisted TLS trust',
        );
      }
      const staleActions = <String>[
        'verify the owned emulator process is absent',
        'remove stale managed ownership state',
      ];
      if (apply) store.withExclusiveLock(_deleteState);
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.stop,
        mode: apply ? AndroidLifecycleMode.apply : AndroidLifecycleMode.dryRun,
        changed: true,
        verified: apply,
        actions: staleActions,
        target: state.target,
      );
    }
    const actions = <String>[
      'stop only the verified owned emulator',
      'remove managed ownership state',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.stop,
        mode: AndroidLifecycleMode.dryRun,
        changed: true,
        verified: false,
        actions: actions,
        target: target,
      );
    }
    await provider.stopManaged(target);
    store.withExclusiveLock(_deleteState);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.stop,
      mode: AndroidLifecycleMode.apply,
      changed: true,
      verified: true,
      actions: actions,
      target: target,
    );
  }

  _ManagedEmulatorState? _readState() {
    final bytes = store.readStateBytes(_statePath);
    return bytes == null
        ? null
        : _ManagedEmulatorState.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  Future<AndroidTargetDescriptor?> _ownedTarget(
    _ManagedEmulatorState state,
  ) async {
    try {
      if (!await provider.isConnected(state.serial)) return null;
      final target = await provider.inspect(
        state.serial,
        ownership: AndroidTargetOwnership.managed,
      );
      return target.avdName == state.avdName ? target : null;
    } on Object {
      return null;
    }
  }

  void _writeState(_ManagedEmulatorState state) {
    final canonical = const JcsCanonicalizer().canonicalize(state.toJson());
    store.atomicWrite(_statePath, utf8.encode('$canonical\n'));
  }

  void _deleteState() {
    final file = File(p.join(store.stateRoot, _statePath));
    if (file.existsSync()) file.deleteSync();
  }
}

final class _ManagedEmulatorState {
  const _ManagedEmulatorState({
    required this.avdName,
    required this.serial,
    required this.processId,
    required this.startedAt,
    this.target,
  });

  final String avdName;
  final String serial;
  final int processId;
  final DateTime startedAt;
  final AndroidTargetDescriptor? target;

  _ManagedEmulatorState withTarget(AndroidTargetDescriptor value) =>
      _ManagedEmulatorState(
        avdName: avdName,
        serial: serial,
        processId: processId,
        startedAt: startedAt,
        target: value,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'avdName': avdName,
    'serial': serial,
    'processId': processId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (target != null) 'target': target!.toJson(),
  };

  factory _ManagedEmulatorState.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> || value['schemaVersion'] != 1) {
      throw const FormatException('Invalid managed emulator state');
    }
    const allowed = <String>{
      'schemaVersion',
      'avdName',
      'serial',
      'processId',
      'startedAt',
      'target',
    };
    if (value.keys.any((key) => key is! String || !allowed.contains(key))) {
      throw const FormatException('Unknown managed emulator state field');
    }
    final avdName = value['avdName'];
    final serial = value['serial'];
    final processId = value['processId'];
    final startedAt = value['startedAt'];
    if (avdName is! String ||
        serial is! String ||
        processId is! int ||
        processId < 1 ||
        startedAt is! String) {
      throw const FormatException('Invalid managed emulator state value');
    }
    _serial(serial);
    final parsedTime = DateTime.tryParse(startedAt);
    if (parsedTime == null || !parsedTime.isUtc) {
      throw const FormatException('Invalid managed emulator timestamp');
    }
    final target = value['target'] == null
        ? null
        : AndroidTargetDescriptor.fromJson(value['target']);
    if (target != null &&
        (target.serial != serial ||
            target.avdName != avdName ||
            target.ownership != AndroidTargetOwnership.managed)) {
      throw const FormatException('Managed target identity mismatch');
    }
    return _ManagedEmulatorState(
      avdName: avdName,
      serial: serial,
      processId: processId,
      startedAt: parsedTime,
      target: target,
    );
  }
}

final class AndroidBootstrapService {
  AndroidBootstrapService({
    required String workspaceRoot,
    required this.provider,
    this.managedTargetResolver,
  }) : store = FileSystemWorkspaceStore(workspaceRoot: workspaceRoot);

  static const String _statePath = 'android/bootstrap-v1.json';

  final AndroidTargetProvider provider;
  final FileSystemWorkspaceStore store;
  final Future<AndroidTargetDescriptor?> Function()? managedTargetResolver;

  Future<AndroidLifecycleReport> bootstrap({
    required String serial,
    required AndroidGatewayPairing pairing,
    required bool apply,
  }) => _configure(
    operation: AndroidLifecycleOperation.bootstrap,
    serial: serial,
    pairing: pairing,
    apply: apply,
  );

  Future<AndroidLifecycleReport> update({
    required String serial,
    required AndroidGatewayPairing pairing,
    required bool apply,
  }) => _configure(
    operation: AndroidLifecycleOperation.update,
    serial: serial,
    pairing: pairing,
    apply: apply,
  );

  Future<AndroidLifecycleReport> _configure({
    required AndroidLifecycleOperation operation,
    required String serial,
    required AndroidGatewayPairing pairing,
    required bool apply,
  }) async {
    final previous = _readState();
    final ownership = await _resolveOwnership(serial);
    final target = await provider.inspect(serial, ownership: ownership);
    if (pairing.tls && target.ownership != AndroidTargetOwnership.managed) {
      throw StateError('TLS trust can only be installed on a managed emulator');
    }
    final same =
        previous != null &&
        previous.target.serial == serial &&
        Digest.semantic(previous.pairing.toJson()) ==
            Digest.semantic(pairing.toJson());
    final actions = <String>[
      if (previous != null && !same) 'remove previous gateway pairing',
      if (!same) 'apply ${pairing.strategy.name} gateway pairing',
      if (same) 'verify existing gateway pairing',
      'persist redacted bootstrap state atomically',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: operation,
        mode: AndroidLifecycleMode.dryRun,
        changed: !same,
        verified: false,
        actions: actions,
        target: target,
        pairing: pairing,
      );
    }

    var changed = false;
    if (previous != null && !same) {
      if (await provider.isConnected(previous.target.serial)) {
        changed =
            await provider.removePairing(
              previous.target.serial,
              previous.pairing,
            ) ||
            changed;
      }
    }
    try {
      changed = await provider.ensurePairing(serial, pairing) || changed;
      if (!await provider.hasReverse(serial, pairing)) {
        throw StateError('Android pairing verification failed');
      }
      final state = _AndroidBootstrapState(target: target, pairing: pairing);
      store.withExclusiveLock(() => _writeState(state));
    } on Object {
      if (previous != null && !same) {
        if (await provider.isConnected(previous.target.serial)) {
          await provider.ensurePairing(
            previous.target.serial,
            previous.pairing,
          );
          store.withExclusiveLock(() => _writeState(previous));
        }
      }
      rethrow;
    }
    return AndroidLifecycleReport(
      operation: operation,
      mode: AndroidLifecycleMode.apply,
      changed: changed || !same,
      verified: true,
      actions: actions,
      target: target,
      pairing: pairing,
    );
  }

  Future<AndroidLifecycleReport> verify() async {
    final state = _readState();
    if (state == null) {
      throw StateError('Android bootstrap is not configured');
    }
    if (!await provider.isConnected(state.target.serial)) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.verify,
        mode: AndroidLifecycleMode.inspect,
        changed: false,
        verified: false,
        actions: const <String>[
          'managed or attached emulator is absent',
          'gateway pairing cannot be observed',
        ],
        target: state.target,
        pairing: state.pairing,
      );
    }
    final ownership = await _resolveOwnership(state.target.serial);
    final target = await provider.inspect(
      state.target.serial,
      ownership: ownership,
    );
    final sameTarget =
        target.avdName == state.target.avdName &&
        target.apiLevel == state.target.apiLevel &&
        target.abi == state.target.abi &&
        target.ownership == state.target.ownership;
    final paired = await provider.hasReverse(target.serial, state.pairing);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.verify,
      mode: AndroidLifecycleMode.inspect,
      changed: false,
      verified: sameTarget && paired,
      actions: const <String>[
        'match emulator identity',
        'observe exact gateway pairing',
      ],
      target: target,
      pairing: state.pairing,
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
        actions: const <String>['no owned bootstrap state'],
      );
    }
    const actions = <String>[
      'remove exact gateway pairing',
      'remove owned bootstrap state',
    ];
    if (!apply) {
      return AndroidLifecycleReport(
        operation: AndroidLifecycleOperation.remove,
        mode: AndroidLifecycleMode.dryRun,
        changed: true,
        verified: false,
        actions: actions,
        target: state.target,
        pairing: state.pairing,
      );
    }
    final connected = await provider.isConnected(state.target.serial);
    if (connected) {
      await provider.removePairing(state.target.serial, state.pairing);
    }
    store.withExclusiveLock(_deleteState);
    return AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.remove,
      mode: AndroidLifecycleMode.apply,
      changed: true,
      verified:
          !connected ||
          !await provider.hasReverse(state.target.serial, state.pairing),
      actions: <String>[
        if (!connected) 'verify the configured emulator is absent',
        ...actions,
      ],
      target: state.target,
      pairing: state.pairing,
    );
  }

  _AndroidBootstrapState? _readState() {
    final bytes = store.readStateBytes(_statePath);
    if (bytes == null) return null;
    return _AndroidBootstrapState.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  void _writeState(_AndroidBootstrapState state) {
    final canonical = const JcsCanonicalizer().canonicalize(state.toJson());
    store.atomicWrite(_statePath, utf8.encode('$canonical\n'));
  }

  void _deleteState() {
    final file = File(p.join(store.stateRoot, _statePath));
    if (file.existsSync()) file.deleteSync();
  }

  Future<AndroidTargetOwnership> _resolveOwnership(String serial) async {
    final managed = await managedTargetResolver?.call();
    return managed?.serial == serial
        ? AndroidTargetOwnership.managed
        : AndroidTargetOwnership.attached;
  }
}

final class _AndroidBootstrapState {
  const _AndroidBootstrapState({required this.target, required this.pairing});

  final AndroidTargetDescriptor target;
  final AndroidGatewayPairing pairing;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'target': target.toJson(),
    'pairing': pairing.toJson(),
  };

  factory _AndroidBootstrapState.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value.length != 3 ||
        value['schemaVersion'] != 1 ||
        !value.containsKey('target') ||
        !value.containsKey('pairing')) {
      throw const FormatException('Invalid Android bootstrap state');
    }
    return _AndroidBootstrapState(
      target: AndroidTargetDescriptor.fromJson(value['target']),
      pairing: AndroidGatewayPairing.fromJson(value['pairing']),
    );
  }
}

void _serial(String serial) {
  if (!RegExp(r'^emulator-[0-9]{4,5}$').hasMatch(serial)) {
    throw FormatException('Physical or invalid Android serial is forbidden');
  }
}

void _package(String packageName) {
  if (packageName.length > 255 ||
      !RegExp(
        r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$',
      ).hasMatch(packageName)) {
    throw FormatException('Invalid Android package name');
  }
}

bool _systemProcessExists(int processId) {
  if (!Platform.isLinux) return true;
  return Directory('/proc/$processId').existsSync();
}
