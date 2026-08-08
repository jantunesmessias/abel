import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition, text;
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/lab/scenario_lab_projection.dart';

final class ScenarioLabPanel extends StatelessComponent {
  const ScenarioLabPanel({
    required this.catalog,
    required this.manifest,
    required this.scenarioId,
    required this.scriptId,
    this.runSnapshot,
    this.runResult,
    this.qualitySnapshot,
    super.key,
  });

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;

  @override
  Component build(BuildContext context) {
    final projection = const ScenarioLabResolver().resolve(
      catalog: catalog,
      manifest: manifest,
      scenarioId: scenarioId,
      scriptId: scriptId,
      runSnapshot: runSnapshot,
      runResult: runResult,
      qualitySnapshot: qualitySnapshot,
    );
    final snapshot = projection.runSnapshot;
    return section(
      classes: 'scenario-lab-panel',
      attributes: <String, String>{
        'aria-label': 'Scenario Lab: ${projection.scenario.title}',
        'data-lab-scenario-id': projection.scenario.id.value,
        'data-lab-script-id': projection.script.id.value,
        'data-lab-run-state': projection.presentationState.name,
        'data-lab-manifest-digest': manifest.digest.value,
        if (snapshot != null) 'data-lab-run-id': snapshot.runId.value,
        if (runResult != null)
          'data-lab-result-digest': runResult!.digest.value,
      },
      <Component>[
        header(<Component>[
          p(classes: 'scenario-lab-panel__eyebrow', <Component>[
            _text('SCENARIO LAB'),
          ]),
          h2(<Component>[_text(projection.scenario.title)]),
          p(<Component>[_text(projection.script.displayName)]),
        ]),
        div(
          classes: 'scenario-lab-panel__state',
          attributes: <String, String>{
            'role': 'status',
            'aria-live': 'polite',
            'data-lab-state': projection.presentationState.name,
          },
          <Component>[
            strong(<Component>[
              _text(_runStateLabel(projection.presentationState)),
            ]),
            _text(
              snapshot == null
                  ? ' Nenhuma execução foi publicada pelo Host.'
                  : ' Observação ${snapshot.sequence} em ${snapshot.observedAt.toIso8601String()}.',
            ),
          ],
        ),
        dl(classes: 'scenario-lab-panel__metadata', <Component>[
          dt(<Component>[_text('Scenario ID')]),
          dd(<Component>[_text(projection.scenario.id.value)]),
          dt(<Component>[_text('Script ID')]),
          dd(<Component>[_text(projection.script.id.value)]),
          dt(<Component>[_text('Timeout total')]),
          dd(<Component>[_text('${projection.script.timeoutMs} ms')]),
          dt(<Component>[_text('Timeout outcome')]),
          dd(<Component>[_text(projection.script.timeoutOutcome.name)]),
          dt(<Component>[_text('Cancelamento')]),
          dd(<Component>[_text(projection.script.cancellationPolicy.name)]),
          dt(<Component>[_text('Verificação automatizada')]),
          dd(
            attributes: <String, String>{
              'data-lab-verification-state':
                  runResult?.verificationState.name ?? 'notAvailable',
            },
            <Component>[
              _text(
                runResult?.verificationState.name ??
                    'Não disponível sem resultado terminal',
              ),
            ],
          ),
        ]),
        _steps(projection.steps),
        _controls(projection.controls),
        _requiredEvidence(projection.requiredEvidence),
        _acceptance(projection.automatedAcceptance),
      ],
    );
  }
}

Component _steps(List<ScenarioLabStepProjection> steps) => section(
  attributes: const <String, String>{'aria-label': 'Steps declarados'},
  <Component>[
    h3(<Component>[_text('Steps')]),
    ol(<Component>[
      for (final step in steps)
        li(
          attributes: <String, String>{
            'data-lab-step-id': step.definition.id,
            'data-lab-step-kind': step.definition.kind.name,
            'data-lab-step-state': step.execution?.state.name ?? 'notReported',
          },
          <Component>[
            strong(<Component>[_text(step.definition.id)]),
            _text(' · ${_stepTarget(step)}'),
            _text(
              ' · ${step.definition.timeoutMs} ms · '
              '${step.definition.timeoutOutcome.name}',
            ),
            span(
              attributes: <String, String>{
                'aria-label':
                    'Estado do step ${step.definition.id}: ${step.execution?.state.name ?? 'não reportado'}',
              },
              <Component>[
                _text(' · ${step.execution?.state.name ?? 'não reportado'}'),
              ],
            ),
          ],
        ),
    ]),
  ],
);

