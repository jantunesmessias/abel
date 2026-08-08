import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repository = SourceRepository(
    id: 'repo',
    kind: SourceRepositoryKind.filesystem,
    root: '.',
  );
  final snapshot = SourceSnapshot(
    repository: repository,
    revision: 'filesystem:sample',
    completeness: SnapshotCompleteness.complete,
    files: <SourceFileEntry>[
      SourceFileEntry(
        path: 'lib/main.dart',
        digest: Digest.bytes(utf8.encode('void main() {}')),
        size: utf8.encode('void main() {}').length,
      ),
    ],
  );

  test('source documents are strict, canonical, and schema conformant', () {
    final changeSet = ChangeSet(
      repositoryId: 'repo',
      baseSnapshotDigest: snapshot.digest,
      currentSnapshotDigest: snapshot.digest,
      complete: true,
      changes: const <SourceChange>[],
    );
    final plan = ImpactPlan(
      changeSetDigest: changeSet.digest,
      currentSnapshotDigest: snapshot.digest,
      complete: true,
      impacted: const <ImpactItem>[],
      reusableSubjects: const <String>['scenario-a'],
    );
    final content = 'void main() {}';
    final context = ContextBundle(
      snapshotDigest: snapshot.digest,
      files: <ContextFile>[
        ContextFile(
          path: 'lib/main.dart',
          digest: Digest.bytes(utf8.encode(content)),
          content: content,
        ),
      ],
      redactions: const <String>[],
    );
    final createdAt = DateTime.utc(2026, 8, 9, 12);
    final task = AgentTask(
      id: 'task-1',
      principalId: 'agent-reviewer',
      contextBundleDigest: context.digest,
      baseSnapshotDigest: snapshot.digest,
      objective: 'Inspect the bounded context and propose a source change.',
      allowedEffects: const <AgentTaskEffect>{
        AgentTaskEffect.inspect,
        AgentTaskEffect.propose,
      },
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(hours: 1)),
    );
    final proposal = AgentProposal(
      id: 'proposal-1',
      taskId: task.id,
      taskDigest: task.digest,
      baseSnapshotDigest: snapshot.digest,
      changeSetDigest: changeSet.digest,
      summary: 'Update the source through the explicit apply workflow.',
      createdAt: createdAt.add(const Duration(minutes: 1)),
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(_root(), 'schemas/v1/source-automation.schema.json'),
            ).readAsStringSync(),
          )
          as Object,
    );
    for (final document in <Map<String, Object?>>[
      snapshot.toJson(),
      changeSet.toJson(),
      plan.toJson(),
      context.toJson(),
      task.toJson(),
      proposal.toJson(),
    ]) {
      expect(validator.validate(document).isValid, isTrue, reason: '$document');
    }
    expect(SourceSnapshot.fromJson(snapshot.toJson()).digest, snapshot.digest);
    expect(AgentTask.fromJson(task.toJson()).digest, task.digest);
    expect(AgentProposal.fromJson(proposal.toJson()).digest, proposal.digest);
    expect(proposal.requiresExplicitApply, isTrue);
    final tampered = snapshot.toJson()..['revision'] = 'tampered';
    expect(() => SourceSnapshot.fromJson(tampered), throwsFormatException);
    expect(
      () => ContextFile(
        path: 'lib/main.dart',
        digest: Digest.bytes(const <int>[1]),
        content: content,
      ),
      throwsArgumentError,
    );
  });

  test('agent contracts cannot grant apply or outlive their bounded task', () {
    final createdAt = DateTime.utc(2026, 8, 9, 12);
    expect(
      () => AgentTask(
        id: 'task-1',
        principalId: 'agent-reviewer',
        contextBundleDigest: Digest.semantic(<String, Object?>{'context': 1}),
        baseSnapshotDigest: snapshot.digest,
        objective: 'Inspect only.',
        allowedEffects: const <AgentTaskEffect>{AgentTaskEffect.inspect},
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(hours: 25)),
      ),
      throwsArgumentError,
    );

    final task = AgentTask(
      id: 'task-1',
      principalId: 'agent-reviewer',
      contextBundleDigest: Digest.semantic(<String, Object?>{'context': 1}),
      baseSnapshotDigest: snapshot.digest,
      objective: 'Propose a bounded change.',
      allowedEffects: const <AgentTaskEffect>{AgentTaskEffect.propose},
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(hours: 1)),
    );
    final proposal = AgentProposal(
      id: 'proposal-1',
      taskId: task.id,
      taskDigest: task.digest,
      baseSnapshotDigest: snapshot.digest,
      changeSetDigest: Digest.semantic(<String, Object?>{'changes': 1}),
      summary: 'Preview only.',
      createdAt: createdAt,
    );
    final escalated = proposal.toJson()..['requiresExplicitApply'] = false;
    expect(() => AgentProposal.fromJson(escalated), throwsFormatException);
  });

  test(
    'bundle manifest, seal, and plugin manifest conform to public schemas',
    () {
      final entry = DevExBundleEntry(
        path: 'release.json',
        digest: Digest.bytes(utf8.encode('{}')),
        size: 2,
        mediaType: 'application/json',
      );
      final manifest = DevExBundleManifest(
        releaseDigest: Digest.semantic(<String, Object?>{'release': 1}),
        releaseBundleDigest: Digest.semantic(<String, Object?>{'bundle': 1}),
        entries: <DevExBundleEntry>[entry],
      );
      final seal = ReleaseSeal(
        releaseDigest: manifest.releaseDigest,
        bundleArchiveDigest: Digest.semantic(<String, Object?>{'archive': 1}),
        impactPlanDigest: Digest.semantic(<String, Object?>{'impact': 1}),
        sourceSnapshotDigests: <Digest>[snapshot.digest],
        policyId: 'source-impact-v1',
      );
      final plugin = PluginManifest(
        id: 'sample-plugin',
        executable: 'bin/plugin',
        coreCompatibility: '^0.1.0',
        protocolVersions: const <int>[1],
        capabilities: <PluginCapability>[
          PluginCapability(name: 'source.inspect', effect: PluginEffect.query),
        ],
      );
      final bundleValidator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(_root(), 'schemas/v1/devex-bundle.schema.json'),
              ).readAsStringSync(),
            )
            as Object,
      );
      final pluginValidator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(_root(), 'schemas/v1/plugin-manifest.schema.json'),
              ).readAsStringSync(),
            )
            as Object,
      );
      expect(bundleValidator.validate(manifest.toJson()).isValid, isTrue);
      expect(bundleValidator.validate(seal.toJson()).isValid, isTrue);
      expect(pluginValidator.validate(plugin.toJson()).isValid, isTrue);
      expect(
        DevExBundleManifest.fromJson(manifest.toJson()).digest,
        manifest.digest,
      );
      expect(ReleaseSeal.fromJson(seal.toJson()).digest, seal.digest);
      expect(PluginManifest.fromJson(plugin.toJson()).id, plugin.id);
    },
  );
}

String _root() {
  var directory = Directory.current.absolute;
  while (!File(
    p.join(directory.path, 'pubspec.yaml'),
  ).readAsStringSync().contains('name: devex_workspace')) {
    directory = directory.parent;
  }
  return directory.path;
}
