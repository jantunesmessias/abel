import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  var stage = 'arguments';
  try {
    final options = _options(arguments);
    final configuration = options['config'];
    final workspace = options['workspace'];
    if (configuration == null || workspace == null) {
      throw const FormatException('missing-options');
    }
    stage = 'fixture';
    _writeEffectFixtures(workspace);
    stage = 'server';
    final client = await _McpClient.start(configuration: configuration);
    try {
      stage = 'discovery';
      final discovery = await client.request('server/discover');
      final discoveryResult = _result(discovery);
      final capabilities = _map(
        discoveryResult['capabilities'],
        'capabilities',
      );
      _require(capabilities.containsKey('tools'), 'tools-capability');
      _require(capabilities.containsKey('resources'), 'resources-capability');

      stage = 'tools';
      final toolsResult = _result(await client.request('tools/list'));
      final tools = _maps(toolsResult['tools'], 'tools');
      final toolNames = tools
          .map((tool) => tool['name'])
          .whereType<String>()
          .toSet();
      _require(toolNames.containsAll(_requiredTools), 'tool-set');
      _require(toolNames.length == tools.length, 'tool-duplicates');
      for (final tool in tools) {
        final name = tool['name']! as String;
        final annotations = _map(tool['annotations'], '$name.annotations');
        final shouldBeReadOnly = !_effectTools.contains(name);
        _require(
          annotations['readOnlyHint'] == shouldBeReadOnly,
          '$name-read-only',
        );
      }

      stage = 'resources';
      final resourcesResult = _result(await client.request('resources/list'));
      final resources = _maps(resourcesResult['resources'], 'resources');
      final resourceUris = resources
          .map((resource) => resource['uri'])
          .whereType<String>()
          .toSet();
      _require(resourceUris.containsAll(_requiredResources), 'resource-set');
      final contentSet = await client.readResource('experience://content-set');
      final contentSetDigest = Digest(_string(contentSet, 'contentSetDigest'));
      final catalog = await client.readResource('experience://catalog');
      final catalogDigest = Digest(_string(catalog, 'digest'));

      stage = 'queries';
      var queryCount = 0;
      final listed = await client.call('catalog.list', <String, Object?>{
        'kind': 'scenario',
        'offset': 0,
        'limit': 3,
      });
      queryCount += 1;
      _require(_list(listed['items'], 'list.items').length == 3, 'list-page');
      final searched = await client.call('catalog.search', <String, Object?>{
        'query': 'dashboard',
        'limit': 5,
      });
      queryCount += 1;
      _require(_list(searched['items'], 'search.items').isNotEmpty, 'search');
      final fetched = await client.call('catalog.get', <String, Object?>{
        'kind': 'scenario',
        'id': 'dashboard-ready',
      });
      queryCount += 1;
      _require(
        _map(fetched['entity'], 'get.entity')['id'] == 'dashboard-ready',
        'get',
      );
      final graph = await client.call('catalog.graph', <String, Object?>{
        'projectionId': 'delivery-journey',
      });
      queryCount += 1;
      _require(_list(graph['nodes'], 'graph.nodes').length >= 5, 'graph');
      final neighborhood = await client
          .call('catalog.neighborhood', <String, Object?>{
            'projectionId': 'delivery-journey',
            'nodeId': 'journey-dashboard-ready',
            'depth': 1,
          });
      queryCount += 1;
      _require(
        _list(neighborhood['nodes'], 'neighborhood.nodes').length >= 2,
        'neighborhood',
      );

      stage = 'context';
      final budgets = ContextBudgets(
        categories: <ContextCategory, ContextCategoryBudget>{
          for (final category in ContextCategory.values)
            category: ContextCategoryBudget(maxItems: 12, maxBytes: 65536),
        },
      );
      final contextRequest = ContextBuildRequest(
        expectedContentSetDigest: contentSetDigest,
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
        budgets: budgets,
      );
      final contextFirst = ContextBuildResult.fromJson(
        await client.call('context.export', contextRequest.toJson()),
      );
      final contextSecond = ContextBuildResult.fromJson(
        await client.call('context.export', contextRequest.toJson()),
      );
      _require(
        contextFirst.bundle.digest == contextSecond.bundle.digest,
        'context-determinism',
      );
      _require(
        !jsonEncode(contextFirst.toJson()).contains(workspace),
        'context-path-leak',
      );
      final source = await client.call('source.excerpt', <String, Object?>{
        'scenarioId': 'dashboard-unavailable',
        'maxBytes': 65536,
      });
      queryCount += 1;
      final sourceText = jsonEncode(source);
      _require(!sourceText.contains(workspace), 'source-path-leak');
      _require(
        !sourceText.contains('MCP_REDACTION_SECRET'),
        'source-secret-leak',
      );
      _require(sourceText.contains('[REDACTED]'), 'source-redaction');

      stage = 'quality-query';
      final validation = await client.call(
        'quality.validate',
        const <String, Object?>{},
      );
      queryCount += 1;
      _require(validation['valid'] == true, 'validation');
      final evidenceIndex = await client.call(
        'evidence.index',
        const <String, Object?>{},
      );
      queryCount += 1;
      final captureIndex = await client.call(
        'capture.index',
        const <String, Object?>{},
      );
      queryCount += 1;
      _require(evidenceIndex['items'] is List<Object?>, 'evidence-index');
      _require(captureIndex['items'] is List<Object?>, 'capture-index');
      final escaped = await client.callError(
        'quality.bundle.verify',
        <String, Object?>{'path': '../outside.evidence.zip'},
      );
      _require(escaped == 'invalidRequest', 'path-confinement');

      stage = 'test-effect';
      final testInput = <String, Object?>{
        'runner': 'dart',
        'targets': <String>['test/mcp_smoke_test.dart'],
      };
      final testCapability = await client.issueCapability(
        requestId: 'mcp-test-capability',
        tool: 'quality.tests.run',
        expectedDigest: contentSetDigest,
        input: testInput,
      );
      final testSummary = await client.call(
        'quality.tests.run',
        _effect(
          requestId: 'mcp-test-effect',
          capability: testCapability,
          expectedDigest: contentSetDigest,
          input: testInput,
        ),
      );
      _require(testSummary['success'] == true, 'test-run');
      _require((testSummary['passed']! as int) >= 1, 'test-pass-count');

      stage = 'capture-effect';
      final captureInput = <String, Object?>{
        'path': 'capture.png',
        'classification': 'internal',
      };
      final revokedCapability = await client.issueCapability(
        requestId: 'mcp-capture-revoke-capability',
        tool: 'quality.capture',
        expectedDigest: contentSetDigest,
        input: captureInput,
      );
      final revoked = await client.call('capability.revoke', <String, Object?>{
        'requestId': 'mcp-capture-revoke',
        'capabilityId': revokedCapability['id'],
        'capabilityDigest': revokedCapability['digest'],
      });
      _require(revoked['revoked'] == true, 'capability-revoke');
      final revokedEffect = await client.callError(
        'quality.capture',
        _effect(
          requestId: 'mcp-capture-revoked-effect',
          capability: revokedCapability,
          expectedDigest: contentSetDigest,
          input: captureInput,
        ),
      );
      _require(revokedEffect == 'capabilityMismatch', 'capability-revoked');
      final rejectedCapability = await client.issueCapability(
        requestId: 'mcp-capture-mismatch-capability',
        tool: 'quality.capture',
        expectedDigest: contentSetDigest,
        input: captureInput,
      );
      final mismatch = await client.callError(
        'quality.capture',
        _effect(
          requestId: 'mcp-capture-mismatch-effect',
          capability: rejectedCapability,
          expectedDigest: contentSetDigest,
          input: <String, Object?>{...captureInput, 'classification': 'public'},
        ),
      );
      _require(mismatch == 'capabilityMismatch', 'capability-mismatch');
      final consumed = await client.callError(
        'quality.capture',
        _effect(
          requestId: 'mcp-capture-consumed-effect',
          capability: rejectedCapability,
          expectedDigest: contentSetDigest,
          input: captureInput,
        ),
      );
      _require(consumed == 'capabilityMismatch', 'capability-consumed');
      final captureCapability = await client.issueCapability(
        requestId: 'mcp-capture-capability',
        tool: 'quality.capture',
        expectedDigest: contentSetDigest,
        input: captureInput,
      );
      final captured = await client.call(
        'quality.capture',
        _effect(
          requestId: 'mcp-capture-effect',
          capability: captureCapability,
          expectedDigest: contentSetDigest,
          input: captureInput,
        ),
      );
      _require(captured['width'] == 1 && captured['height'] == 1, 'capture');
      final artifactDigest = _string(captured, 'artifactDigest');
      final comparison = await client
          .call('quality.capture.diff', <String, Object?>{
            'expectedDigest': artifactDigest,
            'actualDigest': artifactDigest,
            'policy': VisualComparisonPolicy(
              id: 'mcp-visual-v1',
              maxChannelDelta: 0,
              maxChangedPixelRatio: 0,
            ).toJson(),
          });
      _require(comparison['passed'] == true, 'capture-diff');

      stage = 'authoring';
      final authoring = await _proveAuthoring(
        client,
        contentSetDigest: contentSetDigest,
        onStage: (value) => stage = value,
      );

      stage = 'close';
      final processResult = await client.close();
      _require(processResult.exitCode == 0, 'server-exit');
      _require(processResult.stderr.isEmpty, 'server-stderr');

      stdout.writeln(
        const JcsCanonicalizer().canonicalize(<String, Object?>{
          'toolCount': tools.length,
          'resourceCount': resources.length,
          'queryCount': queryCount,
          'contextItemCount': contextFirst.bundle.items.length,
          'contextOmissionCount': contextFirst.bundle.omissions.length,
          'contextDeterministic': true,
          'testPassedCount': testSummary['passed'],
          'captureWidth': captured['width'],
          'captureHeight': captured['height'],
          'captureDiffPassed': true,
          'capabilityRevoked': true,
          'capabilityMismatchConsumed': true,
          'authoringOpened': authoring.opened,
          'authoringReplayExact': authoring.replayExact,
          'authoringMoved': authoring.moved,
          'authoringGrantConsumed': authoring.grantConsumed,
          'authoringReviewPrepared': authoring.reviewPrepared,
          'authoringFindingRecorded': authoring.findingRecorded,
          'authoringConceptProposed': authoring.conceptProposed,
          'automatedAcceptancePassed': authoring.acceptancePassed,
          'acceptanceSeparateFromHumanApproval':
              authoring.acceptanceSeparateFromHumanApproval,
          'pathConfinementProved': true,
          'sourceRedactionProved': true,
          'catalogBound': catalogDigest == Digest(_string(catalog, 'digest')),
        }),
      );
    } finally {
      await client.closeIfNeeded();
    }
  } on _ToolCallFailure catch (error) {
    stderr.writeln('McpExperienceProbeFailure[$stage:${error.code}]');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('McpExperienceProbeFailure[$stage:${error.message}]');
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('McpExperienceProbeFailure[$stage:${error.runtimeType}]');
    exitCode = 1;
  }
}