Component _controls(List<ScenarioLabControlProjection> controls) => section(
  attributes: const <String, String>{'aria-label': 'Controls declarados'},
  <Component>[
    h3(<Component>[_text('Controls')]),
    if (controls.isEmpty)
      p(
        attributes: const <String, String>{
          'data-lab-controls-state': 'notDeclared',
        },
        <Component>[_text('Este plano não declara controls.')],
      )
    else
      ul(<Component>[
        for (final control in controls)
          li(
            attributes: <String, String>{
              'data-lab-control-id': control.definition.id.value,
              'data-lab-control-kind': control.definition.domain.kind.name,
              'data-lab-control-result':
                  control.result?.source.name ?? 'notReported',
            },
            <Component>[
              strong(<Component>[_text(control.definition.displayName)]),
              _text(' · ${control.definition.id.value}'),
              _text(
                ' · capability ${control.definition.capability.key} · '
                '${_domainLabel(control.definition.domain)}',
              ),
              _text(
                control.result == null
                    ? ' · valor não reportado'
                    : ' · ${control.result!.source.name}: ${_valueLabel(control.result!.value)}',
              ),
            ],
          ),
      ]),
  ],
);

Component _requiredEvidence(
  List<ScenarioLabRequiredEvidenceProjection> evidence,
) => section(
  attributes: const <String, String>{'aria-label': 'Required Evidence'},
  <Component>[
    h3(<Component>[_text('Required Evidence')]),
    if (evidence.isEmpty)
      p(
        attributes: const <String, String>{
          'data-lab-evidence-state': 'notDeclared',
        },
        <Component>[_text('Este plano não declara Required Evidence.')],
      )
    else
      ul(<Component>[
        for (final item in evidence)
          li(
            attributes: <String, String>{
              'data-lab-evidence-id': item.definition.id.value,
              'data-lab-evidence-provider': item.definition.providerId.value,
              'data-lab-evidence-fidelity': item.definition.fidelity.name,
              'data-lab-evidence-variant': item.definition.variantId.value,
              'data-lab-evidence-state':
                  item.result?.state.name ?? 'notReported',
              'data-lab-evidence-freshness':
                  item.result?.freshness.name ?? 'notReported',
              'data-lab-evidence-verification':
                  item.verification?.verificationState.name ?? 'notAvailable',
            },
            <Component>[
              strong(<Component>[_text(item.definition.id.value)]),
              _text(
                ' · provider ${item.definition.providerId.value} · '
                '${item.definition.fidelity.name} · '
                'variant ${item.definition.variantId.value}',
              ),
              _text(
                item.result == null
                    ? ' · resultado não reportado'
                    : ' · ${item.result!.state.name} / ${item.result!.freshness.name}',
              ),
            ],
          ),
      ]),
  ],
);

Component _acceptance(
  List<ScenarioLabAcceptanceProjection> acceptance,
) => section(
  attributes: const <String, String>{'aria-label': 'Critérios automatizados'},
  <Component>[
    h3(<Component>[_text('Critérios automatizados')]),
    if (acceptance.isEmpty)
      p(
        attributes: const <String, String>{
          'data-lab-acceptance-state': 'notDeclared',
        },
        <Component>[_text('Este plano não declara critérios automáticos.')],
      )
    else
      ul(<Component>[
        for (final item in acceptance)
          li(
            attributes: <String, String>{
              'data-lab-acceptance-id': item.definition.id.value,
              'data-lab-acceptance-kind': item.definition.kind.name,
              'data-lab-acceptance-state':
                  item.result?.verificationState.name ?? 'notReported',
            },
            <Component>[
              strong(<Component>[_text(item.definition.displayName)]),
              _text(
                ' · ${item.result?.verificationState.name ?? 'não reportado'}',
              ),
            ],
          ),
      ]),
  ],
);

String _stepTarget(ScenarioLabStepProjection step) {
  final operation = step.operation;
  if (operation != null) {
    return 'operation ${operation.id.value} (${operation.kind.name})';
  }
  final binding = step.executionBinding!;
  return 'execution binding ${binding.id.value} · target ${binding.targetId}';
}

String _domainLabel(ScenarioControlDomain domain) => switch (domain) {
  BooleanScenarioControlDomain(:final defaultValue) =>
    'boolean · default ${defaultValue.value}',
  ChoiceScenarioControlDomain(:final defaultValue, :final choices) =>
    'choice · default ${defaultValue.value.value} · '
        '${choices.map((item) => item.id.value).join(', ')}',
  IntegerRangeScenarioControlDomain(
    :final defaultValue,
    :final minimum,
    :final maximum,
    :final step,
  ) =>
    'integerRange · default ${defaultValue.value} · '
        '$minimum..$maximum step $step',
};

String _valueLabel(ScenarioControlValue value) => switch (value) {
  BooleanScenarioControlValue(:final value) => '$value',
  ChoiceScenarioControlValue(:final value) => value.value,
  IntegerScenarioControlValue(:final value) => '$value',
};

String _runStateLabel(ScenarioLabPresentationState state) => switch (state) {
  ScenarioLabPresentationState.notStarted => 'Não iniciado',
  ScenarioLabPresentationState.queued => 'Na fila',
  ScenarioLabPresentationState.starting => 'Iniciando',
  ScenarioLabPresentationState.running => 'Executando',
  ScenarioLabPresentationState.cancelling => 'Cancelando',
  ScenarioLabPresentationState.succeeded => 'Concluído',
  ScenarioLabPresentationState.failed => 'Falhou',
  ScenarioLabPresentationState.cancelled => 'Cancelado',
};

Component _text(String value) => Component.text(value);
