import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import '../targets/android_target_provider.dart';
import 'png_capture_inspector.dart';

final class AndroidEvidenceSelection {
  const AndroidEvidenceSelection({
    this.screenshot = true,
    this.semantics = true,
    this.logcat = true,
    this.screenRecording = false,
    this.performanceTrace = false,
    this.duration = const Duration(seconds: 3),
    this.syntheticDataConfirmed = false,
  });

  final bool screenshot;
  final bool semantics;
  final bool logcat;
  final bool screenRecording;
  final bool performanceTrace;
  final Duration duration;
  final bool syntheticDataConfirmed;

  void validate() {
    if (duration < const Duration(seconds: 1) ||
        duration > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        duration,
        'duration',
        'must be from 1 to 30 seconds',
      );
    }
  }
}

final class AndroidEvidenceResult {
  const AndroidEvidenceResult({required this.evidence, required this.manifest});

  final Evidence evidence;
  final AndroidEvidenceManifest manifest;
}

final class AndroidEvidenceProvider {
  AndroidEvidenceProvider({
    required this.provider,
    required this.store,
    Clock? clock,
    IdGenerator? ids,
    this.pngInspector = const PngCaptureInspector(maxBytes: 64 * 1024 * 1024),
  }) : clock = clock ?? SystemClock(),
       ids = ids ?? SecureIdGenerator();

  final AndroidTargetProvider provider;
  final FileSystemWorkspaceStore store;
  final Clock clock;
  final IdGenerator ids;
  final PngCaptureInspector pngInspector;