Future<_AuthoringProof> _proveAuthoring(
  _McpClient client, {
  required Digest contentSetDigest,
  required void Function(String value) onStage,
}) async {
  onStage('authoring-describe');
  const connectionPrincipal = 'mcp-client';
  final subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace-showcase'),
    applicationId: ApplicationId('sample'),
    projectionId: ExperienceProjectionId('delivery-journey'),
  );
  final describeRequest = ExperienceAuthoringDescribeRequest(
    requestId: AuthoringRequestId('mcp-vertical-describe'),
    subject: subject,
  );
  final description = ExperienceAuthoringDescription.fromJson(
    await client.call('authoring.describe', <String, Object?>{
      'request': describeRequest.toJson(),
    }),
  );
  description.validateAgainst(describeRequest);
  _require(
    description.availability == ExperienceAuthoringAvailability.available &&
        description.currentContentSetDigest == contentSetDigest,
    '$connectionPrincipal-authoring-description',
  );

  final openTemplate = LayoutDraftOpenRequest(
    requestId: AuthoringRequestId('mcp-vertical-open-effect'),
    subject: subject,
    expectedContentSetDigest: description.currentContentSetDigest,
    expectedSourceDigest: description.currentSourceDigest!,
    grantId: AuthoringActionGrantId('mcp-vertical-open-template'),
    grantDigest: Digest.semantic('mcp-vertical-open-template'),
  );
  onStage('authoring-open');
  final openIntent = AuthoringGrantRequest(
    requestId: AuthoringRequestId('mcp-vertical-open-grant'),
    capabilityDigest: description.capability!.digest,
    subject: subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.openDraft,
    expectedDigest: description.currentContentSetDigest,
    expectedSourceDigest: description.currentSourceDigest!,
    payloadDigest: openTemplate.payloadDigest,
  );
  final openGrant = AuthoringGrantResult.fromJson(
    await client.call('authoring.grant', <String, Object?>{
      'request': openIntent.toJson(),
    }),
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
    await client.call('authoring.openDraft', <String, Object?>{
      'request': openRequest.toJson(),
    }),
  );
  opened.validateAgainst(openRequest);
  final replay = LayoutDraftOpenResult.fromJson(
    await client.call('authoring.openDraft', <String, Object?>{
      'request': openRequest.toJson(),
    }),
  );

  final moveTemplate = LayoutDraftMutationRequest(
    requestId: AuthoringRequestId('mcp-vertical-move-effect'),
    draftId: opened.draft.id,
    expectedDraftDigest: opened.draft.digest,
    expectedDraftRevision: opened.draft.revision,
    grantId: AuthoringActionGrantId('mcp-vertical-move-template'),
    grantDigest: Digest.semantic('mcp-vertical-move-template'),
    mutation: LayoutDraftMutation.applyMove,
    move: LayoutMoveNodeInput(
      nodeInstanceId: NodeInstanceId('journey-dashboard-ready'),
      toX: 361,
      toY: 221,
    ),
  );
  onStage('authoring-move');
  final moveIntent = AuthoringGrantRequest(
    requestId: AuthoringRequestId('mcp-vertical-move-grant'),
    capabilityDigest: description.capability!.digest,
    subject: subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.moveNode,
    expectedDigest: opened.draft.digest,
    expectedSourceDigest: opened.draft.baseSourceDigest,
    payloadDigest: moveTemplate.payloadDigest,
  );
  final moveGrant = AuthoringGrantResult.fromJson(
    await client.call('authoring.grant', <String, Object?>{
      'request': moveIntent.toJson(),
    }),
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
    await client.call('authoring.layout.edit', <String, Object?>{
      'request': moveRequest.toJson(),
    }),
  );
  moved.validateAgainst(moveRequest, previousDraft: opened.draft);

  final prepareTemplate = ExperienceReviewPrepareRequest(
    requestId: AuthoringRequestId('mcp-vertical-prepare-effect'),
    subject: subject,
    draftId: moved.draft.id,
    expectedDraftDigest: moved.draft.digest,
    expectedDraftRevision: moved.draft.revision,
    expectedContentSetDigest: moved.draft.contentSetDigest,
    expectedSourceDigest: moved.draft.baseSourceDigest,
    reviewGuideId: ReviewGuideId('delivery-workspace-review'),
    reviewGuideStepId: 'review-ready-lab',
    grantId: AuthoringActionGrantId('mcp-vertical-prepare-template'),
    grantDigest: Digest.semantic('mcp-vertical-prepare-template'),
  );
  onStage('authoring-prepare-grant');
  final prepareGrant = await _authoringGrant(
    client,
    capabilityDigest: description.capability!.digest,
    subject: subject,
    requestId: 'mcp-vertical-prepare-grant',
    operation: AuthoringOperation.prepareReview,
    expectedDigest: moved.draft.digest,
    expectedSourceDigest: moved.draft.baseSourceDigest,
    payloadDigest: prepareTemplate.payloadDigest,
  );
  final prepareRequest = ExperienceReviewPrepareRequest(
    requestId: prepareTemplate.requestId,
    subject: prepareTemplate.subject,
    draftId: prepareTemplate.draftId,
    expectedDraftDigest: prepareTemplate.expectedDraftDigest,
    expectedDraftRevision: prepareTemplate.expectedDraftRevision,
    expectedContentSetDigest: prepareTemplate.expectedContentSetDigest,
    expectedSourceDigest: prepareTemplate.expectedSourceDigest,
    reviewGuideId: prepareTemplate.reviewGuideId,
    reviewGuideStepId: prepareTemplate.reviewGuideStepId,
    grantId: prepareGrant.grant.id,
    grantDigest: prepareGrant.grant.digest,
  );
  onStage('authoring-prepare-effect');
  final preparedJson = await client.call(
    'authoring.review.prepare',
    <String, Object?>{'request': prepareRequest.toJson()},
  );
  onStage('authoring-prepare-result');
  final prepared = ExperienceReviewPrepareResult.fromJson(preparedJson);
  onStage('authoring-prepare-validated');

  ExperienceReviewMutationFence fence(ExperienceReviewPacket packet) =>
      ExperienceReviewMutationFence(
        subject: subject,
        changeSetId: prepared.changeSet.id,
        changeSetDigest: prepared.changeSet.digest,
        reviewPacketId: packet.id,
        reviewPacketDigest: packet.digest,
        reviewPacketRevision: packet.revision,
        expectedSourceDigest: prepared.changeSet.baseSourceDigest,
        expectedContentSetDigest: prepared.changeSet.expectedContentSetDigest,
      );

  Future<ExperienceReviewActionResult> reviewAction({
    required String requestStem,
    required String tool,
    required AuthoringOperation operation,
    required ExperienceReviewPacket packet,
    AppendExperienceFindingInput? finding,
    ProposeExperienceConceptInput? concept,
  }) async {
    final template = ExperienceReviewActionRequest(
      requestId: AuthoringRequestId('$requestStem-effect'),
      fence: fence(packet),
      operation: operation,
      finding: finding,
      concept: concept,
      grantId: AuthoringActionGrantId('$requestStem-template'),
      grantDigest: Digest.semantic('$requestStem-template'),
    );
    final grant = await _authoringGrant(
      client,
      capabilityDigest: description.capability!.digest,
      subject: subject,
      requestId: '$requestStem-grant',
      operation: operation,
      expectedDigest: packet.digest,
      expectedSourceDigest: prepared.changeSet.baseSourceDigest,
      payloadDigest: template.payloadDigest,
    );
    final request = ExperienceReviewActionRequest(
      requestId: template.requestId,
      fence: template.fence,
      operation: operation,
      finding: finding,
      concept: concept,
      grantId: grant.grant.id,
      grantDigest: grant.grant.digest,
    );
    return ExperienceReviewActionResult.fromJson(
      await client.call(tool, <String, Object?>{'request': request.toJson()}),
    );
  }

  onStage('authoring-finding');
  final finding = await reviewAction(
    requestStem: 'mcp-vertical-finding',
    tool: 'authoring.finding.record',
    operation: AuthoringOperation.appendFinding,
    packet: prepared.reviewPacket,
    finding: AppendExperienceFindingInput(
      subject: ExperienceReviewSubject.scenario(ScenarioId('dashboard-ready')),
      severity: ExperienceFindingSeverity.info,
      summary: 'MCP review records a scenario-bound observation.',
      detail: 'The observation remains separate from automated acceptance.',
    ),
  );
  onStage('authoring-concept');
  final concept = await reviewAction(
    requestStem: 'mcp-vertical-concept',
    tool: 'authoring.concept.propose',
    operation: AuthoringOperation.proposeConcept,
    packet: finding.reviewPacket,
    concept: ProposeExperienceConceptInput(
      scenarioId: ScenarioId('dashboard-ready-mcp-concept'),
      title: 'Dashboard readiness concept',
      rationale: 'Keep a proposed scenario explicitly non-current.',
    ),
  );
  onStage('authoring-acceptance');
  final acceptance = await reviewAction(
    requestStem: 'mcp-vertical-acceptance',
    tool: 'quality.acceptance.record',
    operation: AuthoringOperation.evaluateAutomatedAcceptance,
    packet: concept.reviewPacket,
  );
  onStage('authoring-grant-consumption');

  final conflict = LayoutDraftOpenRequest(
    requestId: AuthoringRequestId('mcp-vertical-open-conflict'),
    subject: subject,
    expectedContentSetDigest: openTemplate.expectedContentSetDigest,
    expectedSourceDigest: openTemplate.expectedSourceDigest,
    grantId: openGrant.grant.id,
    grantDigest: openGrant.grant.digest,
  );
  final conflictCode = await client.callError(
    'authoring.openDraft',
    <String, Object?>{'request': conflict.toJson()},
  );
  return _AuthoringProof(
    opened: true,
    replayExact: replay.toJson().toString() == opened.toJson().toString(),
    moved: moved.draft.revision == opened.draft.revision + 1,
    grantConsumed: conflictCode == 'authoring.grantConsumed',
    reviewPrepared:
        prepared.changeSet.draftDigest == moved.draft.digest &&
        prepared.reviewPacket.revision == 0,
    findingRecorded: finding.reviewPacket.findings.length == 1,
    conceptProposed:
        concept.reviewPacket.concepts.length == 1 &&
        concept.reviewPacket.concepts.single.lifecycle ==
            ScenarioLifecycle.concept,
    acceptancePassed:
        acceptance.reviewPacket.automatedAcceptance?.outcome ==
        AutomatedAcceptanceOutcome.passed,
    acceptanceSeparateFromHumanApproval:
        acceptance.reviewPacket.humanDecisions.isEmpty &&
        !acceptance.reviewPacket.isPromotable,
  );
}

