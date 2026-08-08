import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const planner = ScenarioLabExecutionPlanner();

  test('plans a binding-only script with both parent digest fences', () {
    final fixture = _fixture(bindingOnly: true);

    final result = _plan(planner, fixture, ScenarioId('ready'), 'open-ready');

    expect(result.catalogDigest, fixture.catalog.digest);
    expect(result.scenarioLabManifestDigest, fixture.manifest.digest);
    expect(result.plan.scenarioId, ScenarioId('ready'));
    expect(result.script.id, ScenarioScriptId('open-ready'));
    expect(result.initialBinding.id, ScenarioExecutionBindingId('ready-web'));
    expect(result.steps, hasLength(1));
    expect(result.steps.single, isA<PlannedScenarioLabExecutionBindingStep>());
    expect(() => result.steps.add(result.steps.single), throwsUnsupportedError);
  });

  test('materializes only the complete script allowlist in authored order', () {
    final fixture = _fixture();

    final result = _plan(
      planner,
      fixture,
      ScenarioId('ready'),
      'exercise-ready',
    );

    expect(
      result.steps.map((planned) => planned.step.toJson()).toList(),
      result.script.steps.map((step) => step.toJson()).toList(),
    );
    expect(result.steps.map((step) => step.runtimeType).toList(), <Type>[
      PlannedScenarioLabExecutionBindingStep,
      PlannedScenarioLabOperationStep,
      PlannedScenarioLabOperationStep,
    ]);
    expect(
      result.steps.whereType<PlannedScenarioLabOperationStep>().map(
        (step) => step.operation.id.value,
      ),
      <String>['enable-ready', 'reset-ready'],
    );
    expect(result.digest, Digest.semantic(result.toJson(includeDigest: false)));
  });

  test('is deterministic across equivalent registry input order', () {
    final forward = _fixture(includeOtherPlan: true);
    final reverse = _fixture(includeOtherPlan: true, reverseRegistries: true);

    final first = _plan(
      planner,
      forward,
      ScenarioId('ready'),
      'exercise-ready',
    );
    final second = _plan(
      planner,
      reverse,
      ScenarioId('ready'),
      'exercise-ready',
    );

    expect(reverse.catalog.digest, forward.catalog.digest);
    expect(reverse.manifest.digest, forward.manifest.digest);
    expect(second.toJson(), first.toJson());
    expect(second.digest, first.digest);
  });

  test('rejects stale Catalog and Scenario Lab manifest digests', () {
    final fixture = _fixture();

    expect(
      () => planner.plan(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: ScenarioId('ready'),
        scriptId: ScenarioScriptId('exercise-ready'),
        expectedCatalogDigest: Digest.semantic('stale-catalog'),
        expectedScenarioLabManifestDigest: fixture.manifest.digest,
      ),
      _throwsPlanningIssue('expected Catalog digest'),
    );
    expect(
      () => planner.plan(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: ScenarioId('ready'),
        scriptId: ScenarioScriptId('exercise-ready'),
        expectedCatalogDigest: fixture.catalog.digest,
        expectedScenarioLabManifestDigest: Digest.semantic('stale-lab'),
      ),
      _throwsPlanningIssue('expected Scenario Lab manifest digest'),
    );
  });

  test('rejects mismatched manifest and Catalog parents', () {
    final fixture = _fixture();
    final otherCatalog = _catalog(targetId: 'different-target');

    expect(
      () => planner.plan(
        catalog: otherCatalog,
        manifest: fixture.manifest,
        scenarioId: ScenarioId('ready'),
        scriptId: ScenarioScriptId('exercise-ready'),
        expectedCatalogDigest: otherCatalog.digest,
        expectedScenarioLabManifestDigest: fixture.manifest.digest,
      ),
      _throwsPlanningIssue('does not belong to the Catalog'),
    );
  });

  test('rejects unknown Scenario, missing plan and missing script', () {
    final fixture = _fixture();

    expect(
      () =>
          _plan(planner, fixture, ScenarioId('not-authored'), 'exercise-ready'),
      _throwsPlanningIssue('unknown Scenario not-authored'),
    );
    expect(
      () => _plan(planner, fixture, ScenarioId('other'), 'exercise-ready'),
      _throwsPlanningIssue('missing or ambiguous Lab plan for other'),
    );
    expect(
      () => _plan(planner, fixture, ScenarioId('ready'), 'missing-script'),
      _throwsPlanningIssue('missing or ambiguous Lab script missing-script'),
    );
  });

  test('rejects a script selected across Scenario plans', () {
    final fixture = _fixture(includeOtherPlan: true);

    expect(
      () => _plan(planner, fixture, ScenarioId('other'), 'exercise-ready'),
      _throwsPlanningIssue('crosses Scenario other'),
    );
  });

  test('a missing initial binding is rejected before planning', () {
    final catalogWithoutBinding = _catalog(includeReadyBinding: false);

    expect(
      () => _manifest(catalogWithoutBinding),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('invalid execution binding step'),
        ),
      ),
    );
  });
}

