import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory temp;
  late LocalExperienceMcpBackend backend;
  var backendInitialized = false;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('workspace-experience-mcp.');
    _copyFixture(temp);
    backend = _createBackend(temp);
    backendInitialized = true;
  });

  tearDown(() async {
    if (backendInitialized) {
      await backend.close(connectionEpoch: 'test-epoch');
      backendInitialized = false;
    }
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('publishes typed resources and deterministic bounded queries', () async {
    expect(
      backend.tools.map((tool) => tool['name']),
      containsAll(<String>[
        'catalog.list',
        'catalog.search',
        'catalog.graph',
        'context.export',
        'quality.tests.run',
        'authoring.layout.promote',
      ]),
    );
    final contextTool = backend.tools.singleWhere(
      (tool) => tool['name'] == 'context.export',
    );
    final contextSchema = contextTool['inputSchema']! as Map<String, Object?>;
    expect(contextSchema['required'], <String>[
      'expectedContentSetDigest',
      'selection',
      'inclusion',
      'budgets',
    ]);
    expect(
      backend.resources.map((resource) => resource['uri']),
      containsAll(<String>[
        'experience://content-set',
        'experience://catalog',
        'experience://topology',
        'experience://scenario-lab',
        'experience://motion',
      ]),
    );

    final first = await backend.call(
      name: 'catalog.list',
      arguments: <String, Object?>{'kind': 'scenario', 'offset': 0, 'limit': 2},
      principalId: 'principal-a',
      connectionEpoch: 'test-epoch',
    );
    final second = await backend.call(
      name: 'catalog.list',
      arguments: <String, Object?>{'kind': 'scenario', 'offset': 0, 'limit': 2},
      principalId: 'principal-a',
      connectionEpoch: 'test-epoch',
    );
    expect(first, second);
    expect((first! as Map<String, Object?>)['items'], hasLength(2));

    final description = backend.contextBuilder!.describe();
    final contextRequest = ContextBuildRequest(
      expectedContentSetDigest: description.contentSetDigest,
      selection: ContextSelection(
        boardId: BoardId('delivery-lab-board'),
        projectionId: ExperienceProjectionId('delivery-journey'),
        journeyId: JourneyId('operate-delivery-workspace'),
        scenarioId: ScenarioId('dashboard-ready'),
      ),
      inclusion: const ContextInclusion(
        sources: true,
        images: true,
        evidence: false,
        history: true,
        changes: true,
      ),
      budgets: description.maximumBudgets,
    );
    final contextFirst = await backend.call(
      name: 'context.export',
      arguments: contextRequest.toJson(),
      principalId: 'principal-a',
      connectionEpoch: 'test-epoch',
    );
    final contextSecond = await backend.call(
      name: 'context.export',
      arguments: contextRequest.toJson(),
      principalId: 'principal-a',
      connectionEpoch: 'test-epoch',
    );
    expect(contextFirst, contextSecond);
    expect(jsonEncode(contextFirst), isNot(contains(temp.path)));
  });

  test(
    'resolved plan removes disabled tools from discovery and dispatch',
    () async {
      await backend.close(connectionEpoch: 'test-epoch');
      backendInitialized = false;
      final configuration = const WorkspaceConfigurationLoader().load(
        startPath: temp.path,
      );
      final full = _resolvePlan(configuration);
      const disabled = <String>{
        'authoring.local',
        'context.builder.local',
        'evidence.tests',
        'artifact-store.local',
      };
      final enabledModules = full.enabledModules
          .where((module) => !disabled.contains(module.moduleId.value))
          .toList();
      final enabledIds = enabledModules
          .map((module) => module.moduleId)
          .toSet();
      final reduced = ResolvedKitPlan(
        distributionDigest: full.distributionDigest,
        profileId: full.profileId,
        enabledModules: enabledModules,
        providerBindings: full.providerBindings
            .where(
              (binding) => enabledIds.containsAll(binding.providerModuleIds),
            )
            .toList(),
        dependencyOrder: full.dependencyOrder
            .where(enabledIds.contains)
            .toList(),
        startupPolicy: full.startupPolicy,
        diagnostics: full.diagnostics,
      );
      backend = LocalExperienceMcpBackend.create(
        configuration: configuration,
        plan: reduced,
      );
      backendInitialized = true;

      final names = backend.tools.map((tool) => tool['name']).toSet();
      expect(names, isNot(contains('context.export')));
      expect(names, isNot(contains('quality.tests.run')));
      expect(names, isNot(contains('quality.capture')));
      expect(names, isNot(contains('capability.issue')));
      expect(names.any((name) => '$name'.startsWith('authoring.')), isFalse);
      await expectLater(
        backend.call(
          name: 'quality.tests.run',
          arguments: const <String, Object?>{},
          principalId: 'principal-a',
          connectionEpoch: 'test-epoch',
        ),
        throwsA(
          isA<ExperienceMcpToolException>().having(
            (error) => error.code,
            'code',
            'unknownTool',
          ),
        ),
      );
    },
  );

  test(
    'source excerpts are sanitized and paths never come from the caller',
    () async {
      final source = File(p.join(temp.path, 'lib', 'app_factory.dart'));
      source.writeAsStringSync(
        '${source.readAsStringSync()}\nconst token = "Bearer MCP_REDACTION_SECRET";\n',
      );

      final result = await backend.call(
        name: 'source.excerpt',
        arguments: <String, Object?>{
          'scenarioId': 'dashboard-unavailable',
          'maxBytes': 65536,
        },
        principalId: 'principal-a',
        connectionEpoch: 'test-epoch',
      );
      final encoded = jsonEncode(result);
      expect(encoded, contains('[REDACTED]'));
      expect(encoded, isNot(contains('MCP_REDACTION_SECRET')));
      expect(encoded, isNot(contains(temp.path)));
      expect(
        () => backend.call(
          name: 'source.excerpt',
          arguments: <String, Object?>{
            'scenarioId': 'dashboard-unavailable',
            'path': '../../etc/passwd',
          },
          principalId: 'principal-a',
          connectionEpoch: 'test-epoch',
        ),
        throwsA(isA<FormatException>()),
      );

      if (!Platform.isWindows) {
        final outside = Directory.systemTemp.createTempSync(
          'workspace-mcp-outside.',
        );
        addTearDown(() {
          if (outside.existsSync()) outside.deleteSync(recursive: true);
        });
        File(
          p.join(outside.path, 'outside.evidence.zip'),
        ).writeAsStringSync('outside');
        Link(p.join(temp.path, 'linked')).createSync(outside.path);
        await expectLater(
          backend.call(
            name: 'quality.bundle.verify',
            arguments: <String, Object?>{'path': 'linked/outside.evidence.zip'},
            principalId: 'principal-a',
            connectionEpoch: 'test-epoch',
          ),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'generic effects consume scoped capability on the first attempt',
    () async {
      final capture = File(p.join(temp.path, 'capture.png'))
        ..writeAsBytesSync(
          rgbaPng(width: 1, height: 1, pixels: const <int>[20, 40, 60, 255]),
        );
      final contentDigest =
          backend.workspace.contentSetIdentity.contentSetDigest;
      final intendedInput = <String, Object?>{
        'path': p.relative(capture.path, from: temp.path),
        'classification': 'internal',
      };
      final issued =
          await backend.call(
                name: 'capability.issue',
                arguments: <String, Object?>{
                  'requestId': 'issue-1',
                  'tool': 'quality.capture',
                  'expectedDigest': contentDigest.value,
                  'input': intendedInput,
                },
                principalId: 'principal-a',
                connectionEpoch: 'test-epoch',
              )
              as Map<String, Object?>;

      Map<String, Object?> effectArguments(Map<String, Object?> input) =>
          <String, Object?>{
            'requestId': 'capture-1',
            'capabilityId': issued['id'],
            'capabilityDigest': issued['digest'],
            'expectedDigest': contentDigest.value,
            'input': input,
          };

      await expectLater(
        backend.call(
          name: 'quality.capture',
          arguments: effectArguments(<String, Object?>{
            ...intendedInput,
            'classification': 'public',
          }),
          principalId: 'principal-a',
          connectionEpoch: 'test-epoch',
        ),
        throwsA(
          isA<ExperienceMcpToolException>().having(
            (error) => error.code,
            'code',
            'capabilityMismatch',
          ),
        ),
      );
      await expectLater(
        backend.call(
          name: 'quality.capture',
          arguments: effectArguments(intendedInput),
          principalId: 'principal-a',
          connectionEpoch: 'test-epoch',
        ),
        throwsA(isA<ExperienceMcpToolException>()),
      );

      final live =
          await backend.call(
                name: 'capability.issue',
                arguments: <String, Object?>{
                  'requestId': 'issue-2',
                  'tool': 'quality.capture',
                  'expectedDigest': contentDigest.value,
                  'input': intendedInput,
                },
                principalId: 'principal-a',
                connectionEpoch: 'test-epoch',
              )
              as Map<String, Object?>;
      final captured =
          await backend.call(
                name: 'quality.capture',
                arguments: <String, Object?>{
                  'requestId': 'capture-2',
                  'capabilityId': live['id'],
                  'capabilityDigest': live['digest'],
                  'expectedDigest': contentDigest.value,
                  'input': intendedInput,
                },
                principalId: 'principal-a',
                connectionEpoch: 'test-epoch',
              )
              as Map<String, Object?>;
      expect(captured['width'], 1);
      expect(captured['height'], 1);
      final comparison =
          await backend.call(
                name: 'quality.capture.diff',
                arguments: <String, Object?>{
                  'expectedDigest': captured['artifactDigest'],
                  'actualDigest': captured['artifactDigest'],
                  'policy': VisualComparisonPolicy(
                    id: 'mcp-visual-v1',
                    maxChannelDelta: 0,
                    maxChangedPixelRatio: 0,
                  ).toJson(),
                },
                principalId: 'principal-a',
                connectionEpoch: 'test-epoch',
              )
              as Map<String, Object?>;
      expect(comparison['passed'], isTrue);

      final audit = File(
        p.join(
          backend.workspaceStore.stateRoot,
          'mcp',
          'automation-audit.json',
        ),
      );
      expect(audit.existsSync(), isTrue);
      final auditText = audit.readAsStringSync();
      expect(auditText, contains('"outcome":"rejected"'));
      expect(auditText, contains('"outcome":"started"'));
      expect(auditText, contains('"outcome":"succeeded"'));
      expect(auditText, contains('"requestDigest":"sha256:'));
      expect(auditText, isNot(contains('issue-1')));
      expect(auditText, isNot(contains('capture-2')));
    },
  );

  test('authoring tools use the durable grant and replay boundary', () async {
    const connection = 'authoring-epoch';
    final subject = AuthoringSubjectRef(
      workspaceId: WorkspaceId('workspace-showcase'),
      applicationId: ApplicationId('sample'),
      projectionId: ExperienceProjectionId('delivery-journey'),
    );
    final describeRequest = ExperienceAuthoringDescribeRequest(
      requestId: AuthoringRequestId('mcp-describe'),
      subject: subject,
    );
    final description = ExperienceAuthoringDescription.fromJson(
      await backend.call(
        name: 'authoring.describe',
        arguments: <String, Object?>{'request': describeRequest.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
    );
    description.validateAgainst(describeRequest);
    expect(description.availability, ExperienceAuthoringAvailability.available);

    final openTemplate = LayoutDraftOpenRequest(
      requestId: AuthoringRequestId('mcp-open-effect'),
      subject: subject,
      expectedContentSetDigest: description.currentContentSetDigest,
      expectedSourceDigest: description.currentSourceDigest!,
      grantId: AuthoringActionGrantId('mcp-open-template'),
      grantDigest: Digest.semantic('mcp-open-template'),
    );
    final openIntent = AuthoringGrantRequest(
      requestId: AuthoringRequestId('mcp-open-grant'),
      capabilityDigest: description.capability!.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.openDraft,
      expectedDigest: description.currentContentSetDigest,
      expectedSourceDigest: description.currentSourceDigest!,
      payloadDigest: openTemplate.payloadDigest,
    );
    final openGrant = AuthoringGrantResult.fromJson(
      await backend.call(
        name: 'authoring.grant',
        arguments: <String, Object?>{'request': openIntent.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
    );
    openGrant.validateAgainst(openIntent);
    final openRequest = LayoutDraftOpenRequest(
      requestId: openTemplate.requestId,
      subject: subject,
      expectedContentSetDigest: openTemplate.expectedContentSetDigest,
      expectedSourceDigest: openTemplate.expectedSourceDigest,
      grantId: openGrant.grant.id,
      grantDigest: openGrant.grant.digest,
    );
    final opened = LayoutDraftOpenResult.fromJson(
      await backend.call(
        name: 'authoring.openDraft',
        arguments: <String, Object?>{'request': openRequest.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
    );
    opened.validateAgainst(openRequest);
    final replay = LayoutDraftOpenResult.fromJson(
      await backend.call(
        name: 'authoring.openDraft',
        arguments: <String, Object?>{'request': openRequest.toJson()},
        principalId: 'principal-a',
        connectionEpoch: 'authoring-replay-epoch',
      ),
    );
    expect(replay.toJson(), opened.toJson());

    final moveTemplate = LayoutDraftMutationRequest(
      requestId: AuthoringRequestId('mcp-move-effect'),
      draftId: opened.draft.id,
      expectedDraftDigest: opened.draft.digest,
      expectedDraftRevision: opened.draft.revision,
      grantId: AuthoringActionGrantId('mcp-move-template'),
      grantDigest: Digest.semantic('mcp-move-template'),
      mutation: LayoutDraftMutation.applyMove,
      move: LayoutMoveNodeInput(
        nodeInstanceId: NodeInstanceId('journey-dashboard-ready'),
        toX: 361,
        toY: 221,
      ),
    );
    final moveIntent = AuthoringGrantRequest(
      requestId: AuthoringRequestId('mcp-move-grant'),
      capabilityDigest: description.capability!.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.moveNode,
      expectedDigest: opened.draft.digest,
      expectedSourceDigest: opened.draft.baseSourceDigest,
      payloadDigest: moveTemplate.payloadDigest,
    );
    final moveGrant = AuthoringGrantResult.fromJson(
      await backend.call(
        name: 'authoring.grant',
        arguments: <String, Object?>{'request': moveIntent.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
    );
    final moveRequest = LayoutDraftMutationRequest(
      requestId: moveTemplate.requestId,
      draftId: moveTemplate.draftId,
      expectedDraftDigest: moveTemplate.expectedDraftDigest,
      expectedDraftRevision: moveTemplate.expectedDraftRevision,
      grantId: moveGrant.grant.id,
      grantDigest: moveGrant.grant.digest,
      mutation: moveTemplate.mutation,
      move: moveTemplate.move,
    );
    final moved = LayoutDraftMutationResult.fromJson(
      await backend.call(
        name: 'authoring.layout.edit',
        arguments: <String, Object?>{'request': moveRequest.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
    );
    moved.validateAgainst(moveRequest, previousDraft: opened.draft);
    expect(moved.draft.revision, opened.draft.revision + 1);

    final conflicting = LayoutDraftOpenRequest(
      requestId: AuthoringRequestId('mcp-open-conflict'),
      subject: subject,
      expectedContentSetDigest: openTemplate.expectedContentSetDigest,
      expectedSourceDigest: openTemplate.expectedSourceDigest,
      grantId: openGrant.grant.id,
      grantDigest: openGrant.grant.digest,
    );
    await expectLater(
      backend.call(
        name: 'authoring.openDraft',
        arguments: <String, Object?>{'request': conflicting.toJson()},
        principalId: 'principal-a',
        connectionEpoch: connection,
      ),
      throwsA(
        isA<ExperienceMcpToolException>().having(
          (error) => error.code,
          'code',
          'authoring.grantConsumed',
        ),
      ),
    );
  });

  test('audit chain survives restart and tampering fails closed', () async {
    final digest = backend.workspace.contentSetIdentity.contentSetDigest;
    await backend.call(
      name: 'capability.issue',
      arguments: <String, Object?>{
        'requestId': 'issue-restart',
        'tool': 'quality.tests.run',
        'expectedDigest': digest.value,
        'input': <String, Object?>{
          'runner': 'dart',
          'targets': <String>['tests/smoke_test.dart'],
        },
      },
      principalId: 'principal-a',
      connectionEpoch: 'test-epoch',
    );
    await backend.close(connectionEpoch: 'test-epoch');
    backendInitialized = false;
    backend = _createBackend(temp);
    backendInitialized = true;

    final audit = File(
      p.join(backend.workspaceStore.stateRoot, 'mcp', 'automation-audit.json'),
    );
    final document =
        jsonDecode(audit.readAsStringSync()) as Map<String, Object?>;
    final records = document['records']! as List<Object?>;
    final first = records.first! as Map<String, Object?>;
    first['outcome'] = 'tampered';
    audit.writeAsStringSync(jsonEncode(document));
    await backend.close(connectionEpoch: 'test-epoch');
    backendInitialized = false;

    expect(() => _createBackend(temp), throwsA(isA<FormatException>()));
  });
}

LocalExperienceMcpBackend _createBackend(Directory workspace) {
  final configuration = const WorkspaceConfigurationLoader().load(
    startPath: workspace.path,
  );
  return LocalExperienceMcpBackend.create(
    configuration: configuration,
    plan: _resolvePlan(configuration),
  );
}

ResolvedKitPlan _resolvePlan(LoadedWorkspaceConfiguration configuration) {
  final catalog = const BuiltinModuleCatalog().create(
    platform: switch (Platform.operatingSystem) {
      'linux' => 'linux-x64',
      'macos' => 'macos-arm64',
      'windows' => 'windows-x64',
      final value => '$value-native',
    },
  );
  return configuration.kitPlanRequest.resolve(
    catalog: catalog,
    configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
  );
}

void _copyFixture(Directory destination) {
  final root = _repositoryRoot();
  File(
    p.join(root.path, 'examples', 'sample_flutter', 'workspace.yaml'),
  ).copySync(p.join(destination.path, 'workspace.yaml'));
  _copyDirectory(
    Directory(p.join(root.path, 'examples', 'sample_flutter', '.experience')),
    Directory(p.join(destination.path, '.experience')),
  );
  Directory(p.join(destination.path, 'lib')).createSync(recursive: true);
  File(
    p.join(root.path, 'examples', 'sample_flutter', 'lib', 'app_factory.dart'),
  ).copySync(p.join(destination.path, 'lib', 'app_factory.dart'));
}

Directory _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        File(
          p.join(current.path, 'examples', 'sample_flutter', 'workspace.yaml'),
        ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Repository root was not found');
    }
    current = parent;
  }
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(recursive: false, followLinks: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    } else {
      throw StateError('Fixture contains an unsupported filesystem entry');
    }
  }
}
