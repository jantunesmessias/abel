import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('workspace-configuration-');
    Directory(p.join(temporary.path, '.experience')).createSync();
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test('rejects the unpublished consumer configuration revision', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 1
content: {root: .experience}
workspace: {id: sample}
applications: {}
''');

    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('schemaVersion must equal 2'),
        ),
      ),
    );
  });

  test('loads every canonical consumer layout fixture', () {
    final fixtures =
        <
          String,
          ({
            String configFile,
            String contentRoot,
            String workspaceId,
            int apps,
          })
        >{
          'default/workspace.yaml': (
            configFile: 'workspace.yaml',
            contentRoot: '.experience',
            workspaceId: 'sample',
            apps: 1,
          ),
          'monorepo/workspace.yaml': (
            configFile: 'workspace.yaml',
            contentRoot: 'experiences',
            workspaceId: 'sample-suite',
            apps: 2,
          ),
          'custom/helix.yaml': (
            configFile: 'helix.yaml',
            contentRoot: '.helix',
            workspaceId: 'sample',
            apps: 1,
          ),
        };
    final fixtureRoot = p.join(
      _repositoryRoot(),
      'tests',
      'fixtures',
      'layouts',
    );

    for (final entry in fixtures.entries) {
      final workspace = Directory(
        p.join(temporary.path, entry.key.replaceAll('/', '-')),
      )..createSync();
      final expected = entry.value;
      final configuration = File(p.join(workspace.path, expected.configFile))
        ..writeAsBytesSync(
          File(p.join(fixtureRoot, entry.key)).readAsBytesSync(),
        );
      Directory(p.join(workspace.path, expected.contentRoot)).createSync();

      final loaded = const WorkspaceConfigurationLoader().load(
        startPath: workspace.path,
        explicitConfigPath: configuration.path,
      );

      expect(p.basename(loaded.configPath), expected.configFile);
      expect(loaded.layout.contentRoot, expected.contentRoot);
      expect(loaded.workspaceId, expected.workspaceId);
      expect(loaded.applications, hasLength(expected.apps));
    }
  });

  test('rejects distribution fields without a canonical consumer', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
distribution: {id: sample, path: tools/sample}
content: {root: .experience}
workspace: {id: sample}
applications: {}
kit: {modules: {}}
''');

    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsFormatException,
    );
  });

  test('applies profile, workspace, local, and startup precedence', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications:
  app: {root: apps/app, target: web}
kit:
  profile: journey-preview
  modules:
    evidence.auto-preview:
      enabled: true
      settings:
        capture: {renderer: flutter-test, policy: workspace}
''');
    File(p.join(temporary.path, 'workspace.local.yaml')).writeAsStringSync('''
schemaVersion: 2
kit:
  modules:
    evidence.auto-preview:
      enabled: true
      settings:
        capture: {policy: local}
''');

    final loaded = const WorkspaceConfigurationLoader().load(
      startPath: temporary.path,
      startupSelection: KitSelection(
        modules: <KitModuleSelection>[
          KitModuleSelection(
            moduleId: ModuleId('evidence.auto-preview'),
            enabled: true,
            settings: const <String, Object?>{
              'capture': <String, Object?>{'parallelism': 2},
            },
          ),
        ],
      ),
    );
    final plan = loaded.kitPlanRequest.resolve(
      catalog: _catalog(),
      configurationSchemas: <String, Object?>{
        _previewSchemaId: <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['capture'],
          'properties': <String, Object?>{
            'capture': <String, Object?>{
              'type': 'object',
              'additionalProperties': false,
              'required': <String>['renderer', 'policy', 'parallelism'],
              'properties': <String, Object?>{
                'renderer': <String, Object?>{'type': 'string'},
                'policy': <String, Object?>{'const': 'local'},
                'parallelism': <String, Object?>{'const': 2},
              },
            },
          },
        },
      },
    );

    expect(loaded.localDocumentDigest, isNotNull);
    expect(plan.enabledModules.single.settings, <String, Object?>{
      'capture': <String, Object?>{
        'parallelism': 2,
        'policy': 'local',
        'renderer': 'flutter-test',
      },
    });
  });

  test('canonical documents and plans ignore map order', () {
    final other = Directory.systemTemp.createTempSync('workspace-order-');
    addTearDown(() => other.deleteSync(recursive: true));
    Directory(p.join(other.path, '.experience')).createSync();
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync(
      _v2Config(settings: 'renderer: flutter-test\npolicy: static-v1'),
    );
    File(p.join(other.path, 'workspace.yaml')).writeAsStringSync(
      _v2Config(settings: 'policy: static-v1\nrenderer: flutter-test'),
    );

    final first = const WorkspaceConfigurationLoader().load(
      startPath: temporary.path,
    );
    final second = const WorkspaceConfigurationLoader().load(
      startPath: other.path,
    );

    expect(first.documentDigest, second.documentDigest);
    expect(
      first.kitPlanRequest
          .resolve(
            catalog: _catalog(),
            configurationSchemas: <String, Object?>{
              _previewSchemaId: _permissivePreviewSchema,
            },
          )
          .digest,
      second.kitPlanRequest
          .resolve(
            catalog: _catalog(),
            configurationSchemas: <String, Object?>{
              _previewSchemaId: _permissivePreviewSchema,
            },
          )
          .digest,
    );
  });

  test('loads confined v2 LaunchProfiles for the development Host', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications:
  app: {root: ., target: web}
launchProfiles:
  sample-web:
    applicationId: app
    platform: web
    command: flutter
    arguments: [run, -d, web-server, --web-port=8080]
    workingDirectory: .
    overlay: {SAMPLE_MODE: full}
    bootstrapPolicy: {api: production, gateway: overlay}
kit: {profile: journey-preview, modules: {}}
''');

    final loaded = const WorkspaceConfigurationLoader().load(
      startPath: temporary.path,
    );

    expect(loaded.launchProfiles, hasLength(1));
    final profile = loaded.launchProfiles.single;
    expect(profile.id, 'sample-web');
    expect(profile.applicationId, ApplicationId('app'));
    expect(profile.platform, TargetPlatform.web);
    expect(profile.arguments, contains('--web-port=8080'));
    expect(profile.overlay.values, {'SAMPLE_MODE': 'full'});
    expect(
      profile.bootstrapPolicy.dependencies,
      <String, BootstrapDependencyPolicy>{
        'api': BootstrapDependencyPolicy.production,
        'gateway': BootstrapDependencyPolicy.overlay,
      },
    );
  });

  test('rejects LaunchProfiles that reference unknown applications', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications: {}
launchProfiles:
  sample-web:
    applicationId: missing
    platform: web
    command: flutter
    arguments: []
    workingDirectory: .
kit: {modules: {}}
''');

    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unknown Application missing'),
        ),
      ),
    );
  });

  test('rejects v2 traversal and literal secrets before resolution', () {
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: ../outside}
workspace: {id: sample}
applications: {}
kit: {modules: {}}
''');
    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(isA<FormatException>()),
    );

    File(
      p.join(temporary.path, 'workspace.yaml'),
    ).writeAsStringSync(_v2Config(settings: 'accessToken: plain-text'));
    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('literal secret forbidden'),
        ),
      ),
    );
  });

  test('rejects symlinked main and local configuration', () {
    final actualMain = File(p.join(temporary.path, 'actual.yaml'))
      ..writeAsStringSync(
        _v2Config(settings: 'renderer: flutter-test\npolicy: static-v1'),
      );
    Link(p.join(temporary.path, 'workspace.yaml')).createSync(actualMain.path);
    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(isA<FileSystemException>()),
    );

    Link(p.join(temporary.path, 'workspace.yaml')).deleteSync();
    File(p.join(temporary.path, 'workspace.yaml')).writeAsStringSync(
      _v2Config(settings: 'renderer: flutter-test\npolicy: static-v1'),
    );
    final localTarget = File(p.join(temporary.path, 'actual-local.yaml'))
      ..writeAsStringSync('schemaVersion: 1\ngateway: {}\n');
    Link(
      p.join(temporary.path, 'workspace.local.yaml'),
    ).createSync(localTarget.path);
    expect(
      () =>
          const WorkspaceConfigurationLoader().load(startPath: temporary.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}

const _previewSchemaId = 'urn:test:auto-preview-settings:v1';

const Map<String, Object?> _permissivePreviewSchema = <String, Object?>{
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['capture'],
  'properties': <String, Object?>{
    'capture': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['renderer', 'policy'],
      'properties': <String, Object?>{
        'renderer': <String, Object?>{'type': 'string'},
        'policy': <String, Object?>{'type': 'string'},
      },
    },
  },
};

ModuleCatalog _catalog() => ModuleCatalog(
  distributionId: 'full-local',
  coreVersion: '0.1.0',
  platform: 'linux-x64',
  modules: <ModuleDescriptor>[
    ModuleDescriptor(
      id: ModuleId('catalog'),
      version: '1.0.0',
      coreCompatibility: '^0.1.0',
      provides: <ModuleCapabilityRef>[
        ModuleCapabilityRef(id: 'catalog.read', version: 1),
      ],
      supportedPlatforms: const <String>{'any'},
    ),
    ModuleDescriptor(
      id: ModuleId('evidence.auto-preview'),
      version: '1.0.0',
      coreCompatibility: '^0.1.0',
      provides: <ModuleCapabilityRef>[
        ModuleCapabilityRef(id: 'evidence.visual', version: 1),
      ],
      supportedPlatforms: const <String>{'any'},
      configurationSchema: _previewSchemaId,
    ),
  ],
  profiles: <KitProfile>[
    KitProfile(
      id: 'journey-preview',
      displayName: 'Journey Preview',
      selection: KitSelection(
        modules: <KitModuleSelection>[
          KitModuleSelection(
            moduleId: ModuleId('evidence.auto-preview'),
            enabled: true,
            settings: const <String, Object?>{
              'capture': <String, Object?>{'renderer': 'profile'},
            },
          ),
        ],
      ),
    ),
  ],
  defaultProfileId: 'journey-preview',
);

String _v2Config({required String settings}) {
  final indentedSettings = settings
      .split('\n')
      .map((line) => '          $line')
      .join('\n');
  return '''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications: {}
kit:
  profile: journey-preview
  modules:
    evidence.auto-preview:
      enabled: true
      settings:
        capture:
$indentedSettings
''';
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(current.path, 'apps')).existsSync() &&
        Directory(p.join(current.path, 'libs')).existsSync()) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = parent;
  }
}