ScenarioLabExecutionPlan _plan(
  ScenarioLabExecutionPlanner planner,
  _Fixture fixture,
  ScenarioId scenarioId,
  String scriptId,
) => planner.plan(
  catalog: fixture.catalog,
  manifest: fixture.manifest,
  scenarioId: scenarioId,
  scriptId: ScenarioScriptId(scriptId),
  expectedCatalogDigest: fixture.catalog.digest,
  expectedScenarioLabManifestDigest: fixture.manifest.digest,
);

Matcher _throwsPlanningIssue(String fragment) => throwsA(
  isA<ScenarioLabPlanningException>().having(
    (error) => error.issues.join('\n'),
    'issues',
    contains(fragment),
  ),
);

final class _Fixture {
  const _Fixture(this.catalog, this.manifest);

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
}

_Fixture _fixture({
  bool bindingOnly = false,
  bool includeOtherPlan = false,
  bool reverseRegistries = false,
}) {
  final catalog = _catalog(reverseRegistries: reverseRegistries);
  return _Fixture(
    catalog,
    _manifest(
      catalog,
      bindingOnly: bindingOnly,
      includeOtherPlan: includeOtherPlan,
      reverseRegistries: reverseRegistries,
    ),
  );
}

CatalogManifest _catalog({
  bool includeReadyBinding = true,
  bool reverseRegistries = false,
  String targetId = 'browser',
}) {
  final applicationId = ApplicationId('sample');
  final scenarios = <Scenario>[
    Scenario(
      id: ScenarioId('ready'),
      applicationId: applicationId,
      title: 'Ready',
    ),
    Scenario(
      id: ScenarioId('other'),
      applicationId: applicationId,
      title: 'Other',
    ),
  ];
  final bindings = <ScenarioExecutionBinding>[
    if (includeReadyBinding)
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: targetId,
        launchProfileId: 'sample-web',
      ),
    ScenarioExecutionBinding(
      id: ScenarioExecutionBindingId('other-web'),
      scenarioId: ScenarioId('other'),
      targetId: targetId,
      launchProfileId: 'sample-web',
    ),
  ];
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
    ),
    layout: ConsumerLayout.standard,
    workspace: Workspace(
      id: WorkspaceId('workspace'),
      displayName: 'Workspace',
    ),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: WorkspaceId('workspace'),
        displayName: 'Sample',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: reverseRegistries ? scenarios.reversed.toList() : scenarios,
    transitions: const <Transition>[],
    executionBindings: reverseRegistries
        ? bindings.reversed.toList()
        : bindings,
  );
}

