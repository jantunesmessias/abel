import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

import '../static_web_origin_server.dart';
import '../system_clock.dart';
import '../targets/android_target_provider.dart';
import 'remote_worker_service.dart';
import 'scrcpy_remote_session.dart';

final class SystemRemoteWorkerConfiguration {
  const SystemRemoteWorkerConfiguration({
    this.chromiumExecutable,
    this.androidSdkRoot,
    this.androidAvdName,
    this.androidImageDigest,
    this.gatewayPort = 8443,
    this.webInteractivePort = 27184,
    this.periodicScreenshotInterval = const Duration(seconds: 2),
    this.scrcpyServerPath,
    this.scrcpyServerDigest,
    this.scrcpyVersion = '4.0',
    this.scrcpyPort = 27185,
  });

  final String? chromiumExecutable;
  final String? androidSdkRoot;
  final String? androidAvdName;
  final Digest? androidImageDigest;
  final int gatewayPort;
  final int webInteractivePort;
  final Duration periodicScreenshotInterval;
  final String? scrcpyServerPath;
  final Digest? scrcpyServerDigest;
  final String scrcpyVersion;
  final int scrcpyPort;
}

final class SystemRemoteWorkerBackend implements RemoteWorkerBackend {
  SystemRemoteWorkerBackend(this.configuration);

  final SystemRemoteWorkerConfiguration configuration;
  StaticWebOriginServer? _webServer;
  AndroidManagedEmulatorService? _emulator;
  RemoteWorkerInteractiveSession? _interactiveSession;

  @override
  Future<RemoteBackendResult> execute({
    required RemoteExecutionPlan plan,
    required Map<String, File> inputsByRole,
    required Directory workspace,
  }) => switch (plan.target) {
    RemoteTargetKind.web => _executeWeb(plan, inputsByRole, workspace),
    RemoteTargetKind.androidEmulator => _executeAndroid(
      plan,
      inputsByRole,
      workspace,
    ),
  };

  Future<RemoteBackendResult> _executeWeb(
    RemoteExecutionPlan plan,
    Map<String, File> inputs,
    Directory workspace,
  ) async {
    final chromium = configuration.chromiumExecutable;
    if (chromium == null || chromium.isEmpty) {
      throw StateError('web worker does not contain a configured Chromium');
    }
    final archive = inputs['webBuild'];
    if (archive == null) throw StateError('signed webBuild artifact is absent');
    final root = Directory(p.join(workspace.path, 'web-root'))..createSync();
    _extractWebArchive(archive, root);
    if (!File(p.join(root.path, 'index.html')).existsSync()) {
      throw StateError('webBuild does not contain a root index.html');
    }
    final instruction = _instruction(inputs['interactionScript']);
    _webServer = StaticWebOriginServer(rootDirectory: root.path);
    await _webServer!.start(
      port: plan.mode == RemoteRunMode.interactive
          ? configuration.webInteractivePort
          : 0,
    );
    final screenshot = File(p.join(workspace.path, 'web-screenshot.png'));
    final profile = Directory(p.join(workspace.path, 'chromium-profile'))
      ..createSync();
    await _checkedProcess(chromium, <String>[
      '--headless=new',
      '--disable-dev-shm-usage',
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-sync',
      '--metrics-recording-only',
      '--no-first-run',
      '--user-data-dir=${profile.path}',
      '--window-size=1440,1024',
      '--virtual-time-budget=${instruction.settleMilliseconds}',
      '--screenshot=${screenshot.path}',
      _webServer!.origin.toString(),
    ], timeout: const Duration(minutes: 2));
    _png(screenshot);
    final interactive =
        plan.interactiveTransport == RemoteInteractiveTransport.webDirect
        ? WebDirectRemoteInteractiveSession()
        : null;
    _interactiveSession = interactive;
    return RemoteBackendResult(
      artifacts: <RemoteGeneratedArtifact>[
        RemoteGeneratedArtifact(
          role: 'screenshot',
          file: screenshot,
          mediaType: 'image/png',
          classification: 'internal',
        ),
      ],
      interactiveTransport:
          interactive?.transport ?? RemoteInteractiveTransport.none,
      interactiveSession: interactive,
    );
  }

