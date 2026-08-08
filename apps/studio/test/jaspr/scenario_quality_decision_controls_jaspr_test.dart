@TestOn('vm')
library;

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/jaspr/scenario_lab_quality_pages.dart';
import 'package:studio/src/jaspr/verified_artifact_image.dart';
import 'package:studio/src/quality/scenario_quality_decision_controls.dart';
import 'package:studio/src/quality/studio_scenario_quality_transport.dart';

import '../support/scenario_quality_decision_fixture.dart';

void main() {
  testComponents(
    'renders pinned guide, gates confirmation on image readiness and publishes history',
    (tester) async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      tester.pumpComponent(
        ScenarioQualityDecisionExperience(
          catalog: fixture.lab.catalog,
          manifest: fixture.lab.manifest,
          scenarioId: fixture.lab.scenarioId,
          scriptId: fixture.lab.scriptId,
          rpcMethods: studioScenarioQualityRpcMethods,
          runSnapshot: fixture.result.finalSnapshot,
          runResult: fixture.result,
          qualityClient: host,
          resourceClient: host,
        ),
      );
      await _settle(tester);

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-review-availability': 'available',
          'data-quality-decision-operation': 'ready',
          'data-quality-decision-count': '0',
          'data-quality-decision-requirement': 'approval',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'role': 'status',
          'aria-live': 'polite',
          'aria-atomic': 'true',
        }),
        findsOneComponent,
      );
      expect(
        find.text('Compare every required artifact before deciding.'),
        findsOneComponent,
      );
      expect(
        find.textContaining(
          'The required state is legible and matches the expected baseline.',
        ),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-resource-state': 'validated',
        }),
        findsNComponents(3),
      );
      expect(_enabledAction('approve'), findsNothing);
      expect(host.grantRequests, isEmpty);

      await _markImagesRendered(tester);
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-resource-state': 'rendered',
        }),
        findsNComponents(3),
      );
      expect(_enabledAction('approve'), findsOneComponent);

      await tester.click(_action('approve'));
      expect(host.grantRequests, isEmpty);
      expect(
        _domWithAttributes(const <String, String>{
          'aria-modal': 'true',
          'aria-labelledby': 'scenario-quality-decision-confirmation-title',
          'aria-describedby':
              'scenario-quality-decision-confirmation-description',
        }),
        findsOneComponent,
      );
      expect(find.tag('dialog'), findsOneComponent);
      expect(_action('confirm'), findsOneComponent);
      expect(_action('cancel'), findsOneComponent);
      expect(_action('approve'), findsOneComponent);
      expect(_autofocusedAction('confirm'), findsOneComponent);

      await tester.click(_action('cancel'));
      expect(find.tag('dialog'), findsNothing);
      expect(host.grantRequests, isEmpty);
      expect(_enabledAction('approve'), findsOneComponent);

      await tester.click(_action('approve'));

      await tester.click(_action('confirm'));
      await _settle(tester);
      expect(host.grantRequests, hasLength(1));
      expect(host.appendRequests, hasLength(1));
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-decision-count': '1',
          'data-quality-decision-policy': 'fixture-policy',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-decision-record': 'decision-0001',
          'data-quality-human-decision': 'approved',
        }),
        findsOneComponent,
      );
      expect(_action('supersede-rejected'), findsOneComponent);
      expect(_action('supersede-approved'), findsNothing);

      final publicDom = _allDomText();
      expect(publicDom, isNot(contains('/resources/')));
      expect(publicDom, isNot(contains('http://127.0.0.1:7367')));
      expect(publicDom, isNot(contains('grant-0001')));
      expect(publicDom, isNot(contains('token')));
    },
  );

  testComponents('partial capability quintet fails closed before Host calls', (
    tester,
  ) async {
    final fixture = ScenarioQualityDecisionTestFixture();
    final host = FakeScenarioQualityHost(fixture);
    tester.pumpComponent(
      ScenarioQualityDecisionExperience(
        catalog: fixture.lab.catalog,
        manifest: fixture.lab.manifest,
        scenarioId: fixture.lab.scenarioId,
        scriptId: fixture.lab.scriptId,
        rpcMethods: studioScenarioQualityRpcMethods.difference(const <String>{
          'quality.decision.get',
        }),
        runSnapshot: fixture.result.finalSnapshot,
        runResult: fixture.result,
        qualityClient: host,
        resourceClient: host,
      ),
    );
    await _settle(tester);

    expect(
      _domWithAttributes(const <String, String>{
        'data-quality-decision-operation': 'protocolViolation',
        'data-quality-review-availability': 'unsupported',
      }),
      findsOneComponent,
    );
    expect(host.describeRequests, isEmpty);
    expect(host.openRequests, isEmpty);
    expect(host.grantRequests, isEmpty);
    expect(_enabledAction('approve'), findsNothing);
  });

  testComponents(
    'callbacks from disposed review images cannot validate a refresh',
    (tester) async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      tester.pumpComponent(
        ScenarioQualityDecisionExperience(
          catalog: fixture.lab.catalog,
          manifest: fixture.lab.manifest,
          scenarioId: fixture.lab.scenarioId,
          scriptId: fixture.lab.scriptId,
          rpcMethods: studioScenarioQualityRpcMethods,
          runSnapshot: fixture.result.finalSnapshot,
          runResult: fixture.result,
          qualityClient: host,
          resourceClient: host,
        ),
      );
      await _settle(tester);
      final staleImages = find
          .byComponentPredicate(
            (component) => component is VerifiedArtifactImage,
            description: 'stale verified review image',
          )
          .evaluate()
          .map((element) => element.component as VerifiedArtifactImage)
          .toList(growable: false);
      expect(staleImages, hasLength(3));

      await tester.click(_action('refresh'));
      await _settle(tester);
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-resource-state': 'validated',
        }),
        findsNComponents(3),
      );
      for (final stale in staleImages) {
        stale.onStatusChanged?.call(VerifiedArtifactImageStatus.rendered);
      }
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-resource-state': 'validated',
        }),
        findsNComponents(3),
      );
      expect(_enabledAction('approve'), findsNothing);
      expect(host.grantRequests, isEmpty);
    },
  );

  testComponents(
    'existing Quality route owns review and Lab stays action-free',
    (tester) async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      tester.pumpComponent(
        ScenarioQualityRoutePage(
          enabled: true,
          labEnabled: true,
          catalog: fixture.lab.catalog,
          manifest: fixture.lab.manifest,
          hasContentGeneration: true,
          scenarioId: fixture.lab.scenarioId.value,
          scriptId: fixture.lab.scriptId.value,
          runSnapshot: fixture.result.finalSnapshot,
          runResult: fixture.result,
          selectedRunId: fixture.result.finalSnapshot.runId,
          qualityRpcMethods: studioScenarioQualityRpcMethods,
          qualityClient: host,
          qualityResourceClient: host,
        ),
      );
      await _settle(tester);

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-route-state': 'ready',
          'data-quality-selected-run-id': 'run-terminal',
        }),
        findsOneComponent,
      );
      expect(_action('approve'), findsOneComponent);
      expect(find.text('Iniciar execução'), findsNothing);
      expect(find.text('Cancelar execução'), findsNothing);
    },
  );
}

Future<void> _settle(ComponentTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump();
  }
}

Future<void> _markImagesRendered(ComponentTester tester) async {
  final elements = find
      .byComponentPredicate(
        (component) => component is VerifiedArtifactImage,
        description: 'verified review image',
      )
      .evaluate()
      .toList(growable: false);
  expect(elements, hasLength(3));
  for (final element in elements) {
    final image = element.component as VerifiedArtifactImage;
    image.onStatusChanged?.call(VerifiedArtifactImageStatus.rendered);
  }
  await tester.pump();
}

Finder _action(String action) => _domWithAttributes(<String, String>{
  'data-quality-decision-action': action,
});

Finder _enabledAction(String action) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      component.attributes?['data-quality-decision-action'] == action &&
      component.attributes?['disabled'] == null,
  description: 'enabled Quality action $action',
);

Finder _autofocusedAction(String action) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      component.attributes?['data-quality-decision-action'] == action &&
      component.attributes?['autofocus'] != null,
  description: 'autofocused Quality action $action',
);

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

String _allDomText() => find
    .byComponentPredicate(
      (component) => component is DomComponent,
      description: 'all DOM components',
    )
    .evaluate()
    .map((element) => element.component.toString())
    .join('\n');