ScenarioLabManifest _manifest(
  CatalogManifest catalog, {
  bool bindingOnly = false,
  bool includeOtherPlan = false,
  bool reverseRegistries = false,
}) {
  final readyScript = ScenarioScriptDefinition(
    id: ScenarioScriptId(bindingOnly ? 'open-ready' : 'exercise-ready'),
    scenarioId: ScenarioId('ready'),
    displayName: bindingOnly ? 'Open ready' : 'Exercise ready',
    timeoutMs: 30000,
    timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
    cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
    steps: <ScenarioScriptStep>[
      ExecutionBindingScenarioScriptStep(
        id: 'prepare',
        bindingId: ScenarioExecutionBindingId('ready-web'),
        timeoutMs: 10000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
      ),
      if (!bindingOnly)
        OperationScenarioScriptStep(
          id: 'enable',
          operationId: ScenarioLabOperationId('enable-ready'),
          timeoutMs: 2000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        ),
      if (!bindingOnly)
        OperationScenarioScriptStep(
          id: 'restore',
          operationId: ScenarioLabOperationId('reset-ready'),
          timeoutMs: 2000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        ),
    ],
  );
  final otherScript = ScenarioScriptDefinition(
    id: ScenarioScriptId('open-other'),
    scenarioId: ScenarioId('other'),
    displayName: 'Open other',
    timeoutMs: 10000,
    timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
    cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
    steps: <ScenarioScriptStep>[
      ExecutionBindingScenarioScriptStep(
        id: 'prepare-other',
        bindingId: ScenarioExecutionBindingId('other-web'),
        timeoutMs: 10000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
      ),
    ],
  );

  final operations = bindingOnly
      ? <ScenarioLabOperationDefinition>[]
      : <ScenarioLabOperationDefinition>[
          AssignControlOperationDefinition(
            id: ScenarioLabOperationId('enable-ready'),
            scenarioId: ScenarioId('ready'),
            controlId: ScenarioControlId('enabled'),
            value: const BooleanScenarioControlValue(true),
          ),
          ResetControlOperationDefinition(
            id: ScenarioLabOperationId('reset-ready'),
            scenarioId: ScenarioId('ready'),
            controlId: ScenarioControlId('enabled'),
          ),
        ];
  final criteria = bindingOnly
      ? <AutomatedAcceptanceCriterion>[]
      : <AutomatedAcceptanceCriterion>[
          ScriptSucceededAcceptanceCriterion(
            id: AutomatedAcceptanceCriterionId('script-succeeds'),
            scenarioId: ScenarioId('ready'),
            displayName: 'Script succeeds',
            scriptId: readyScript.id,
          ),
          ControlEqualsAcceptanceCriterion(
            id: AutomatedAcceptanceCriterionId('control-restored'),
            scenarioId: ScenarioId('ready'),
            displayName: 'Control is restored',
            controlId: ScenarioControlId('enabled'),
            expectedValue: const BooleanScenarioControlValue(false),
          ),
        ];
  final plans = <ScenarioLabPlan>[
    ScenarioLabPlan(
      scenarioId: ScenarioId('ready'),
      executionBindingIds: <ScenarioExecutionBindingId>[
        ScenarioExecutionBindingId('ready-web'),
      ],
      controlIds: bindingOnly
          ? const <ScenarioControlId>[]
          : <ScenarioControlId>[ScenarioControlId('enabled')],
      operationIds: bindingOnly
          ? const <ScenarioLabOperationId>[]
          : <ScenarioLabOperationId>[
              ScenarioLabOperationId('enable-ready'),
              ScenarioLabOperationId('reset-ready'),
            ],
      scriptIds: <ScenarioScriptId>[readyScript.id],
      automatedAcceptanceCriterionIds: bindingOnly
          ? const <AutomatedAcceptanceCriterionId>[]
          : <AutomatedAcceptanceCriterionId>[
              AutomatedAcceptanceCriterionId('script-succeeds'),
              AutomatedAcceptanceCriterionId('control-restored'),
            ],
      requiredEvidenceIds: const <RequiredEvidenceId>[],
      comparisonBindingIds: const <ScenarioComparisonBindingId>[],
      humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
      supplementalArtifactIds: const <SupplementalArtifactId>[],
    ),
    if (includeOtherPlan)
      ScenarioLabPlan(
        scenarioId: ScenarioId('other'),
        executionBindingIds: <ScenarioExecutionBindingId>[
          ScenarioExecutionBindingId('other-web'),
        ],
        controlIds: const <ScenarioControlId>[],
        operationIds: const <ScenarioLabOperationId>[],
        scriptIds: <ScenarioScriptId>[otherScript.id],
        automatedAcceptanceCriterionIds:
            const <AutomatedAcceptanceCriterionId>[],
        requiredEvidenceIds: const <RequiredEvidenceId>[],
        comparisonBindingIds: const <ScenarioComparisonBindingId>[],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: const <SupplementalArtifactId>[],
      ),
  ];
  final scripts = <ScenarioScriptDefinition>[
    readyScript,
    if (includeOtherPlan) otherScript,
  ];

  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: bindingOnly
        ? const <CapabilityDescriptor>[]
        : <CapabilityDescriptor>[
            CapabilityDescriptor(
              id: 'sample.toggle',
              version: 1,
              operations: <String>{'read', 'write', 'reset'},
            ),
          ],
    controls: bindingOnly
        ? const <ScenarioControlDefinition>[]
        : <ScenarioControlDefinition>[
            ScenarioControlDefinition(
              id: ScenarioControlId('enabled'),
              scenarioId: ScenarioId('ready'),
              displayName: 'Enabled',
              capability: AppAdapterCapabilityReference(
                id: AppAdapterCapabilityId('sample.toggle'),
                version: 1,
              ),
              readOperationId: CapabilityOperationId('read'),
              writeOperationId: CapabilityOperationId('write'),
              resetOperationId: CapabilityOperationId('reset'),
              domain: BooleanScenarioControlDomain(defaultValue: false),
            ),
          ],
    operations: reverseRegistries ? operations.reversed.toList() : operations,
    scripts: reverseRegistries ? scripts.reversed.toList() : scripts,
    automatedAcceptanceCriteria: reverseRegistries
        ? criteria.reversed.toList()
        : criteria,
    requiredEvidence: const <RequiredEvidenceDefinition>[],
    comparisonBindings: const <ScenarioComparisonBinding>[],
    visualComparisonPolicies: const <VisualComparisonPolicy>[],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: const <SupplementalArtifactReference>[],
    plans: reverseRegistries ? plans.reversed.toList() : plans,
  );
}