  Future<RemoteBackendResult> _executeAndroid(
    RemoteExecutionPlan plan,
    Map<String, File> inputs,
    Directory workspace,
  ) async {
    final sdkRoot = configuration.androidSdkRoot;
    final avdName = configuration.androidAvdName;
    final configuredImage = configuration.androidImageDigest;
    if (sdkRoot == null ||
        sdkRoot.isEmpty ||
        avdName == null ||
        avdName.isEmpty ||
        configuredImage == null) {
      throw StateError('Android worker runtime configuration is incomplete');
    }
    final image = plan.deviceImage;
    final apk = inputs['androidApk'];
    if (image == null || apk == null) {
      throw StateError('signed Android image or APK is absent');
    }
    if (image.imageDigest != configuredImage || !image.kvmRequired) {
      throw StateError('worker Android image does not match the signed plan');
    }
    final instruction = _instruction(inputs['interactionScript']);
    if (instruction.androidPackage == null ||
        instruction.androidActivity == null) {
      throw StateError('Android execution requires a signed component');
    }
    final provider = AndroidTargetProvider(sdkRoot: sdkRoot);
    _emulator = AndroidManagedEmulatorService(
      workspaceRoot: p.join(workspace.path, 'android-state'),
      provider: provider,
    );
    final started = await _emulator!.start(
      avdName: avdName,
      port: 5554,
      apply: true,
      headless: true,
      wipeData: true,
      renderer: image.renderer,
    );
    final target = started.target;
    if (target == null ||
        target.apiLevel != image.apiLevel ||
        target.abi != image.abi) {
      throw StateError('booted Android target differs from the signed image');
    }
    await provider.installApk(target.serial, apk.path);
    await provider.launch(
      target.serial,
      AndroidLaunchRequest(
        packageName: instruction.androidPackage!,
        activity: instruction.androidActivity!,
        pairing: AndroidGatewayPairing(
          strategy: AndroidGatewayRouteStrategy.emulatorHostAlias,
          hostPort: configuration.gatewayPort,
          targetPort: configuration.gatewayPort,
          tls: true,
        ),
        overlay: RuntimeConfigurationOverlay(const <String, String>{}),
      ),
    );
    await Future<void>.delayed(
      Duration(milliseconds: instruction.settleMilliseconds),
    );
    final screenshot = File(p.join(workspace.path, 'android-screenshot.png'));
    screenshot.writeAsBytesSync(await provider.capturePng(target.serial));
    _png(screenshot);
    final logcat = await provider.runManagedAdb(target, const <String>[
      'logcat',
      '-d',
      '-t',
      '2000',
      '-v',
      'threadtime',
    ], timeout: const Duration(seconds: 30));
    final logFile = File(p.join(workspace.path, 'android-logcat.txt'));
    logFile.writeAsStringSync(_sanitizeLogcat(logcat.stdoutText));
    RemoteWorkerInteractiveSession? interactive;
    if (plan.mode == RemoteRunMode.interactive) {
      final serverPath = configuration.scrcpyServerPath;
      final serverDigest = configuration.scrcpyServerDigest;
      if ((serverPath == null) != (serverDigest == null)) {
        throw StateError('scrcpy server path and digest must be paired');
      }
      interactive = switch (plan.interactiveTransport) {
        RemoteInteractiveTransport.periodicScreenshotReadOnly =>
          PeriodicScreenshotRemoteInteractiveSession(
            capture: () => provider.capturePng(target.serial),
            interval: configuration.periodicScreenshotInterval,
          ),
        RemoteInteractiveTransport.scrcpyH264Control when serverPath != null =>
          ScrcpyRemoteInteractiveSession(
            factory: SystemScrcpyTransportFactory(
              provider: provider,
              serverJar: File(serverPath),
              serverDigest: serverDigest!,
              version: configuration.scrcpyVersion,
              localPort: configuration.scrcpyPort,
            ),
            target: target,
            clock: SystemClock(),
          ),
        RemoteInteractiveTransport.scrcpyH264Control => throw StateError(
          'signed plan requires scrcpy but the worker image has no server',
        ),
        _ => throw StateError('Android interactive transport is invalid'),
      };
    }
    _interactiveSession = interactive;
    return RemoteBackendResult(
      artifacts: <RemoteGeneratedArtifact>[
        RemoteGeneratedArtifact(
          role: 'screenshot',
          file: screenshot,
          mediaType: 'image/png',
          classification: 'internal',
        ),
        RemoteGeneratedArtifact(
          role: 'logcat',
          file: logFile,
          mediaType: 'text/plain; charset=utf-8',
          classification: 'sensitive',
        ),
      ],
      interactiveTransport:
          interactive?.transport ?? RemoteInteractiveTransport.none,
      interactiveSession: interactive,
    );
  }

