import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ScenarioLabManifest', () {
    test(
      'round-trips a closed catalog-bound manifest and validates schema',
      () {
        final catalog = _catalog();
        final manifest = _manifest(catalog);
        final decoded = ScenarioLabManifest.fromJson(
          manifest.toJson(),
          catalog: catalog,
        );
        final validation = _schemaValidator().validate(manifest.toJson());

        expect(
          validation.isValid,
          isTrue,
          reason: validation.issues.join('\n'),
        );
        expect(decoded.toJson(), manifest.toJson());
        expect(decoded.digest, manifest.digest);
        expect(decoded.catalogDigest, catalog.digest);
        expect(ScenarioLabManifest.schemaVersion, 1);
        expect(
          decoded.scripts.single.steps.first,
          isA<ExecutionBindingScenarioScriptStep>(),
        );
        expect(decoded.automatedAcceptanceCriteria, hasLength(3));
        expect(decoded.humanApprovalRequirements, hasLength(1));
      },
    );

    test('allows a schema-valid binding-only Lab plan', () {
      final catalog = _catalog();
      final manifest = ScenarioLabManifest(
        catalog: catalog,
        appAdapterCapabilities: const <CapabilityDescriptor>[],
        controls: const <ScenarioControlDefinition>[],
        operations: const <ScenarioLabOperationDefinition>[],
        scripts: <ScenarioScriptDefinition>[
          ScenarioScriptDefinition(
            id: ScenarioScriptId('open-ready'),
            scenarioId: ScenarioId('ready'),
            displayName: 'Open ready state',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
            steps: <ScenarioScriptStep>[
              ExecutionBindingScenarioScriptStep(
                id: 'prepare',
                timeoutMs: 10000,
                timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
                bindingId: ScenarioExecutionBindingId('ready-web'),
              ),
            ],
          ),
        ],
        automatedAcceptanceCriteria: const <AutomatedAcceptanceCriterion>[],
        requiredEvidence: const <RequiredEvidenceDefinition>[],
        comparisonBindings: const <ScenarioComparisonBinding>[],
        visualComparisonPolicies: const <VisualComparisonPolicy>[],
        semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
        humanApprovalRequirements: const <HumanApprovalRequirement>[],
        supplementalArtifacts: const <SupplementalArtifactReference>[],
        plans: <ScenarioLabPlan>[
          ScenarioLabPlan(
            scenarioId: ScenarioId('ready'),
            executionBindingIds: <ScenarioExecutionBindingId>[
              ScenarioExecutionBindingId('ready-web'),
            ],
            controlIds: const <ScenarioControlId>[],
            operationIds: const <ScenarioLabOperationId>[],
            scriptIds: <ScenarioScriptId>[ScenarioScriptId('open-ready')],
            automatedAcceptanceCriterionIds:
                const <AutomatedAcceptanceCriterionId>[],
            requiredEvidenceIds: const <RequiredEvidenceId>[],
            comparisonBindingIds: const <ScenarioComparisonBindingId>[],
            humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
            supplementalArtifactIds: const <SupplementalArtifactId>[],
          ),
        ],
      );

      final validation = _schemaValidator().validate(manifest.toJson());
      expect(validation.isValid, isTrue, reason: validation.issues.join('\n'));
      expect(
        ScenarioLabManifest.fromJson(
          manifest.toJson(),
          catalog: catalog,
        ).toJson(),
        manifest.toJson(),
      );
    });

    test('canonicalizes registries while preserving ordered script steps', () {
      final catalog = _catalog();
      final forward = _manifest(catalog);
      final reverse = ScenarioLabManifest(
        catalog: catalog,
        appAdapterCapabilities: forward.appAdapterCapabilities.reversed,
        controls: forward.controls.reversed,
        operations: forward.operations.reversed,
        scripts: forward.scripts.reversed,
        automatedAcceptanceCriteria:
            forward.automatedAcceptanceCriteria.reversed,
        requiredEvidence: forward.requiredEvidence.reversed,
        comparisonBindings: forward.comparisonBindings.reversed,
        visualComparisonPolicies: forward.visualComparisonPolicies.reversed,
        semanticComparisonPolicies: forward.semanticComparisonPolicies.reversed,
        humanApprovalRequirements: forward.humanApprovalRequirements.reversed,
        supplementalArtifacts: forward.supplementalArtifacts.reversed,
        plans: forward.plans.reversed,
      );

      expect(reverse.toJson(), forward.toJson());
      expect(reverse.digest, forward.digest);
      expect(
        const JcsCanonicalizer().canonicalize(reverse.toJson()),
        const JcsCanonicalizer().canonicalize(forward.toJson()),
      );
      expect(reverse.scripts.single.steps.map((step) => step.id), <String>[
        'prepare',
        'set-locale',
        'collect',
        'reset-locale',
      ]);
    });

    test('rejects unknown fields, adjacent versions and forged digests', () {
      final catalog = _catalog();
      final source = _manifest(catalog).toJson();

      final unknown = _copy(source)..['metadata'] = <String, Object?>{};
      expect(
        () => ScenarioLabManifest.fromJson(unknown, catalog: catalog),
        throwsFormatException,
      );

      final adjacent = _copy(source)..['schemaVersion'] = 2;
      _redigest(adjacent);
      expect(
        () => ScenarioLabManifest.fromJson(adjacent, catalog: catalog),
        throwsFormatException,
      );

      final forged = _copy(source)
        ..['digest'] = Digest.semantic('forged').value;
      expect(
        () => ScenarioLabManifest.fromJson(forged, catalog: catalog),
        throwsFormatException,
      );

      expect(
        () => ScenarioLabManifest.fromJson(source, catalog: _catalog('Other')),
        throwsFormatException,
      );
    });

    test('control values and domains are sealed discriminated unions', () {
      final values = <ScenarioControlValue>[
        const BooleanScenarioControlValue(true),
        ChoiceScenarioControlValue(ControlChoiceId('pt-br')),
        const IntegerScenarioControlValue(3),
      ];
      for (final value in values) {
        expect(
          ScenarioControlValue.fromJson(value.toJson()).toJson(),
          value.toJson(),
        );
      }

      final domains = <ScenarioControlDomain>[
        BooleanScenarioControlDomain(defaultValue: false),
        ChoiceScenarioControlDomain(
          defaultValue: ControlChoiceId('en-us'),
          choices: <ScenarioControlChoice>[
            ScenarioControlChoice(
              id: ControlChoiceId('en-us'),
              displayName: 'English',
            ),
            ScenarioControlChoice(
              id: ControlChoiceId('pt-br'),
              displayName: 'Portuguese',
            ),
          ],
        ),
        IntegerRangeScenarioControlDomain(
          defaultValue: 2,
          minimum: 0,
          maximum: 10,
          step: 2,
        ),
      ];
      for (final domain in domains) {
        expect(
          ScenarioControlDomain.fromJson(domain.toJson()).toJson(),
          domain.toJson(),
        );
      }

      expect(
        () => ScenarioControlValue.fromJson(<String, Object?>{
          'kind': 'dynamic',
          'value': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => ScenarioControlValue.fromJson(<String, Object?>{
          'kind': 'boolean',
          'value': true,
          'metadata': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('scripts are ordered, bounded and binding/operation allowlisted', () {
      final catalog = _catalog();
      final source = _manifest(catalog).toJson();

      final arbitraryOperation = _copy(source);
      final scripts = arbitraryOperation['scripts']! as List<Object?>;
      final script = scripts.single! as Map<String, Object?>;
      final steps = script['steps']! as List<Object?>;
      (steps[1]! as Map<String, Object?>)['operationId'] = 'undeclared';
      _redigest(arbitraryOperation);
      expect(
        () =>
            ScenarioLabManifest.fromJson(arbitraryOperation, catalog: catalog),
        throwsArgumentError,
      );

      final missingTimeout = _copy(source);
      final missingScripts = missingTimeout['scripts']! as List<Object?>;
      final missingSteps =
          (missingScripts.single! as Map<String, Object?>)['steps']!
              as List<Object?>;
      (missingSteps[1]! as Map<String, Object?>).remove('timeoutMs');
      _redigest(missingTimeout);
      expect(
        () => ScenarioLabManifest.fromJson(missingTimeout, catalog: catalog),
        throwsFormatException,
      );

      expect(
        () => ScenarioScriptDefinition(
          id: ScenarioScriptId('invalid'),
          scenarioId: ScenarioId('ready'),
          displayName: 'Invalid',
          timeoutMs: 1000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
          steps: <ScenarioScriptStep>[
            OperationScenarioScriptStep(
              id: 'operation-first',
              timeoutMs: 100,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              operationId: ScenarioLabOperationId('set-locale'),
            ),
            ExecutionBindingScenarioScriptStep(
              id: 'prepare',
              timeoutMs: 100,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
              bindingId: ScenarioExecutionBindingId('ready-web'),
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test(
      'rejects stale evidence, unregistered policies and loose artifacts',
      () {
        final catalog = _catalog();
        final source = _manifest(catalog).toJson();

        final stale = _copy(source);
        final evidence = stale['requiredEvidence']! as List<Object?>;
        (evidence.single! as Map<String, Object?>)['freshness'] = 'stale';
        _redigest(stale);
        expect(
          () => ScenarioLabManifest.fromJson(stale, catalog: catalog),
          throwsArgumentError,
        );

        final missingPolicy = _copy(source);
        final requirements =
            missingPolicy['requiredEvidence']! as List<Object?>;
        final comparison =
            (requirements.single! as Map<String, Object?>)['comparisonPolicy']!
                as Map<String, Object?>;
        comparison['policyId'] = 'missing';
        _redigest(missingPolicy);
        expect(
          () => ScenarioLabManifest.fromJson(missingPolicy, catalog: catalog),
          throwsArgumentError,
        );

        final looseArtifact = _copy(source);
        final artifacts =
            looseArtifact['supplementalArtifacts']! as List<Object?>;
        (artifacts.single! as Map<String, Object?>)['path'] = '/tmp/result.png';
        _redigest(looseArtifact);
        expect(
          () => ScenarioLabManifest.fromJson(looseArtifact, catalog: catalog),
          throwsFormatException,
        );
      },
    );

    test(
      'comparison inputs pin baseline/candidate without latest-Evidence inference',
      () {
        final digest = Digest.semantic('comparison-input');
        final inputs = <ComparisonInputReference>[
          ArtifactComparisonInputReference(
            artifactId: SupplementalArtifactId('baseline-artifact'),
          ),
          EvidenceComparisonInputReference(
            evidenceDigest: digest,
            provenanceDigest: Digest.semantic('evidence-provenance'),
            classification: ArtifactClassification.internal,
          ),
          RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: RequiredEvidenceId('ready-visual'),
          ),
        ];
        for (final input in inputs) {
          expect(
            ComparisonInputReference.fromJson(input.toJson()).toJson(),
            input.toJson(),
          );
        }

        final catalog = _catalog();
        final roleMismatch = _copy(_manifest(catalog).toJson());
        final artifacts =
            roleMismatch['supplementalArtifacts']! as List<Object?>;
        (artifacts.single! as Map<String, Object?>)['role'] = 'diagnostic';
        _redigest(roleMismatch);
        expect(
          () => ScenarioLabManifest.fromJson(roleMismatch, catalog: catalog),
          throwsArgumentError,
        );

        final currentCollectionCandidate = _copy(_manifest(catalog).toJson());
        final currentCollectionBindings =
            currentCollectionCandidate['comparisonBindings']! as List<Object?>;
        (currentCollectionBindings.single!
            as Map<String, Object?>)['candidate'] = <String, Object?>{
          'kind': 'requiredEvidence',
          'requiredEvidenceId': 'ready-visual',
        };
        _redigest(currentCollectionCandidate);
        final currentCollectionValidation = _schemaValidator().validate(
          currentCollectionCandidate,
        );
        expect(
          currentCollectionValidation.isValid,
          isTrue,
          reason: currentCollectionValidation.issues.join('\n'),
        );
        final decodedCurrentCollection = ScenarioLabManifest.fromJson(
          currentCollectionCandidate,
          catalog: catalog,
        );
        expect(
          decodedCurrentCollection.comparisonBindings.single.candidate,
          isA<RequiredEvidenceComparisonInputReference>().having(
            (input) => input.requiredEvidenceId.value,
            'requiredEvidenceId',
            'ready-visual',
          ),
        );

        final currentCollectionBaseline = _copy(currentCollectionCandidate);
        final currentCollectionBaselineBindings =
            currentCollectionBaseline['comparisonBindings']! as List<Object?>;
        final currentCollectionBaselineBinding =
            currentCollectionBaselineBindings.single! as Map<String, Object?>;
        currentCollectionBaselineBinding['baseline'] = <String, Object?>{
          'kind': 'requiredEvidence',
          'requiredEvidenceId': 'ready-visual',
        };
        currentCollectionBaselineBinding['candidate'] = <String, Object?>{
          'kind': 'evidence',
          'evidenceDigest': Digest.semantic('baseline-test-evidence').value,
          'provenanceDigest': Digest.semantic('baseline-test-provenance').value,
          'classification': 'internal',
        };
        _redigest(currentCollectionBaseline);
        expect(
          () => ScenarioLabManifest.fromJson(
            currentCollectionBaseline,
            catalog: catalog,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => '${error.message}',
              'message',
              contains('candidate-only'),
            ),
          ),
        );

        expect(
          () => ComparisonInputReference.fromJson(<String, Object?>{
            'kind': 'requiredEvidence',
            'requiredEvidenceId': 'ready-visual',
            'artifactId': 'not-allowed',
          }),
          throwsFormatException,
        );

        expect(
          () => ScenarioComparisonBinding(
            id: ScenarioComparisonBindingId('same-input'),
            scenarioId: ScenarioId('ready'),
            requiredEvidenceId: RequiredEvidenceId('ready-visual'),
            baseline: RequiredEvidenceComparisonInputReference(
              requiredEvidenceId: RequiredEvidenceId('ready-visual'),
            ),
            candidate: RequiredEvidenceComparisonInputReference(
              requiredEvidenceId: RequiredEvidenceId('ready-visual'),
            ),
          ),
          throwsArgumentError,
        );

        final cycle = _copy(_manifest(catalog).toJson());
        final requirements = cycle['requiredEvidence']! as List<Object?>;
        requirements.add(<String, Object?>{
          ...(requirements.single! as Map<String, Object?>),
          'id': 'baseline-visual',
        });
        final cycleBindings = cycle['comparisonBindings']! as List<Object?>;
        (cycleBindings.single!
            as Map<String, Object?>)['candidate'] = <String, Object?>{
          'kind': 'requiredEvidence',
          'requiredEvidenceId': 'baseline-visual',
        };
        cycleBindings.add(<String, Object?>{
          'id': 'baseline-comparison',
          'scenarioId': 'ready',
          'requiredEvidenceId': 'baseline-visual',
          'baseline': <String, Object?>{
            'kind': 'evidence',
            'evidenceDigest': Digest.semantic('baseline-evidence').value,
            'provenanceDigest': Digest.semantic('baseline-provenance').value,
            'classification': 'internal',
          },
          'candidate': <String, Object?>{
            'kind': 'requiredEvidence',
            'requiredEvidenceId': 'ready-visual',
          },
        });
        final operations = cycle['operations']! as List<Object?>;
        operations.add(<String, Object?>{
          'id': 'collect-baseline',
          'scenarioId': 'ready',
          'kind': 'collectEvidence',
          'evidenceRequirementId': 'baseline-visual',
        });
        final scripts = cycle['scripts']! as List<Object?>;
        final steps =
            (scripts.single! as Map<String, Object?>)['steps']!
                as List<Object?>;
        steps.add(<String, Object?>{
          'id': 'collect-baseline',
          'kind': 'operation',
          'operationId': 'collect-baseline',
          'timeoutMs': 10000,
          'timeoutOutcome': 'fail',
        });
        final criteria = cycle['automatedAcceptanceCriteria']! as List<Object?>;
        criteria.add(<String, Object?>{
          'id': 'baseline-accepted',
          'scenarioId': 'ready',
          'displayName': 'Baseline Evidence is accepted',
          'kind': 'evidenceAccepted',
          'evidenceRequirementId': 'baseline-visual',
        });
        final plans = cycle['plans']! as List<Object?>;
        final plan = plans.single! as Map<String, Object?>;
        (plan['operationIds']! as List<Object?>).add('collect-baseline');
        (plan['automatedAcceptanceCriterionIds']! as List<Object?>).add(
          'baseline-accepted',
        );
        (plan['requiredEvidenceIds']! as List<Object?>).add('baseline-visual');
        (plan['comparisonBindingIds']! as List<Object?>).add(
          'baseline-comparison',
        );
        _redigest(cycle);
        expect(
          () => ScenarioLabManifest.fromJson(cycle, catalog: catalog),
          throwsA(
            isA<ArgumentError>().having(
              (error) => '${error.message}',
              'message',
              contains('acyclic graph'),
            ),
          ),
        );
      },
    );

    test('keeps automated acceptance distinct from human approval', () {
      final manifest = _manifest(_catalog());
      final automatedJson = manifest.automatedAcceptanceCriteria
          .map((criterion) => criterion.toJson())
          .toList();
      final humanJson = manifest.humanApprovalRequirements.single.toJson();

      expect(
        automatedJson.every(
          (criterion) =>
              !criterion.containsKey('reviewGuideId') &&
              !criterion.containsKey('reviewGuideStepId'),
        ),
        isTrue,
      );
      expect(humanJson.containsKey('kind'), isFalse);
      expect(humanJson['reviewGuideId'], 'ready-review');
      expect(humanJson['reviewGuideStepId'], 'inspect-ready');
    });

    test('enforces public ID and timeout limits', () {
      expect(() => ScenarioControlId('a${'x' * 256}'), throwsFormatException);
      expect(
        () => OperationScenarioScriptStep(
          id: 'set-locale',
          timeoutMs: 0,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          operationId: ScenarioLabOperationId('set-locale'),
        ),
        throwsArgumentError,
      );
      expect(
        () => HumanApprovalRequirement(
          id: HumanApprovalRequirementId('approve'),
          scenarioId: ScenarioId('ready'),
          reviewGuideId: ReviewGuideId('ready-review'),
          reviewGuideStepId: 'a${'x' * 256}',
          scope: HumanApprovalScope.scenarioRun,
        ),
        throwsFormatException,
      );
    });
  });
}

CatalogManifest _catalog([String workspaceName = 'Delivery Lab']) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('delivery-lab');
  final applicationId = ApplicationId('delivery-app');
  final scenarioId = ScenarioId('ready');
  final bindingId = ScenarioExecutionBindingId('ready-web');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: workspaceName),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Delivery app',
        root: 'apps/delivery',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(
        id: scenarioId,
        applicationId: applicationId,
        title: 'Ready deliveries',
      ),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: bindingId,
        scenarioId: scenarioId,
        targetId: 'chrome',
        launchProfileId: 'delivery-web',
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('ready-review'),
        applicationId: applicationId,
        title: 'Ready review',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'inspect-ready',
            instruction: 'Inspect the ready delivery list.',
            observationCriteria: 'The delivery cards are complete and legible.',
            scenarioId: scenarioId,
            bindingId: bindingId,
          ),
        ],
      ),
    ],
  );
}

ScenarioLabManifest _manifest(CatalogManifest catalog) {
  final scenarioId = ScenarioId('ready');
  final controlId = ScenarioControlId('locale');
  final evidenceId = RequiredEvidenceId('ready-visual');
  final scriptId = ScenarioScriptId('exercise-ready');
  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'sample.locale',
        version: 1,
        operations: <String>{'read', 'write', 'reset'},
      ),
    ],
    controls: <ScenarioControlDefinition>[
      ScenarioControlDefinition(
        id: controlId,
        scenarioId: scenarioId,
        displayName: 'Locale',
        capability: AppAdapterCapabilityReference(
          id: AppAdapterCapabilityId('sample.locale'),
          version: 1,
        ),
        readOperationId: CapabilityOperationId('read'),
        writeOperationId: CapabilityOperationId('write'),
        resetOperationId: CapabilityOperationId('reset'),
        domain: ChoiceScenarioControlDomain(
          defaultValue: ControlChoiceId('en-us'),
          choices: <ScenarioControlChoice>[
            ScenarioControlChoice(
              id: ControlChoiceId('en-us'),
              displayName: 'English',
            ),
            ScenarioControlChoice(
              id: ControlChoiceId('pt-br'),
              displayName: 'Portuguese',
            ),
          ],
        ),
      ),
    ],
    operations: <ScenarioLabOperationDefinition>[
      AssignControlOperationDefinition(
        id: ScenarioLabOperationId('set-locale'),
        scenarioId: scenarioId,
        controlId: controlId,
        value: ChoiceScenarioControlValue(ControlChoiceId('pt-br')),
      ),
      CollectEvidenceOperationDefinition(
        id: ScenarioLabOperationId('collect-ready'),
        scenarioId: scenarioId,
        evidenceRequirementId: evidenceId,
      ),
      ResetControlOperationDefinition(
        id: ScenarioLabOperationId('reset-locale'),
        scenarioId: scenarioId,
        controlId: controlId,
      ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Exercise ready state',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'prepare',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
            bindingId: ScenarioExecutionBindingId('ready-web'),
          ),
          OperationScenarioScriptStep(
            id: 'set-locale',
            timeoutMs: 2000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('set-locale'),
          ),
          OperationScenarioScriptStep(
            id: 'collect',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('collect-ready'),
          ),
          OperationScenarioScriptStep(
            id: 'reset-locale',
            timeoutMs: 2000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('reset-locale'),
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      ScriptSucceededAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('script-succeeds'),
        scenarioId: scenarioId,
        displayName: 'Script succeeds',
        scriptId: scriptId,
      ),
      EvidenceAcceptedAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('visual-accepted'),
        scenarioId: scenarioId,
        displayName: 'Visual Evidence is accepted',
        evidenceRequirementId: evidenceId,
      ),
      ControlEqualsAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('locale-restored'),
        scenarioId: scenarioId,
        displayName: 'Locale is restored',
        controlId: controlId,
        expectedValue: ChoiceScenarioControlValue(ControlChoiceId('en-us')),
      ),
    ],
    requiredEvidence: <RequiredEvidenceDefinition>[
      RequiredEvidenceDefinition(
        id: evidenceId,
        scenarioId: scenarioId,
        providerId: ModuleId('evidence.auto-preview'),
        fidelity: RuntimeFidelity.structural,
        variantId: VariantId('phone-light'),
        freshness: EvidenceFreshness.fresh,
        allowedClassifications: <ArtifactClassification>{
          ArtifactClassification.public,
          ArtifactClassification.internal,
        },
        evidencePolicyId: EvidencePolicyId('static-v1'),
        comparisonPolicy: VisualComparisonPolicyReference(
          VisualComparisonPolicyId('pixel-v1'),
        ),
      ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      ScenarioComparisonBinding(
        id: ScenarioComparisonBindingId('ready-comparison'),
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        baseline: ArtifactComparisonInputReference(
          artifactId: SupplementalArtifactId('design-note'),
        ),
        candidate: EvidenceComparisonInputReference(
          evidenceDigest: Digest.semantic('ready-candidate-evidence'),
          provenanceDigest: Digest.semantic('ready-candidate-provenance'),
          classification: ArtifactClassification.internal,
        ),
      ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: 'pixel-v1',
        maxChannelDelta: 8,
        maxChangedPixelRatio: 0.01,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: <HumanApprovalRequirement>[
      HumanApprovalRequirement(
        id: HumanApprovalRequirementId('approve-ready'),
        scenarioId: scenarioId,
        reviewGuideId: ReviewGuideId('ready-review'),
        reviewGuideStepId: 'inspect-ready',
        scope: HumanApprovalScope.evidenceSet,
      ),
    ],
    supplementalArtifacts: <SupplementalArtifactReference>[
      SupplementalArtifactReference(
        id: SupplementalArtifactId('design-note'),
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        role: SupplementalArtifactRole.comparisonBaseline,
        artifactDigest: Digest.semantic('design-note'),
        provenanceDigest: Digest.semantic('design-note-provenance'),
        classification: ArtifactClassification.internal,
      ),
    ],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[
          ScenarioExecutionBindingId('ready-web'),
        ],
        controlIds: <ScenarioControlId>[controlId],
        operationIds: <ScenarioLabOperationId>[
          ScenarioLabOperationId('set-locale'),
          ScenarioLabOperationId('collect-ready'),
          ScenarioLabOperationId('reset-locale'),
        ],
        scriptIds: <ScenarioScriptId>[scriptId],
        automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
          AutomatedAcceptanceCriterionId('script-succeeds'),
          AutomatedAcceptanceCriterionId('visual-accepted'),
          AutomatedAcceptanceCriterionId('locale-restored'),
        ],
        requiredEvidenceIds: <RequiredEvidenceId>[evidenceId],
        comparisonBindingIds: <ScenarioComparisonBindingId>[
          ScenarioComparisonBindingId('ready-comparison'),
        ],
        humanApprovalRequirementIds: <HumanApprovalRequirementId>[
          HumanApprovalRequirementId('approve-ready'),
        ],
        supplementalArtifactIds: <SupplementalArtifactId>[
          SupplementalArtifactId('design-note'),
        ],
      ),
    ],
  );
}

Draft202012Validator _schemaValidator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _root(),
            'schemas',
            'catalog',
            'scenario-lab-manifest.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
);

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

void _redigest(Map<String, Object?> value) {
  final semantic = Map<String, Object?>.of(value)..remove('digest');
  value['digest'] = Digest.semantic(semantic).value;
}

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