Future<AuthoringGrantResult> _authoringGrant(
  _McpClient client, {
  required Digest capabilityDigest,
  required AuthoringSubjectRef subject,
  required String requestId,
  required AuthoringOperation operation,
  required Digest expectedDigest,
  required Digest expectedSourceDigest,
  required Digest payloadDigest,
}) async {
  final intent = AuthoringGrantRequest(
    requestId: AuthoringRequestId(requestId),
    capabilityDigest: capabilityDigest,
    subject: subject,
    effect: authoringEffectFor(operation),
    operation: operation,
    expectedDigest: expectedDigest,
    expectedSourceDigest: expectedSourceDigest,
    payloadDigest: payloadDigest,
  );
  final result = AuthoringGrantResult.fromJson(
    await client.call('authoring.grant', <String, Object?>{
      'request': intent.toJson(),
    }),
  );
  result.validateAgainst(intent);
  return result;
}

final class _AuthoringProof {
  const _AuthoringProof({
    required this.opened,
    required this.replayExact,
    required this.moved,
    required this.grantConsumed,
    required this.reviewPrepared,
    required this.findingRecorded,
    required this.conceptProposed,
    required this.acceptancePassed,
    required this.acceptanceSeparateFromHumanApproval,
  });

  final bool opened;
  final bool replayExact;
  final bool moved;
  final bool grantConsumed;
  final bool reviewPrepared;
  final bool findingRecorded;
  final bool conceptProposed;
  final bool acceptancePassed;
  final bool acceptanceSeparateFromHumanApproval;
}