  void _extractWebArchive(File source, Directory destination) {
    final input = InputFileStream(source.path);
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > 10000) {
        throw StateError('webBuild contains too many entries');
      }
      var expandedBytes = 0;
      for (final entry in archive) {
        expandedBytes += entry.size;
        if (expandedBytes > 2 * 1024 * 1024 * 1024) {
          throw StateError('webBuild expanded size exceeds 2 GiB');
        }
        final canonical = entry.name.replaceAll('\\', '/');
        final normalized = p.posix.normalize(canonical);
        if (entry.isSymbolicLink ||
            canonical.contains('\u0000') ||
            normalized == '..' ||
            normalized.startsWith('../') ||
            normalized.startsWith('/') ||
            normalized != canonical.replaceFirst(RegExp(r'^\./'), '')) {
          throw StateError('webBuild contains an unsafe archive entry');
        }
      }
      for (final entry in archive) {
        final outputPath = p.joinAll(<String>[
          destination.path,
          ...entry.name.split('/'),
        ]);
        if (!p.isWithin(destination.path, outputPath)) {
          throw StateError('webBuild extraction escaped its destination');
        }
        if (entry.isDirectory) {
          Directory(outputPath).createSync(recursive: true);
        } else {
          final output = OutputFileStream(outputPath);
          entry.writeContent(output);
          output.closeSync();
        }
      }
    } finally {
      input.closeSync();
    }
  }

  _RemoteInstruction _instruction(File? file) {
    if (file == null) return const _RemoteInstruction(settleMilliseconds: 1000);
    if (file.lengthSync() > 1024 * 1024) {
      throw StateError('interactionScript exceeds 1 MiB');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['kind'] != 'RemoteInteractionScript') {
      throw const FormatException('interactionScript header is invalid');
    }
    final unknown = decoded.keys.toSet().difference(const <String>{
      'schemaVersion',
      'kind',
      'settleMilliseconds',
      'androidPackage',
      'androidActivity',
    });
    if (unknown.isNotEmpty) {
      throw const FormatException('interactionScript has unknown fields');
    }
    final settle = decoded['settleMilliseconds'];
    final package = decoded['androidPackage'];
    final activity = decoded['androidActivity'];
    if (settle is! int ||
        settle < 0 ||
        settle > 30000 ||
        package != null && package is! String ||
        activity != null && activity is! String) {
      throw const FormatException('interactionScript fields are invalid');
    }
    return _RemoteInstruction(
      settleMilliseconds: settle,
      androidPackage: package as String?,
      androidActivity: activity as String?,
    );
  }

  Future<void> _checkedProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final result = await Process.run(executable, arguments).timeout(timeout);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        'trusted remote runner exited with ${result.exitCode}',
        result.exitCode,
      );
    }
  }

  void _png(File file) {
    final bytes = file.readAsBytesSync();
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24 ||
        bytes.length > 64 * 1024 * 1024 ||
        !List<int>.generate(8, (index) => bytes[index]).asMap().entries.every(
          (entry) => entry.value == signature[entry.key],
        )) {
      throw StateError('remote screenshot is not a bounded lossless PNG');
    }
  }

  String _sanitizeLogcat(String input) => const LineSplitter()
      .convert(input)
      .take(2000)
      .map(
        (line) => line
            .replaceAll(
              RegExp(
                r'(authorization|cookie|token|secret)=?\s*[^\s,;]+',
                caseSensitive: false,
              ),
              r'$1=[REDACTED]',
            )
            .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[EMAIL]'),
      )
      .join('\n');

  @override
  Future<void> stop() async {
    await _interactiveSession?.stop();
    _interactiveSession = null;
    await _webServer?.close();
    _webServer = null;
    final emulator = _emulator;
    _emulator = null;
    if (emulator != null) await emulator.stop(apply: true);
  }
}

