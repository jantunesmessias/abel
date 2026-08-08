import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _ShowcaseOptions.parse(arguments);
  final repository = _repositoryRoot();
  final flutterWorkspace = Directory(
    '${repository.path}/examples/sample_flutter',
  );
  final studioAssets = Directory(
    '${repository.path}/apps/devex_studio/build/jaspr',
  );
  final targetAssets = Directory('${flutterWorkspace.path}/build/web');
  _ensureLocalConfiguration(flutterWorkspace);

  if (options.buildStudio ||
      !File('${studioAssets.path}/index.html').existsSync()) {
    await _runChecked(
      'jaspr',
      const <String>['build'],
      workingDirectory: '${repository.path}/apps/devex_studio',
      label: 'Building the Jaspr Studio',
    );
  }

  if (options.buildTarget ||
      (!options.checkOnly &&
          _targetBuildRequired(repository, flutterWorkspace, targetAssets))) {
    await _runChecked(
      'flutter',
      const <String>[
        'build',
        'web',
        '--release',
        '--target=tool/devex_main.dart',
        '--dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181',
        '--dart-define=DEVEX_CONTROLLER_ORIGIN=http://127.0.0.1:7368',
      ],
      workingDirectory: flutterWorkspace.path,
      label: 'Building the precompiled Flutter Target',
    );
  } else if (options.checkOnly &&
      _targetBuildRequired(repository, flutterWorkspace, targetAssets)) {
    stdout.writeln(
      'The precompiled Flutter Target is missing or stale. '
      'Run without --check, or pass --build-target, before starting it.',
    );
  }

  final compilation = await _runJson(
    Platform.resolvedExecutable,
    <String>[
      'run',
      'apps/devex_cli/bin/devex.dart',
      '--json',
      'compile',
      '--config',
      'examples/sample_flutter/devex.yaml',
    ],
    workingDirectory: repository.path,
    label: 'Compiling the showcase catalog and Gateway presets',
  );
  _printGatewayPlans(compilation);
  if (options.checkOnly) {
    stdout.writeln(
      'Showcase configuration is valid. No services were started.',
    );
    return;
  }

  for (final port in const <int>[8181, 7367, 7368, 8080]) {
    await _requireAvailablePort(port);
  }

  final processes = <Process>[];
  final stopping = Completer<void>();
  Future<void> stopProcesses() async {
    final current = processes.reversed.toList(growable: false);
    processes.clear();
    for (final process in current) {
      process.kill(ProcessSignal.sigint);
    }
    for (final process in current) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
      }
    }
  }

  Future<void> shutdown() async {
    if (!stopping.isCompleted) stopping.complete();
    await stopProcesses();
  }

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown())),
  ];
  try {
    var generation = 0;
    while (!stopping.isCompleted) {
      if (generation > 0) {
        await _waitForAvailablePorts(const <int>[8181, 7367, 7368, 8080]);
      }
      final generationEnded = Completer<void>();
      final failure = Completer<String>();
      try {
        final api = await Process.start(
          Platform.resolvedExecutable,
          const <String>[
            'run',
            'examples/sample_api/bin/server.dart',
            '--port',
            '8181',
          ],
          workingDirectory: repository.path,
        );
        processes.add(api);
        _forwardErrors(api, 'sample-api');
        await _watchForReadiness(api, label: 'sample-api');
        await _waitForHealth(Uri.parse('http://127.0.0.1:8181/health'));

        final devexArguments = <String>[
          'run',
          'apps/devex_cli/bin/devex.dart',
          '--json',
          'dev',
          '--config',
          'examples/sample_flutter/devex.yaml',
          '--host-port',
          '7367',
          '--studio-port',
          '7368',
          '--studio-assets',
          studioAssets.path,
          if (options.noOpen || generation > 0) '--no-open',
        ];
        final devex = await Process.start(
          Platform.resolvedExecutable,
          devexArguments,
          workingDirectory: repository.path,
        );
        processes.add(devex);
        _forwardErrors(devex, 'devex');
        final ready = await _watchForReadiness(devex, label: 'devex');
        final result = ready['result']! as Map<String, Object?>;

        stdout.writeln();
        stdout.writeln(
          generation == 0
              ? 'DevExKit complete showcase is ready:'
              : 'DevExKit complete showcase recovered (generation ${generation + 1}):',
        );
        stdout.writeln('  Studio: ${result['studioOrigin']}');
        stdout.writeln('  Host:   ${result['hostOrigin']}');
        stdout.writeln('  API:    http://127.0.0.1:8181');
        stdout.writeln(
          '  Target: http://127.0.0.1:8080 '
          '(prebuilt release assets, started from Studio)',
        );
        stdout.writeln();
        stdout.writeln(
          'All packaged modules are enabled by profile full-local.',
        );
        stdout.writeln(
          'A watchdog will restart the local stack after a process exit or '
          'three failed health probes.',
        );
        stdout.writeln(
          'Press Ctrl+C to stop the API, Host, Studio and managed targets.',
        );

        void watchExit(Process process, String label) {
          unawaited(
            process.exitCode.then((code) {
              if (!stopping.isCompleted && !failure.isCompleted) {
                failure.complete('$label exited unexpectedly with code $code');
              }
            }),
          );
        }

        watchExit(api, 'sample-api');
        watchExit(devex, 'devex');
        unawaited(
          _watchHealth(<Uri>[
            Uri(scheme: 'http', host: '127.0.0.1', port: 8181, path: '/health'),
            Uri(scheme: 'http', host: '127.0.0.1', port: 7367, path: '/health'),
            Uri(scheme: 'http', host: '127.0.0.1', port: 7368, path: '/health'),
          ], generationEnded.future).then((message) {
            if (message != null &&
                !stopping.isCompleted &&
                !failure.isCompleted) {
              failure.complete(message);
            }
          }),
        );
        await Future.any<void>(<Future<void>>[
          stopping.future,
          failure.future.then((message) {
            stderr.writeln('[showcase-watchdog] $message; restarting stack.');
          }),
        ]);
      } on Object catch (error, stackTrace) {
        if (!stopping.isCompleted) {
          stderr.writeln('[showcase-watchdog] startup failed: $error');
          stderr.writeln(stackTrace);
        }
      } finally {
        if (!generationEnded.isCompleted) generationEnded.complete();
        await stopProcesses();
      }
      if (!stopping.isCompleted) {
        generation += 1;
        final delay = Duration(seconds: generation > 5 ? 5 : generation);
        await Future.any<void>(<Future<void>>[
          stopping.future,
          Future<void>.delayed(delay),
        ]);
      }
    }
  } finally {
    await shutdown();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
  }
}