final class _McpClient {
  _McpClient._({
    required this.process,
    required this.lines,
    required this.stderrDone,
  });

  static Future<_McpClient> start({required String configuration}) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        'apps/workspace_cli/bin/workspace.dart',
        'mcp',
        'serve',
        '--config',
        configuration,
      ],
      workingDirectory: Directory.current.path,
      mode: ProcessStartMode.normal,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrDone = _readBounded(process.stderr, 256 * 1024);
    return _McpClient._(process: process, lines: lines, stderrDone: stderrDone);
  }

  final Process process;
  final StreamIterator<String> lines;
  final Future<String> stderrDone;
  var _sequence = 0;
  var _closed = false;

  static const Map<String, Object?> _meta = <String, Object?>{
    'io.modelcontextprotocol/protocolVersion': '2026-07-28',
    'io.modelcontextprotocol/clientInfo': <String, Object?>{
      'name': 'ep7-vertical',
      'version': '1',
    },
    'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
  };

  Future<Map<String, Object?>> request(String method, {Object? params}) async {
    final id = 'probe-${++_sequence}';
    process.stdin.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
        if (method != 'server/discover') '_meta': _meta,
      }),
    );
    await process.stdin.flush();
    final available = await lines.moveNext().timeout(
      const Duration(minutes: 2),
    );
    if (!available) throw const FormatException('server-closed');
    final response = _map(jsonDecode(lines.current), 'response');
    if (response['id'] != id) throw const FormatException('response-id');
    return response;
  }

  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final response = await request(
      'tools/call',
      params: <String, Object?>{'name': name, 'arguments': arguments},
    );
    if (response['error'] case final Map<String, Object?> error) {
      throw _ToolCallFailure('rpc-${error['code']}');
    }
    final result = _result(response);
    if (result['isError'] != false) {
      final content = _map(result['structuredContent'], 'structuredContent');
      throw _ToolCallFailure(_string(content, 'errorCode'));
    }
    return _map(result['structuredContent'], 'structuredContent');
  }

  Future<String> callError(String name, Map<String, Object?> arguments) async {
    final response = await request(
      'tools/call',
      params: <String, Object?>{'name': name, 'arguments': arguments},
    );
    final result = _result(response);
    if (result['isError'] != true) {
      throw const FormatException('tool-succeeded');
    }
    return _string(_map(result['structuredContent'], 'error'), 'errorCode');
  }

  Future<Map<String, Object?>> readResource(String uri) async {
    final response = await request(
      'resources/read',
      params: <String, Object?>{'uri': uri},
    );
    final contents = _list(_result(response)['contents'], 'contents');
    if (contents.length != 1) throw const FormatException('resource-count');
    final content = _map(contents.single, 'content');
    return _map(jsonDecode(_string(content, 'text')), 'resource');
  }

  Future<Map<String, Object?>> issueCapability({
    required String requestId,
    required String tool,
    required Digest expectedDigest,
    required Map<String, Object?> input,
  }) => call('capability.issue', <String, Object?>{
    'requestId': requestId,
    'tool': tool,
    'expectedDigest': expectedDigest.value,
    'input': input,
  });

  Future<_ProcessResult> close() async {
    if (_closed) throw StateError('client already closed');
    _closed = true;
    await process.stdin.close();
    final exit = await process.exitCode.timeout(const Duration(minutes: 2));
    await lines.cancel();
    return _ProcessResult(exitCode: exit, stderr: await stderrDone);
  }

  Future<void> closeIfNeeded() async {
    if (_closed) return;
    _closed = true;
    await process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await lines.cancel();
    await stderrDone;
  }
}

