import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition, text;
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/quality/scenario_quality_projection.dart';

final class ScenarioQualityPanel extends StatelessComponent {
  const ScenarioQualityPanel({
    required this.catalog,
    required this.manifest,
    required this.scenarioId,
    required this.scriptId,
    this.runSnapshot,
    this.runResult,
    this.qualitySnapshot,
    this.currentContentSetDigest,
    this.decisionControls,
    super.key,
  });

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
  final Digest? currentContentSetDigest;
  final Component? decisionControls;

  @override
  Component build(BuildContext context) {
    final projection = const ScenarioQualityResolver().resolve(
      catalog: catalog,
      manifest: manifest,
      scenarioId: scenarioId,
      scriptId: scriptId,
      runSnapshot: runSnapshot,
      runResult: runResult,
      qualitySnapshot: qualitySnapshot,
      currentContentSetDigest: currentContentSetDigest,
    );
    return section(
      classes: 'scenario-quality-panel',
      attributes: <String, String>{
        'aria-label': 'Quality: ${projection.lab.scenario.title}',
        'data-quality-scenario-id': projection.lab.scenario.id.value,
        'data-quality-script-id': projection.lab.script.id.value,
        'data-quality-states': projection.states
            .map((state) => state.name)
            .join(','),
        'data-quality-verification':
            projection.verificationState?.name ?? 'notAvailable',
        'data-quality-human-decision':
            projection.humanDecisionState?.name ?? 'notAvailable',
        if (runSnapshot != null)
          'data-quality-run-id': runSnapshot!.runId.value,
        if (runResult != null)
          'data-quality-result-digest': runResult!.digest.value,
        if (runSnapshot != null && currentContentSetDigest != null)
          'data-quality-content-currentness':
              runSnapshot!.contentSetDigest == currentContentSetDigest
              ? 'current'
              : 'stale',
      },
      <Component>[
        header(<Component>[
          p(classes: 'scenario-quality-panel__eyebrow', <Component>[
            _text('QUALITY'),
          ]),
          h2(<Component>[_text(projection.lab.scenario.title)]),
          p(<Component>[
            _text(
              'Estados derivados de resultados tipados; artifacts não são '
              'interpretados pelo Studio.',
            ),
          ]),
        ]),
        if (runSnapshot != null &&
            currentContentSetDigest != null &&
            runSnapshot!.contentSetDigest != currentContentSetDigest)
          aside(
            classes: 'scenario-quality-panel__currentness',
            attributes: const <String, String>{
              'role': 'status',
              'data-quality-currentness-notice': 'stale',
            },
            <Component>[
              strong(<Component>[_text('Execução histórica')]),
              p(<Component>[
                _text(
                  'O resultado permanece imutável, mas pertence a uma geração de conteúdo anterior. Recolha Evidence no Lab atual antes de revisar.',
                ),
              ]),
            ],
          ),
        ul(
          classes: 'scenario-quality-panel__states',
          attributes: const <String, String>{
            'aria-label': 'Estados Quality observados',
          },
          <Component>[
            for (final state in projection.states)
              li(
                attributes: <String, String>{'data-quality-state': state.name},
                <Component>[_text(_qualityStateLabel(state))],
              ),
          ],
        ),
        section(
          attributes: <String, String>{
            'aria-label': 'Decisão humana',
            'data-quality-human-decision':
                projection.humanDecisionState?.name ?? 'notAvailable',
          },
          <Component>[
            h3(<Component>[_text('Decisão humana')]),
            p(<Component>[
              _text(
                projection.humanDecisionState == null
                    ? 'Nenhuma projeção de decisão humana foi publicada.'
                    : _humanDecisionLabel(projection.humanDecisionState!),
              ),
            ]),
            p(<Component>[
              _text(
                'Este eixo é independente da verificação automatizada e não '
                'altera os estados Quality acima.',
              ),
            ]),
          ],
        ),
        ?decisionControls,
        _evidence(projection),
        _comparisons(projection),
        _findings(projection.findings),
      ],
    );
  }
}

