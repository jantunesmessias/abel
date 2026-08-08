import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'accepts immediately emitted child-bound readiness and captures it',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-managed-target-',
      );
      addTearDown(() {
        if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      });
      final script = File(p.join(temporary.path, 'target.dart'))
        ..writeAsStringSync(_targetScript);
      final exit = Completer<String>();
      final supervisor = ManagedProcessSupervisor(
        workspaceRoot: temporary.path,
        onExit: (_, _, stdoutTail, _) => exit.complete(stdoutTail),
      );
      addTearDown(supervisor.close);
      final profile = _profile(temporary, script);
      final attempt = TargetLaunchAttemptId('attempt_0123456789abcdef');

      final record = await supervisor.startTarget(
        'run-1',
        profile,
        targetId: 'sample-web',
        launchAttemptId: attempt,
        timeout: const Duration(seconds: 10),
      );

      expect(record.launchAttemptId, attempt);
      expect(record.targetId, 'sample-web');
      expect(record.launchProfileId, profile.id);
      expect(record.origin.host, '127.0.0.1');
      expect(record.origin.port, greaterThan(0));
      expect(supervisor.activeCount, 1);
      await supervisor.stop('run-1');
      expect(supervisor.activeCount, 0);
      final stdoutTail = await exit.future;
      final lines = const LineSplitter().convert(stdoutTail);
      expect(
        jsonDecode(lines.first),
        containsPair('kind', 'TargetReadinessRecord'),
      );
      expect(lines, contains('target post-readiness log'));
    },
  );

  test(
    'rejects a readiness record that does not bind its child process',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-managed-target-invalid-',
      );
      addTearDown(() {
        if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      });
      final script = File(p.join(temporary.path, 'target.dart'))
        ..writeAsStringSync(_targetScript);
      final supervisor = ManagedProcessSupervisor(
        workspaceRoot: temporary.path,
      );
      addTearDown(supervisor.close);
      final profile = _profile(
        temporary,
        script,
        overlay: const <String, String>{'TEST_MISMATCH_PID': 'true'},
      );

      await expectLater(
        supervisor.startTarget(
          'run-invalid',
          profile,
          targetId: 'sample-web',
          launchAttemptId: TargetLaunchAttemptId('attempt_0123456789abcdef'),
          timeout: const Duration(seconds: 10),
        ),
        throwsFormatException,
      );
      expect(supervisor.activeCount, 0);
    },
  );
}

LaunchProfile _profile(
  Directory temporary,
  File script, {
  Map<String, String> overlay = const <String, String>{},
}) => LaunchProfile(
  id: 'sample-web',
  applicationId: ApplicationId('sample'),
  platform: TargetPlatform.web,
  command: Platform.resolvedExecutable,
  arguments: <String>[
    '--packages=${p.join(_repositoryRoot(), '.dart_tool', 'package_config.json')}',
    script.path,
  ],
  workingDirectory: temporary.path,
  overlay: RuntimeConfigurationOverlay(overlay),
  bootstrapPolicy: ApplicationBootstrapPolicy(
    const <String, BootstrapDependencyPolicy>{},
  ),
);

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File(p.join(current.path, 'ARCHITECTURE.md')).existsSync()) {
      return current.path;
    }
    current = current.parent;
  }
  throw StateError('Repository root not found');
}

const String _targetScript = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = request.uri.path == '/health' ? 200 : 404;
    await request.response.close();
  });
  final record = TargetReadinessRecord(
    launchAttemptId: TargetLaunchAttemptId(
      Platform.environment['TARGET_LAUNCH_ATTEMPT_ID']!,
    ),
    targetId: Platform.environment['TARGET_ID']!,
    launchProfileId: Platform.environment['TARGET_LAUNCH_PROFILE_ID']!,
    origin: Uri.parse('http://${server.address.address}:${server.port}'),
    processId: Platform.environment['TEST_MISMATCH_PID'] == 'true'
        ? pid + 1
        : pid,
  );
  stdout.writeln(jsonEncode(record.toJson()));
  stdout.writeln('target post-readiness log');
  await Completer<void>().future;
}
''';