final class _ToolCallFailure implements Exception {
  const _ToolCallFailure(this.code);

  final String code;
}

final class _ProcessResult {
  const _ProcessResult({required this.exitCode, required this.stderr});

  final int exitCode;
  final String stderr;
}

Map<String, Object?> _effect({
  required String requestId,
  required Map<String, Object?> capability,
  required Digest expectedDigest,
  required Map<String, Object?> input,
}) => <String, Object?>{
  'requestId': requestId,
  'capabilityId': capability['id'],
  'capabilityDigest': capability['digest'],
  'expectedDigest': expectedDigest.value,
  'input': input,
};

void _writeEffectFixtures(String workspace) {
  File(
    p.join(workspace, 'capture.png'),
  ).writeAsBytesSync(_rgbaPng(const <int>[20, 40, 60, 255]), flush: true);
  final source = File(p.join(workspace, 'lib', 'app_factory.dart'));
  source.writeAsStringSync(
    '${source.readAsStringSync()}\nconst mcpProbeSecret = "Bearer MCP_REDACTION_SECRET";\n',
    flush: true,
  );
  final testDirectory = Directory(p.join(workspace, 'test'))
    ..createSync(recursive: true);
  File(p.join(workspace, 'pubspec.yaml')).writeAsStringSync(
    'name: mcp_probe_fixture\npublish_to: none\nenvironment:\n  sdk: ^3.12.0\ndev_dependencies:\n  test: any\n',
    flush: true,
  );
  File(p.join(testDirectory.path, 'mcp_smoke_test.dart')).writeAsStringSync(
    "import 'package:test/test.dart';\nvoid main() { test('mcp smoke', () { expect(2 + 2, 4); }); }\n",
    flush: true,
  );
}

