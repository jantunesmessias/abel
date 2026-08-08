import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw const FormatException(
      'Usage: prepare_external_distribution_consumer <external-root>',
    );
  }
  final repository = _repositoryRoot();
  final external = Directory(arguments.single).absolute;
  if (external.existsSync() || Link(external.path).existsSync()) {
    throw FileSystemException('External consumer root already exists');
  }
  external.createSync(recursive: true);
  final libraries = Directory(p.join(external.path, 'libs'))..createSync();
  for (final name in const <String>[
    'experience_contracts',
    'experience_engine',
    'execution_runtime',
  ]) {
    _copyPackage(
      Directory(p.join(repository, 'libs', name)),
      Directory(p.join(libraries.path, name)),
    );
  }

  final consumer = Directory(p.join(external.path, 'consumer'))..createSync();
  Directory(p.join(consumer.path, 'bin')).createSync();
  File(p.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: acme_distribution_composer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  experience_contracts:
    path: ../libs/experience_contracts
  execution_runtime:
    path: ../libs/execution_runtime
''');
  File(p.join(consumer.path, 'bin', 'compose.dart')).writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:execution_runtime/execution_runtime.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw const FormatException('Usage: compose <base> <output> <version>');
  }
  final spec = ConsumerDistributionSpec(
    distribution: DistributionDescriptor(
      id: 'acme-experience',
      displayName: 'Acme Experience Platform',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
      commandAliases: const <String>['acme-experience'],
    ),
    releaseVersion: arguments[2],
    profileId: 'gateway-lab-headless',
    studioAssets: ConsumerStudioAssets.absent,
    compatibility: ConsumerDistributionCompatibility(
      coreCompatibility: '^0.1.0',
    ),
  );
  final result = await const LocalConsumerDistributionComposer().compose(
    baseBundleDirectory: arguments[0],
    consumerWorkspaceDirectory: Directory.current.parent.path,
    specification: spec,
    outputDirectory: arguments[1],
    configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
  );
  stdout.writeln(jsonEncode(result.toJson()));
}
''');

  final content = Directory(p.join(external.path, '.experience'))..createSync();
  File(p.join(external.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
distribution: {id: acme-experience}
content: {root: .experience}
workspace:
  id: acme-workspace
  displayName: Acme External Workspace
applications:
  acme-app:
    root: .
    target: web
    displayName: Acme Application
kit:
  profile: gateway-lab-headless
  modules: {}
  providerBindings: []
  startupPolicy: fail-required-v1
''');
  File(p.join(content.path, 'ready.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata:
  id: acme-ready
spec:
  applicationId: acme-app
  title: Acme is ready
  description: Consumer-owned content compiled outside the Abel monorepo.
''');
  File(p.join(content.path, 'journey.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata:
  id: acme-delivery
spec:
  applicationId: acme-app
  title: Acme delivery
  scenarioIds: [acme-ready]
''');

  await _run('dart', const <String>['pub', 'get'], consumer.path);
  await _run('dart', const <String>[
    'analyze',
    '--fatal-infos',
    '--fatal-warnings',
  ], consumer.path);
}

void _copyPackage(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (p
        .split(relative)
        .any((segment) => segment == '.dart_tool' || segment == 'build')) {
      continue;
    }
    if (entity is Link) throw StateError('Public package contains a symlink');
    final destination = p.join(target.path, relative);
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      File(destination).parent.createSync(recursive: true);
      entity.copySync(destination);
    }
  }
  final pubspec = File(p.join(target.path, 'pubspec.yaml'));
  var sourceText = pubspec.readAsStringSync().replaceFirst(
    RegExp(r'^resolution: workspace\s*$', multiLine: true),
    '',
  );
  for (final dependency in const <String>[
    'experience_contracts',
    'experience_engine',
  ]) {
    sourceText = sourceText.replaceFirst(
      RegExp('^  $dependency: [^\\n]+\$', multiLine: true),
      '  $dependency:\n    path: ../$dependency',
    );
  }
  pubspec.writeAsStringSync(sourceText);
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
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed: $exitCode');
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