final class WebDirectRemoteInteractiveSession
    implements RemoteWorkerInteractiveSession {
  final Completer<void> _stopped = Completer<void>();

  @override
  RemoteInteractiveTransport get transport =>
      RemoteInteractiveTransport.webDirect;

  @override
  Future<void> run({
    required RemoteWorkerStreamClient stream,
    required DateTime deadline,
  }) async {
    await stream.publish(
      RemoteStreamChannel.metadataJson,
      utf8.encode(
        jsonEncode(const <String, Object?>{
          'schemaVersion': 1,
          'type': 'web.direct.ready',
        }),
      ),
    );
    await _waitForSessionEnd(stream, deadline, _stopped.future);
  }

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

final class PeriodicScreenshotRemoteInteractiveSession
    implements RemoteWorkerInteractiveSession {
  PeriodicScreenshotRemoteInteractiveSession({
    required this.capture,
    required this.interval,
  }) {
    if (interval <= Duration.zero || interval > const Duration(seconds: 10)) {
      throw ArgumentError('periodic screenshot interval is invalid');
    }
  }

  final Future<List<int>> Function() capture;
  final Duration interval;
  final Completer<void> _stopped = Completer<void>();

  @override
  RemoteInteractiveTransport get transport =>
      RemoteInteractiveTransport.periodicScreenshotReadOnly;

  @override
  Future<void> run({
    required RemoteWorkerStreamClient stream,
    required DateTime deadline,
  }) async {
    while (!_stopped.isCompleted && deadline.isAfter(DateTime.now().toUtc())) {
      await stream.publish(RemoteStreamChannel.screenshotPng, await capture());
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) break;
      await _waitForFirstOrTimeout(
        remaining < interval ? remaining : interval,
        <Future<void>>[_stopped.future, stream.done],
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

Future<void> _waitForSessionEnd(
  RemoteWorkerStreamClient stream,
  DateTime deadline,
  Future<void> stopped,
) async {
  final now = DateTime.now().toUtc();
  if (!deadline.isAfter(now)) return;
  final requestedEnd = Completer<void>();
  final subscription = stream.controlFrames.listen((frame) {
    if (frame.channel != RemoteStreamChannel.control ||
        frame.payload.length > 64 * 1024) {
      return;
    }
    try {
      final value = jsonDecode(utf8.decode(frame.payload));
      if (value is Map<String, Object?> &&
          value.keys.toSet().difference(const <String>{'type'}).isEmpty &&
          value['type'] == 'session.end' &&
          !requestedEnd.isCompleted) {
        requestedEnd.complete();
      }
    } on FormatException {
      // Invalid target controls are ignored; the gateway already bounds them.
    }
  });
  try {
    await _waitForFirstOrTimeout(deadline.difference(now), <Future<void>>[
      stopped,
      stream.done,
      requestedEnd.future,
    ]);
  } finally {
    await subscription.cancel();
  }
}

Future<void> _waitForFirstOrTimeout(
  Duration timeout,
  List<Future<void>> signals,
) async {
  if (timeout <= Duration.zero) return;
  final timedOut = Completer<void>();
  final timer = Timer(timeout, timedOut.complete);
  try {
    await Future.any<void>(<Future<void>>[timedOut.future, ...signals]);
  } finally {
    timer.cancel();
  }
}

final class _RemoteInstruction {
  const _RemoteInstruction({
    required this.settleMilliseconds,
    this.androidPackage,
    this.androidActivity,
  });

  final int settleMilliseconds;
  final String? androidPackage;
  final String? androidActivity;
}