Directory _repositoryRoot() {
  var current = File.fromUri(Platform.script).parent;
  while (current.parent.path != current.path) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('DevExKit repository root not found');
}

void _ensureLocalConfiguration(Directory workspace) {
  final local = File('${workspace.path}/devex.local.yaml');
  if (local.existsSync()) return;
  final template = File('${workspace.path}/devex.local.example.yaml');
  if (!template.existsSync()) {
    throw FileSystemException(
      'Missing local configuration template',
      template.path,
    );
  }
  local.writeAsBytesSync(template.readAsBytesSync(), flush: true);
  stdout.writeln(
    'Created ignored devex.local.yaml from the safe loopback template.',
  );
}

bool _targetBuildRequired(
  Directory repository,
  Directory workspace,
  Directory targetAssets,
) {
  final index = File('${targetAssets.path}/index.html');
  if (!index.existsSync()) return true;
  final builtAt = index.lastModifiedSync();
  final inputs = <File>[
    File('${workspace.path}/pubspec.yaml'),
    File('${repository.path}/pubspec.lock'),
    File('${workspace.path}/tool/devex_main.dart'),
    ..._sourceFiles(Directory('${workspace.path}/lib')),
    ..._sourceFiles(Directory('${workspace.path}/web')),
  ];
  return inputs.any(
    (input) => input.existsSync() && input.lastModifiedSync().isAfter(builtAt),
  );
}

Iterable<File> _sourceFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) yield entity;
  }
}

