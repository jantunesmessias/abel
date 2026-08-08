import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('devex-plugin-test.'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test(
    'sandboxed plugin sees neither workspace file nor inherited secret',
    () async {
      final secret = File(p.join(temp.path, 'workspace-secret'))
        ..writeAsStringSync('secret');
      final script = File(p.join(temp.path, 'plugin.sh'));
      script.writeAsStringSync('''#!/usr/bin/bash
IFS= read -r first
printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"pluginId":"demo"}}'
IFS= read -r second
visible=false
if [[ -e "${secret.path}" ]]; then visible=true; fi
printf '{"jsonrpc":"2.0","id":2,"result":{"workspaceVisible":%s,"inheritedSecret":"%s"}}\\n' "\$visible" "\${DEVEX_PLUGIN_SECRET-}"
''');
      final chmod = await Process.run('chmod', <String>['0755', script.path]);
      expect(chmod.exitCode, 0);
      final manifest = PluginManifest(
        id: 'demo',
        executable: 'plugin.sh',
        coreCompatibility: '^0.1.0',
        protocolVersions: const <int>[1],
        capabilities: <PluginCapability>[
          PluginCapability(name: 'source.inspect', effect: PluginEffect.query),
        ],
      );
      final result = await PluginProcessHost(pluginRoot: temp.path).invoke(
        manifest: manifest,
        capability: 'source.inspect',
        arguments: const <String, Object?>{},
      );
      expect(result.result, <String, Object?>{
        'workspaceVisible': false,
        'inheritedSecret': '',
      });
    },
  );

  test(
    'mutation is denied before execution without preview and explicit grant',
    () async {
      final manifest = PluginManifest(
        id: 'demo',
        executable: 'missing',
        coreCompatibility: '^0.1.0',
        protocolVersions: const <int>[1],
        capabilities: <PluginCapability>[
          PluginCapability(name: 'files.write', effect: PluginEffect.authoring),
        ],
      );
      await expectLater(
        PluginProcessHost(pluginRoot: temp.path).invoke(
          manifest: manifest,
          capability: 'files.write',
          arguments: const <String, Object?>{},
        ),
        throwsA(isA<PluginInvocationException>()),
      );
    },
  );

  test('registry discovers canonical manifests deterministically', () {
    final alpha = Directory(p.join(temp.path, 'alpha'))..createSync();
    final beta = Directory(p.join(temp.path, 'beta'))..createSync();
    PluginManifest manifest(String id) => PluginManifest(
      id: id,
      executable: 'plugin',
      coreCompatibility: '^0.1.0',
      protocolVersions: const <int>[1],
      capabilities: <PluginCapability>[
        PluginCapability(name: 'source.inspect', effect: PluginEffect.query),
      ],
    );
    for (final entry in <(Directory, PluginManifest)>[
      (beta, manifest('beta')),
      (alpha, manifest('alpha')),
    ]) {
      File(p.join(entry.$1.path, 'plugin.json')).writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(entry.$2.toJson())}\n',
      );
    }
    final discovered = const LocalPluginRegistry().discover(temp.path);
    expect(discovered.map((item) => item.manifest.id), <String>[
      'alpha',
      'beta',
    ]);
    expect(discovered.map((item) => item.manifestDigest).toSet(), hasLength(2));
  });
}