List<int> _rgbaPng(List<int> pixels) {
  final header = Uint8List(13);
  final headerData = ByteData.sublistView(header);
  headerData.setUint32(0, 1);
  headerData.setUint32(4, 1);
  header[8] = 8;
  header[9] = 6;
  final compressed = ZLibCodec().encode(<int>[0, ...pixels]);
  return <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ..._pngChunk('IHDR', header),
    ..._pngChunk('IDAT', compressed),
    ..._pngChunk('IEND', const <int>[]),
  ];
}

List<int> _pngChunk(String type, List<int> data) => <int>[
  ..._uint32(data.length),
  ...type.codeUnits,
  ...data,
  ..._uint32(_pngCrc32(<int>[...type.codeUnits, ...data])),
];

List<int> _uint32(int value) => <int>[
  (value >>> 24) & 0xff,
  (value >>> 16) & 0xff,
  (value >>> 8) & 0xff,
  value & 0xff,
];

int _pngCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Map<String, String?> _options(List<String> arguments) {
  String? value(String name) {
    final prefix = '--$name=';
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument.startsWith(prefix)) return argument.substring(prefix.length);
      if (argument == '--$name' && index + 1 < arguments.length) {
        return arguments[index + 1];
      }
    }
    return null;
  }

  return <String, String?>{
    'config': value('config'),
    'workspace': value('workspace'),
  };
}