Future<void> _requireAvailablePort(int port) async {
  ServerSocket? socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException {
    throw StateError('Required showcase port $port is already in use');
  } finally {
    await socket?.close();
  }
}

Future<void> _waitForAvailablePorts(List<int> ports) async {
  Object? lastError;
  for (var attempt = 0; attempt < 50; attempt += 1) {
    try {
      for (final port in ports) {
        await _requireAvailablePort(port);
      }
      return;
    } on Object catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('Showcase ports were not released: $lastError');
}

Future<String?> _watchHealth(
  List<Uri> healthUris,
  Future<void> generationEnded,
) async {
  var ended = false;
  unawaited(generationEnded.then((_) => ended = true));
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = const Duration(seconds: 2);
  var consecutiveFailures = 0;
  try {
    while (!ended) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (ended) return null;
      final failed = <Uri>[];
      for (final uri in healthUris) {
        try {
          final request = await client.getUrl(uri);
          final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
          await response.drain<void>();
          if (response.statusCode != HttpStatus.ok) failed.add(uri);
        } on Object {
          failed.add(uri);
        }
      }
      if (failed.isEmpty) {
        consecutiveFailures = 0;
        continue;
      }
      consecutiveFailures += 1;
      if (consecutiveFailures >= 3) {
        return 'health probes failed three times for '
            '${failed.map((uri) => uri.origin).join(', ')}';
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _watchForReadiness(
  Process process, {
  required String label,
}) {
  final ready = Completer<Map<String, Object?>>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      stdout.writeln('[$label] $line');
      if (ready.isCompleted) return;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?> &&
            decoded['ok'] != false &&
            (decoded['status'] == 'ready' ||
                (decoded['result'] as Map<String, Object?>?)?['status'] ==
                    'ready')) {
          ready.complete(decoded);
        }
      } on FormatException {
        // Tooling may emit non-JSON progress before its canonical ready line.
      }
    },
  );
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('$label exited with $code before reporting readiness'),
        );
      }
    }),
  );
  return ready.future.timeout(const Duration(minutes: 2));
}

void _forwardErrors(Process process, String label) {
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln('[$label] $line'));
}

Future<void> _waitForHealth(Uri uri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return;
      } on SocketException {
        // The process has reported readiness, but the listener may need one
        // more scheduler turn before accepting the probe.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Health endpoint did not become ready: $uri');
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _runJson(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  stdout.writeln('$label…');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}\n${result.stdout}',
      result.exitCode,
    );
  }
  final decoded = jsonDecode((result.stdout as String).trim());
  if (decoded is! Map<String, Object?> || decoded['ok'] != true) {
    throw StateError('$label failed: ${result.stdout}');
  }
  return decoded;
}

Future<void> _runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  stdout.writeln('$label…');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, label, exitCode);
  }
}

void _printGatewayPlans(Map<String, Object?> compilation) {
  final result = compilation['result']! as Map<String, Object?>;
  final plans = result['gatewayPlans']! as List<Object?>;
  stdout.writeln('Gateway plans persisted in the consumer CAS:');
  for (final raw in plans.cast<Map<String, Object?>>()) {
    stdout.writeln(
      '  ${raw['presetId']}: ${raw['artifactDigest']} '
      '(plan ${raw['planDigest']})',
    );
  }
}

final class _ShowcaseOptions {
  const _ShowcaseOptions({
    required this.buildStudio,
    required this.buildTarget,
    required this.noOpen,
    required this.checkOnly,
  });

  final bool buildStudio;
  final bool buildTarget;
  final bool noOpen;
  final bool checkOnly;

  factory _ShowcaseOptions.parse(List<String> arguments) {
    final supported = const <String>{
      '--build-studio',
      '--build-target',
      '--no-open',
      '--check',
    };
    final unknown = arguments.where(
      (argument) => !supported.contains(argument),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown showcase option ${unknown.first}');
    }
    return _ShowcaseOptions(
      buildStudio: arguments.contains('--build-studio'),
      buildTarget: arguments.contains('--build-target'),
      noOpen: arguments.contains('--no-open'),
      checkOnly: arguments.contains('--check'),
    );
  }
}