Component _evidence(ScenarioQualityProjection projection) => section(
  attributes: const <String, String>{
    'aria-label': 'Quality por Required Evidence',
  },
  <Component>[
    h3(<Component>[_text('Required Evidence')]),
    if (projection.lab.requiredEvidence.isEmpty)
      p(
        attributes: const <String, String>{
          'data-quality-evidence-state': 'notDeclared',
        },
        <Component>[_text('O plano não declara Required Evidence.')],
      )
    else
      ul(<Component>[
        for (final evidence in projection.lab.requiredEvidence)
          li(
            attributes: <String, String>{
              'data-quality-evidence-id': evidence.definition.id.value,
              'data-quality-evidence-state':
                  evidence.result?.state.name ?? 'notReported',
              'data-quality-evidence-freshness':
                  evidence.result?.freshness.name ?? 'notReported',
              'data-quality-evidence-verification':
                  evidence.verification?.verificationState.name ??
                  'notAvailable',
            },
            <Component>[
              strong(<Component>[_text(evidence.definition.id.value)]),
              _text(
                evidence.result == null
                    ? ' · resultado não reportado'
                    : ' · ${evidence.result!.state.name} / '
                          '${evidence.result!.freshness.name}',
              ),
              _text(
                ' · verificação '
                '${evidence.verification?.verificationState.name ?? 'não disponível'}',
              ),
            ],
          ),
      ]),
  ],
);

Component _comparisons(ScenarioQualityProjection projection) => section(
  attributes: const <String, String>{'aria-label': 'Comparisons declaradas'},
  <Component>[
    h3(<Component>[_text('Comparisons')]),
    if (projection.lab.comparisons.isEmpty)
      p(
        attributes: const <String, String>{
          'data-quality-comparison-state': 'notDeclared',
        },
        <Component>[_text('O plano não declara comparisons.')],
      )
    else
      ul(<Component>[
        for (final comparison in projection.lab.comparisons)
          li(
            attributes: <String, String>{
              'data-quality-comparison-id': comparison.definition.id.value,
              'data-quality-comparison-state':
                  comparison.result?.verificationState.name ?? 'notReported',
              'data-quality-comparison-kind':
                  comparison.result?.resultKind.name ?? 'notReported',
              if (_changedUnits(comparison.result) case final changed?)
                'data-quality-changed-units': '$changed',
            },
            <Component>[
              strong(<Component>[_text(comparison.definition.id.value)]),
              _text(
                comparison.result == null
                    ? ' · resultado não reportado'
                    : ' · ${comparison.result!.resultKind.name} / '
                          '${comparison.result!.verificationState.name}',
              ),
              if (_changedUnits(comparison.result) case final changed?)
                _text(' · $changed unidades alteradas'),
            ],
          ),
      ]),
  ],
);

Component _findings(List<ScenarioQualityFinding> findings) => section(
  attributes: const <String, String>{
    'aria-label': 'Origem dos estados Quality',
  },
  <Component>[
    h3(<Component>[_text('Origem dos estados')]),
    ul(<Component>[
      for (final finding in findings)
        li(
          attributes: <String, String>{
            'data-quality-finding-state': finding.state.name,
            'data-quality-finding-source': finding.source.name,
            'data-quality-finding-source-id': finding.sourceId,
            'data-quality-finding-detail': finding.detail,
          },
          <Component>[
            _text(
              '${_qualityStateLabel(finding.state)} · '
              '${finding.source.name} ${finding.sourceId} · ${finding.detail}',
            ),
          ],
        ),
    ]),
  ],
);

int? _changedUnits(ScenarioComparisonResult? result) => switch (result) {
  VisualScenarioComparisonResult(:final changedPixels) => changedPixels,
  SemanticScenarioComparisonResult(:final changedNodes) => changedNodes,
  null => null,
};

String _qualityStateLabel(ScenarioQualityState state) => switch (state) {
  ScenarioQualityState.passing => 'Passing',
  ScenarioQualityState.changed => 'Changed',
  ScenarioQualityState.failing => 'Failing',
  ScenarioQualityState.stale => 'Stale',
  ScenarioQualityState.unverified => 'Unverified',
  ScenarioQualityState.missing => 'Missing',
  ScenarioQualityState.unsupported => 'Unsupported',
  ScenarioQualityState.policyDenied => 'Policy denied',
};

String _humanDecisionLabel(HumanDecisionState state) => switch (state) {
  HumanDecisionState.unreviewed => 'Aguardando decisão humana.',
  HumanDecisionState.approved => 'A decisão humana publicada é approved.',
  HumanDecisionState.rejected => 'A decisão humana publicada é rejected.',
  HumanDecisionState.superseded => 'A decisão humana publicada foi superseded.',
};

Component _text(String value) => Component.text(value);