Map<String, Object?> _result(Map<String, Object?> response) {
  if (response.containsKey('error')) throw const FormatException('rpc-error');
  return _map(response['result'], 'result');
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is! Map<String, Object?>) throw FormatException('$path-object');
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path-list');
  return value;
}

List<Map<String, Object?>> _maps(Object? value, String path) =>
    _list(value, path).map((item) => _map(item, path)).toList(growable: false);

String _string(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) throw FormatException('$key-string');
  return result;
}

void _require(bool condition, String reason) {
  if (!condition) throw FormatException(reason);
}

Future<String> _readBounded(Stream<List<int>> stream, int limit) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('stderr-oversized');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: false).trim();
}

const Set<String> _requiredResources = <String>{
  'experience://content-set',
  'experience://catalog',
  'experience://topology',
  'experience://facets',
  'experience://scenario-lab',
  'experience://motion',
};

const Set<String> _effectTools = <String>{
  'capability.issue',
  'capability.revoke',
  'quality.tests.run',
  'quality.capture',
  'authoring.grant',
  'authoring.openDraft',
  'authoring.layout.edit',
  'authoring.layout.batchMutate',
  'authoring.review.prepare',
  'authoring.finding.record',
  'authoring.concept.propose',
  'quality.acceptance.record',
  'authoring.layout.promote',
};

const Set<String> _requiredTools = <String>{
  'source.inspect',
  'source.diff',
  'source.impact.plan',
  'evidence.bundle.verify',
  'catalog.list',
  'catalog.search',
  'catalog.get',
  'catalog.neighborhood',
  'catalog.graph',
  'context.export',
  'source.excerpt',
  'evidence.index',
  'capture.index',
  'quality.validate',
  'quality.tests.run',
  'quality.capture',
  'quality.capture.diff',
  'quality.bundle.verify',
  'quality.evidence.verify',
  'capability.issue',
  'capability.revoke',
  'authoring.describe',
  'authoring.getHead',
  'authoring.getDraft',
  'authoring.getChangeSet',
  'authoring.getReview',
  'authoring.grant',
  'authoring.openDraft',
  'authoring.layout.edit',
  'authoring.layout.batchMutate',
  'authoring.review.prepare',
  'authoring.finding.record',
  'authoring.concept.propose',
  'quality.acceptance.record',
  'authoring.layout.promote',
};
