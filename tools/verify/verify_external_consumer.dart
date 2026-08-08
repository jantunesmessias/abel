import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final repository = _repositoryRoot();
  final temporary =
      arguments.isEmpty
            ? Directory.systemTemp.createTempSync(
                'experience-external-consumer-',
              )
            : Directory(arguments.single)
        ..createSync(recursive: true);
  final ownsTemporary = arguments.isEmpty;
  try {
    final copied = Directory(p.join(temporary.path, 'libs'))..createSync();
    const packageNames = <String>[
      'experience_contracts',
      'experience_engine',
      'execution_runtime',
      'flutter_app_adapter',
      'testing_support',
    ];
    for (final name in packageNames) {
      _copyPackage(
        Directory(p.join(repository, 'libs', name)),
        Directory(p.join(copied.path, name)),
      );
    }
    final consumer = Directory(p.join(temporary.path, 'consumer'))
      ..createSync();
    Directory(p.join(consumer.path, 'lib')).createSync();
    Directory(p.join(consumer.path, 'test')).createSync();
    File(p.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: experience_external_consumer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  experience_contracts:
    path: ../libs/experience_contracts
  experience_engine:
    path: ../libs/experience_engine
  execution_runtime:
    path: ../libs/execution_runtime
  flutter_app_adapter:
    path: ../libs/flutter_app_adapter
  testing_support:
    path: ../libs/testing_support
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    File(p.join(consumer.path, 'lib', 'public_api.dart')).writeAsStringSync('''
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:execution_runtime/execution_runtime.dart';
import 'package:testing_support/testing_support.dart';

Object publicApiSmoke() {
  final Clock clock = FakeClock(DateTime.utc(2026));
  return <Object>[
    Digest.semantic('external-consumer'),
    ConsumerLayout.standard,
    SystemClock(),
    clock,
    TargetBinding(
      sessionId: 'external-session',
      nonce: '0123456789abcdef',
      runtimeConfiguration: const <String, String>{},
      capabilities: const <String>{},
    ),
  ];
}
''');
    File(
      p.join(consumer.path, 'test', 'public_api_test.dart'),
    ).writeAsStringSync('''
import 'package:experience_external_consumer/public_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('published public libraries resolve outside the workspace', () {
    expect(publicApiSmoke(), isNotEmpty);
  });
}
''');
    await _run('flutter', const <String>['pub', 'get'], consumer.path);
    await _run('flutter', const <String>[
      'analyze',
      '--fatal-infos',
      '--fatal-warnings',
    ], consumer.path);
    await _run('flutter', const <String>['test'], consumer.path);
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'externalConsumer': true,
        'packages': packageNames,
        'analyze': 'passed',
        'tests': 'passed',
      }),
    );
  } finally {
    if (ownsTemporary && temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  }
}

void _copyPackage(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final segments = p.split(relative);
    if (segments.any(
      (segment) => segment == '.dart_tool' || segment == 'build',
    )) {
      continue;
    }
    if (entity is Link) throw StateError('Package source contains a symlink');
    final destination = p.join(target.path, relative);
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      File(destination).parent.createSync(recursive: true);
      entity.copySync(destination);
    }
  }
  final pubspec = File(p.join(target.path, 'pubspec.yaml'));
  var pubspecSource = pubspec.readAsStringSync().replaceFirst(
    RegExp(r'^resolution: workspace\s*$', multiLine: true),
    '',
  );
  for (final dependency in <String>[
    'experience_contracts',
    'experience_engine',
    'execution_runtime',
    'flutter_app_adapter',
    'testing_support',
  ]) {
    pubspecSource = pubspecSource.replaceFirst(
      RegExp('^  $dependency: [^\\n]+\$', multiLine: true),
      '  $dependency:\n    path: ../$dependency',
    );
  }
  pubspec.writeAsStringSync(pubspecSource);
}

Future<void> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed: $code');
  }
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