  Future<AndroidEvidenceResult> collect({
    required AndroidTargetDescriptor target,
    required Digest catalogDigest,
    required String launchProfileId,
    required String packageName,
    required TargetContainmentReport containment,
    AndroidEvidenceSelection selection = const AndroidEvidenceSelection(),
    Map<String, Digest> inputDigests = const <String, Digest>{},
    String? sourceRevision,
    BackendMode backendMode = BackendMode.none,
  }) async {
    selection.validate();
    if (target.ownership != AndroidTargetOwnership.managed) {
      throw StateError('Native Android evidence requires a managed emulator');
    }
    if (containment.platform != 'androidEmulator' ||
        containment.targetId != target.serial ||
        containment.networkContainment == NetworkContainment.unconstrained) {
      throw ArgumentError(
        'Android evidence requires a matching executed containment report',
      );
    }
    if (!RegExp(
      r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$',
    ).hasMatch(packageName)) {
      throw const FormatException('Android evidence package name is invalid');
    }

    final correlationId = 'android-${ids.nextId()}';
    final collectedAt = clock.nowUtc();
    final environment = await _environment(target);
    final collected = <_AndroidCollectedArtifact>[];
    final observations = <AndroidEvidenceObservation>[];

    Future<void> run(
      String role,
      bool requested,
      Future<_AndroidRawArtifact> Function() operation, {
      bool visualPolicy = false,
    }) async {
      if (!requested) {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.unavailable,
            detailCode: 'not_requested',
          ),
        );
        return;
      }
      if (visualPolicy && !selection.syntheticDataConfirmed) {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.policyDenied,
            detailCode: 'synthetic_data_not_confirmed',
          ),
        );
        return;
      }
      try {
        final raw = await operation();
        late final Digest digest;
        store.withExclusiveLock(() => digest = store.putBlob(raw.bytes));
        final artifact = Artifact(
          digest: digest,
          size: raw.bytes.length,
          mediaType: raw.mediaType,
          classification: raw.classification,
          role: role,
          pixelDigest: raw.png?.pixelDigest,
          width: raw.png?.width,
          height: raw.png?.height,
        );
        collected.add(_AndroidCollectedArtifact(artifact));
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.collected,
            detailCode: 'collected',
            artifactDigest: digest,
          ),
        );
      } on ProcessException {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.unavailable,
            detailCode: 'target_command_unavailable',
          ),
        );
      } on TimeoutException {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.failed,
            detailCode: 'target_command_timeout',
          ),
        );
      } on FormatException {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.failed,
            detailCode: 'artifact_validation_failed',
          ),
        );
      } on StateError {
        observations.add(
          AndroidEvidenceObservation(
            role: role,
            status: AndroidEvidenceStatus.failed,
            detailCode: 'collection_failed',
          ),
        );
      }
    }

    await run('android.screenshot', selection.screenshot, () async {
      final bytes = await provider.capturePng(target.serial);
      return _AndroidRawArtifact(
        bytes: bytes,
        mediaType: 'image/png',
        classification: ArtifactClassification.internal,
        png: pngInspector.inspect(bytes),
      );
    }, visualPolicy: true);
    await run('android.semantics', selection.semantics, () async {
      final output = await provider.runManagedAdb(target, const <String>[
        'exec-out',
        'uiautomator',
        'dump',
        '/dev/tty',
      ], timeout: const Duration(seconds: 30));
      final bytes = _sanitizeSemantics(output.stdout);
      return _AndroidRawArtifact(
        bytes: bytes,
        mediaType: 'application/vnd.devex.android-semantics.v1+json',
        classification: ArtifactClassification.internal,
      );
    });
    await run(
      'android.logcat',
      selection.logcat,
      () => _logcat(target, packageName),
    );
    await run(
      'android.screen-recording',
      selection.screenRecording,
      () => _screenRecording(target, correlationId, selection.duration),
      visualPolicy: true,
    );
    await run(
      'android.performance-trace',
      selection.performanceTrace,
      () => _performanceTrace(target, correlationId, selection.duration),
      visualPolicy: true,
    );

    final manifest = AndroidEvidenceManifest(
      correlationId: correlationId,
      targetId: target.serial,
      environment: environment,
      containmentReportDigest: containment.digest,
      collectedAt: collectedAt,
      syntheticDataConfirmed: selection.syntheticDataConfirmed,
      observations: observations,
    );
    final manifestBytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(manifest.toJson())}\n',
    );
    late final Digest manifestBlobDigest;
    store.withExclusiveLock(() {
      manifestBlobDigest = store.putBlob(manifestBytes);
      store.rebuildCasIndex();
    });
    collected.add(
      _AndroidCollectedArtifact(
        Artifact(
          digest: manifestBlobDigest,
          size: manifestBytes.length,
          mediaType: 'application/vnd.devex.android-evidence-manifest.v1+json',
          classification: ArtifactClassification.internal,
          role: 'android.environment',
        ),
      ),
    );
    final collectedCapabilities = <String>{
      'android.evidence.manifest',
      for (final observation in observations)
        if (observation.status == AndroidEvidenceStatus.collected)
          observation.role,
    };
    final fingerprint = ExecutionFingerprint(
      catalogDigest: catalogDigest,
      launchProfileId: launchProfileId,
      targetId: target.serial,
      platform: 'androidEmulator',
      renderer: environment.renderer,
      runtimeFidelity: RuntimeFidelity.hostNative,
      backendMode: backendMode,
      networkContainment: containment.networkContainment,
      bootstrapAssessment: BootstrapAssessment.controlled,
      toolchain: environment.toolchain,
      capabilities: collectedCapabilities,
      inputDigests: <String, Digest>{
        ...inputDigests,
        'android.environment': environment.digest,
        'android.containment': containment.digest,
      },
      policies: <String, String>{
        'evidence': 'android-native-v1',
        'data': selection.syntheticDataConfirmed
            ? 'synthetic-confirmed'
            : 'hashed-observations-only',
      },
      sourceRevision: sourceRevision,
    );
    final evidence = Evidence(
      id: 'evidence-${ids.nextId()}',
      subjectDigest: catalogDigest,
      fingerprint: fingerprint,
      observedAt: collectedAt,
      policyId: 'android-native-v1',
      artifacts: collected.map((item) => item.artifact).toList(growable: false),
    );
    return AndroidEvidenceResult(evidence: evidence, manifest: manifest);
  }

  Future<AndroidDeviceEnvironment> _environment(
    AndroidTargetDescriptor target,
  ) async {
    Future<String> property(
      String name, {
      String fallback = 'unspecified',
    }) async {
      final output = await provider.runManagedAdb(target, <String>[
        'shell',
        'getprop',
        name,
      ]);
      final value = output.stdoutText.trim();
      if (value.contains('\u0000') || value.length > 512) {
        throw const FormatException('Android property is invalid');
      }
      return value.isEmpty ? fallback : value;
    }

    final buildFingerprint = await property('ro.build.fingerprint');
    final incremental = await property('ro.build.version.incremental');
    final renderer = await property(
      'debug.hwui.renderer',
      fallback: await property(
        'ro.boot.qemu.gltransport',
        fallback: 'platform-default',
      ),
    );
    final locale = await property('persist.sys.locale', fallback: 'und');
    final timezone = await property(
      'persist.sys.timezone',
      fallback: 'Etc/UTC',
    );
    final descriptor =
        '${target.avdName}|$buildFingerprint|api-${target.apiLevel}|${target.abi}';
    return AndroidDeviceEnvironment(
      imageDescriptor: descriptor,
      imageDigest: Digest.semantic(<String, Object?>{
        'avdName': target.avdName,
        'buildFingerprint': buildFingerprint,
        'apiLevel': target.apiLevel,
        'abi': target.abi,
      }),
      apiLevel: target.apiLevel,
      abi: target.abi,
      renderer: renderer,
      locale: locale,
      timezone: timezone,
      toolchain: <String, String>{
        'adb': await provider.adbVersion(),
        'androidBuild': incremental,
        'dart': Platform.version.split(' ').first,
      },
    );
  }

  List<int> _sanitizeSemantics(List<int> source) {
    if (source.isEmpty || source.length > 8 * 1024 * 1024) {
      throw const FormatException('Android semantics source size is invalid');
    }
    final text = utf8.decode(source, allowMalformed: false);
    final nodes = <Map<String, Object?>>[];
    final nodePattern = RegExp(r'<node\b([^>]*)>');
    final attributePattern = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
    for (final match in nodePattern.allMatches(text)) {
      if (nodes.length >= 100000) {
        throw const FormatException('Android semantics node limit exceeded');
      }
      final attributes = <String, String>{
        for (final attribute in attributePattern.allMatches(match.group(1)!))
          attribute.group(1)!: attribute.group(2)!,
      };
      final node = <String, Object?>{'sequence': nodes.length};
      final className = attributes['class'];
      if (className != null &&
          className.isNotEmpty &&
          className.length <= 512) {
        node['class'] = className;
      }
      for (final entry in const <String, String>{
        'resource-id': 'resourceIdDigest',
        'text': 'textDigest',
        'content-desc': 'contentDescriptionDigest',
      }.entries) {
        final value = attributes[entry.key];
        if (value != null && value.isNotEmpty) {
          node[entry.value] = Digest.bytes(utf8.encode(value)).value;
        }
      }
      for (final name in const <String>[
        'checkable',
        'checked',
        'clickable',
        'enabled',
        'focusable',
        'focused',
        'scrollable',
        'long-clickable',
        'password',
        'selected',
      ]) {
        final value = attributes[name];
        if (value == 'true' || value == 'false') node[name] = value == 'true';
      }
      final bounds = attributes['bounds'];
      if (bounds != null &&
          RegExp(r'^\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]$').hasMatch(bounds)) {
        node['bounds'] = bounds;
      }
      nodes.add(node);
    }
    if (nodes.isEmpty) {
      throw const FormatException('Android semantics contains no nodes');
    }
    final document = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'AndroidSemanticsSnapshot',
      'privacy': 'hashedTextV1',
      'nodes': nodes,
    };
    return utf8.encode('${const JcsCanonicalizer().canonicalize(document)}\n');
  }

  Future<_AndroidRawArtifact> _logcat(
    AndroidTargetDescriptor target,
    String packageName,
  ) async {
    final pidOutput = await provider.runManagedAdb(target, <String>[
      'shell',
      'pidof',
      packageName,
    ]);
    final pid = pidOutput.stdoutText.trim().split(RegExp(r'\s+')).first;
    if (!RegExp(r'^[0-9]{1,10}$').hasMatch(pid)) {
      throw StateError('Android package PID is unavailable');
    }
    final output = await provider.runManagedAdb(target, <String>[
      'logcat',
      '--pid=$pid',
      '-d',
      '-v',
      'threadtime',
      '-t',
      '2000',
    ], timeout: const Duration(seconds: 30));
    if (output.stdout.length > 8 * 1024 * 1024) {
      throw const FormatException('Android logcat is oversized');
    }
    final entries = <Map<String, Object?>>[];
    final pattern = RegExp(
      r'^\S+\s+\S+\s+\d+\s+\d+\s+([VDIWEAF])\s+([^:]{1,128}):\s?(.*)$',
    );
    for (final line in const LineSplitter().convert(output.stdoutText)) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final tag = match.group(2)!.trim();
      final message = match.group(3)!;
      entries.add(<String, Object?>{
        'sequence': entries.length,
        'priority': match.group(1),
        'tagDigest': Digest.bytes(utf8.encode(tag)).value,
        'messageDigest': Digest.bytes(utf8.encode(message)).value,
      });
    }
    final document = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'AndroidLogcatSnapshot',
      'privacy': 'hashedMessageV1',
      'entries': entries,
    };
    return _AndroidRawArtifact(
      bytes: utf8.encode(
        '${const JcsCanonicalizer().canonicalize(document)}\n',
      ),
      mediaType: 'application/vnd.devex.android-logcat.v1+json',
      classification: ArtifactClassification.internal,
    );
  }

  Future<_AndroidRawArtifact> _screenRecording(
    AndroidTargetDescriptor target,
    String correlationId,
    Duration duration,
  ) async {
    final remote = '/data/local/tmp/$correlationId.mp4';
    try {
      await provider.runManagedAdb(target, <String>[
        'shell',
        'screenrecord',
        '--time-limit',
        '${duration.inSeconds}',
        '--bit-rate',
        '4000000',
        remote,
      ], timeout: duration + const Duration(seconds: 20));
      final output = await provider.runManagedAdb(target, <String>[
        'exec-out',
        'cat',
        remote,
      ]);
      final bytes = output.stdout;
      if (bytes.length < 12 ||
          bytes.length > 128 * 1024 * 1024 ||
          String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
        throw const FormatException('Android recording is not a bounded MP4');
      }
      return _AndroidRawArtifact(
        bytes: bytes,
        mediaType: 'video/mp4',
        classification: ArtifactClassification.internal,
      );
    } finally {
      try {
        await provider.runManagedAdb(target, <String>[
          'shell',
          'rm',
          '-f',
          remote,
        ]);
      } on Object {
        // Collection status already records the modality failure.
      }
    }
  }

  Future<_AndroidRawArtifact> _performanceTrace(
    AndroidTargetDescriptor target,
    String correlationId,
    Duration duration,
  ) async {
    // Android's shell domain is permitted to create Perfetto output in this
    // dedicated directory; /data/local/tmp is denied by current SELinux policy
    // on API 35 images even though ordinary shell files work there.
    final remote = '/data/misc/perfetto-traces/$correlationId.perfetto-trace';
    try {
      await provider.runManagedAdb(target, <String>[
        'shell',
        'perfetto',
        '-o',
        remote,
        '-t',
        '${duration.inSeconds}s',
        'sched',
        'freq',
        'idle',
        'am',
        'wm',
        'gfx',
        'view',
      ], timeout: duration + const Duration(seconds: 20));
      final output = await provider.runManagedAdb(target, <String>[
        'exec-out',
        'cat',
        remote,
      ]);
      if (output.stdout.length < 16 ||
          output.stdout.length > 256 * 1024 * 1024) {
        throw const FormatException('Android Perfetto trace size is invalid');
      }
      return _AndroidRawArtifact(
        bytes: output.stdout,
        mediaType: 'application/vnd.google.perfetto-trace',
        classification: ArtifactClassification.internal,
      );
    } finally {
      try {
        await provider.runManagedAdb(target, <String>[
          'shell',
          'rm',
          '-f',
          remote,
        ]);
      } on Object {
        // Collection status already records the modality failure.
      }
    }
  }
}

final class _AndroidRawArtifact {
  const _AndroidRawArtifact({
    required this.bytes,
    required this.mediaType,
    required this.classification,
    this.png,
  });
  final List<int> bytes;
  final String mediaType;
  final ArtifactClassification classification;
  final PngCaptureInspection? png;
}

final class _AndroidCollectedArtifact {
  const _AndroidCollectedArtifact(this.artifact);
  final Artifact artifact;
}
