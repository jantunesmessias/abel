import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/lab/scenario_lab_panel.dart';
import 'package:studio/src/quality/scenario_quality_decision_controls.dart';
import 'package:studio_ui/studio_ui.dart';

final class ScenarioLabRoutePage extends StatelessComponent {
  const ScenarioLabRoutePage({
    required this.enabled,
    required this.qualityEnabled,
    required this.catalog,
    required this.manifest,
    required this.hasContentGeneration,
    this.scenarioId,
    this.scriptId,
    this.runSnapshot,
    this.runResult,
    this.qualitySnapshot,
    this.selectedRunId,
    this.runControls,
    super.key,
  });

  final bool enabled;
  final bool qualityEnabled;
  final CatalogManifest catalog;
  final ScenarioLabManifest? manifest;
  final bool hasContentGeneration;
  final String? scenarioId;
  final String? scriptId;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
  final ScenarioLabRunId? selectedRunId;
  final Component? runControls;

  @override
  Component build(BuildContext context) => _ScenarioLabSurfacePage(
    surface: _ScenarioSurface.lab,
    enabled: enabled,
    counterpartEnabled: qualityEnabled,
    catalog: catalog,
    manifest: manifest,
    hasContentGeneration: hasContentGeneration,
    scenarioId: scenarioId,
    scriptId: scriptId,
    runSnapshot: runSnapshot,
    runResult: runResult,
    qualitySnapshot: qualitySnapshot,
    selectedRunId: selectedRunId,
    runControls: runControls,
    qualityRpcMethods: const <String>{},
    qualityClient: null,
    qualityResourceClient: null,
    currentContentSetDigest: null,
  );
}

final class ScenarioQualityRoutePage extends StatelessComponent {
  const ScenarioQualityRoutePage({
    required this.enabled,
    required this.labEnabled,
    required this.catalog,
    required this.manifest,
    required this.hasContentGeneration,
    this.scenarioId,
    this.scriptId,
    this.runSnapshot,
    this.runResult,
    this.qualitySnapshot,
    this.currentContentSetDigest,
    this.selectedRunId,
    this.runControls,
    this.qualityRpcMethods = const <String>{},
    this.qualityClient,
    this.qualityResourceClient,
    super.key,
  });

  final bool enabled;
  final bool labEnabled;
  final CatalogManifest catalog;
  final ScenarioLabManifest? manifest;
  final bool hasContentGeneration;
  final String? scenarioId;
  final String? scriptId;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
  final Digest? currentContentSetDigest;
  final ScenarioLabRunId? selectedRunId;
  final Component? runControls;
  final Set<String> qualityRpcMethods;
  final StudioHostScenarioQualityClient? qualityClient;
  final StudioHostScenarioQualityResourceClient? qualityResourceClient;

  @override
  Component build(BuildContext context) => _ScenarioLabSurfacePage(
    surface: _ScenarioSurface.quality,
    enabled: enabled,
    counterpartEnabled: labEnabled,
    catalog: catalog,
    manifest: manifest,
    hasContentGeneration: hasContentGeneration,
    scenarioId: scenarioId,
    scriptId: scriptId,
    runSnapshot: runSnapshot,
    runResult: runResult,
    qualitySnapshot: qualitySnapshot,
    selectedRunId: selectedRunId,
    runControls: runControls,
    qualityRpcMethods: qualityRpcMethods,
    qualityClient: qualityClient,
    qualityResourceClient: qualityResourceClient,
    currentContentSetDigest: currentContentSetDigest,
  );
}

enum _ScenarioSurface { lab, quality }

final class _ScenarioLabSurfacePage extends StatelessComponent {
  const _ScenarioLabSurfacePage({
    required this.surface,
    required this.enabled,
    required this.counterpartEnabled,
    required this.catalog,
    required this.manifest,
    required this.hasContentGeneration,
    required this.scenarioId,
    required this.scriptId,
    required this.runSnapshot,
    required this.runResult,
    required this.qualitySnapshot,
    required this.selectedRunId,
    required this.runControls,
    required this.qualityRpcMethods,
    required this.qualityClient,
    required this.qualityResourceClient,
    required this.currentContentSetDigest,
  });

  final _ScenarioSurface surface;
  final bool enabled;
  final bool counterpartEnabled;
  final CatalogManifest catalog;
  final ScenarioLabManifest? manifest;
  final bool hasContentGeneration;
  final String? scenarioId;
  final String? scriptId;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
  final ScenarioLabRunId? selectedRunId;
  final Component? runControls;
  final Set<String> qualityRpcMethods;
  final StudioHostScenarioQualityClient? qualityClient;
  final StudioHostScenarioQualityResourceClient? qualityResourceClient;
  final Digest? currentContentSetDigest;

  String get _prefix => surface == _ScenarioSurface.lab ? 'lab' : 'quality';

  String get _title =>
      surface == _ScenarioSurface.lab ? 'Scenario Lab' : 'Quality';

  bool get _hasHistoricalContent =>
      surface == _ScenarioSurface.quality &&
      runSnapshot != null &&
      currentContentSetDigest != null &&
      runSnapshot!.contentSetDigest != currentContentSetDigest;

  @override
  Component build(BuildContext context) {
    if (!enabled) {
      return _boundary(
        state: 'disabled',
        child: StudioEmptyState(
          title: '$_title não habilitado',
          message: 'O ResolvedKitPlan atual não publicou studio.$_prefix.',
          tone: PresentationTone.warning,
        ),
      );
    }
    final currentManifest = manifest;
    if (currentManifest == null) {
      return _boundary(
        state: 'manifestAbsent',
        child: StudioEmptyState(
          title: '$_title indisponível',
          message: _manifestAbsentMessage(),
          tone: PresentationTone.warning,
        ),
      );
    }
    if (!hasContentGeneration ||
        currentManifest.catalogDigest != catalog.digest) {
      return _boundary(
        state: 'fencingMismatch',
        child: const StudioEmptyState(
          title: 'Geração Scenario Lab inconsistente',
          message:
              'O Studio recusou um ScenarioLabManifest fora do content-set e Catalog atuais.',
          tone: PresentationTone.critical,
        ),
      );
    }
    final requestedScenarioId = scenarioId;
    final requestedScriptId = scriptId;
    if (requestedScenarioId == null && requestedScriptId == null) {
      return _index(currentManifest);
    }
    if (requestedScenarioId == null || requestedScriptId == null) {
      return _notFound(
        requestedScenarioId ?? 'ausente',
        requestedScriptId ?? 'ausente',
      );
    }
    final selection = _selection(
      currentManifest,
      requestedScenarioId,
      requestedScriptId,
    );
    if (selection == null) {
      return _notFound(requestedScenarioId, requestedScriptId);
    }
    return _detail(currentManifest, selection);
  }

  Component _boundary({required String state, required Component child}) =>
      section(
        classes: 'scenario-surface-boundary page-stack',
        attributes: <String, String>{
          'data-$_prefix-route-state': state,
          'aria-label': 'Estado de $_title',
        },
        <Component>[child],
      );

  String _manifestAbsentMessage() {
    if (hasContentGeneration) {
      return 'A geração content-set atual não publicou '
          'ScenarioLabManifest.';
    }
    return 'O Host não publicou um content-set atômico com '
        'ScenarioLabManifest.';
  }

  Component _index(ScenarioLabManifest manifest) {
    final scenariosById = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final scriptsById = <ScenarioScriptId, ScenarioScriptDefinition>{
      for (final script in manifest.scripts) script.id: script,
    };
    return section(
      classes: 'scenario-surface-index page-stack',
      attributes: <String, String>{
        'data-$_prefix-route-state': 'index',
        'data-scenario-lab-manifest-digest': manifest.digest.value,
        'aria-label': 'Índice de $_title',
      },
      <Component>[
        StudioPageHeader(
          eyebrow: surface == _ScenarioSurface.lab
              ? 'PLANO DECLARATIVO'
              : 'RESULTADOS TIPADOS',
          title: _title,
          description: surface == _ScenarioSurface.lab
              ? 'Selecione exatamente um Scenario e um script publicados no content-set.'
              : 'Selecione um Scenario e script para inspecionar Quality sem promover decisão humana.',
        ),
        StudioPanel(
          title: 'Scenarios com plano',
          description:
              '${manifest.plans.length} planos · ${manifest.scripts.length} scripts',
          children: <Component>[
            if (manifest.plans.isEmpty)
              const StudioEmptyState(
                title: 'Nenhum plano Lab',
                message:
                    'O ScenarioLabManifest atual não contém planos selecionáveis.',
              )
            else
              ol(
                classes: 'scenario-surface-list',
                attributes: <String, String>{
                  'aria-label': 'Deep links de $_title',
                },
                <Component>[
                  for (final plan in manifest.plans)
                    if (scenariosById[plan.scenarioId] case final scenario?)
                      for (final scriptId in plan.scriptIds)
                        if (scriptsById[scriptId] case final script?)
                          li(
                            attributes: <String, String>{
                              'data-$_prefix-scenario-id': scenario.id.value,
                              'data-$_prefix-script-id': script.id.value,
                            },
                            <Component>[
                              Link(
                                to: _path(surface, scenario.id, script.id),
                                classes: 'scenario-surface-list__link',
                                attributes: <String, String>{
                                  'data-$_prefix-deep-link': 'true',
                                  'aria-label':
                                      'Abrir $_title para ${scenario.title}, script ${script.displayName}',
                                },
                                children: <Component>[
                                  strong(<Component>[
                                    Component.text(scenario.title),
                                  ]),
                                  span(<Component>[
                                    Component.text(script.displayName),
                                  ]),
                                  small(<Component>[
                                    Component.text(
                                      '${scenario.id.value} · ${script.id.value}',
                                    ),
                                  ]),
                                ],
                              ),
                              if (counterpartEnabled)
                                Link(
                                  to: _path(
                                    _counterpart(surface),
                                    scenario.id,
                                    script.id,
                                    runId: selectedRunId,
                                  ),
                                  classes: 'scenario-surface-list__cross-link',
                                  attributes: <String, String>{
                                    'data-scenario-cross-surface':
                                        '${surface.name}-to-${_counterpart(surface).name}',
                                  },
                                  child: Component.text(
                                    surface == _ScenarioSurface.lab
                                        ? 'Abrir Quality'
                                        : 'Abrir Lab',
                                  ),
                                ),
                            ],
                          ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Component _detail(
    ScenarioLabManifest manifest,
    _ScenarioSelection selection,
  ) => section(
    classes: 'scenario-surface-detail page-stack',
    attributes: <String, String>{
      'data-$_prefix-route-state': 'ready',
      'data-$_prefix-scenario-id': selection.scenario.id.value,
      'data-$_prefix-script-id': selection.script.id.value,
      'data-scenario-lab-manifest-digest': manifest.digest.value,
      if (selectedRunId != null)
        'data-$_prefix-selected-run-id': selectedRunId!.value,
      'aria-label': '$_title selecionado',
    },
    <Component>[
      StudioPageHeader(
        eyebrow: surface == _ScenarioSurface.lab
            ? 'SCENARIO + SCRIPT'
            : 'QUALITY READ-ONLY',
        title: _title,
        description:
            '${selection.scenario.title} · ${selection.script.displayName}',
        actions: <Component>[
          Link(
            to: '/$_prefix',
            classes: 'studio-ui-button studio-ui-button--secondary',
            child: Component.text('Todos os planos'),
          ),
          if (counterpartEnabled)
            Link(
              to: _path(
                _counterpart(surface),
                selection.scenario.id,
                selection.script.id,
                runId: selectedRunId,
              ),
              classes: 'studio-ui-button studio-ui-button--quiet',
              attributes: <String, String>{
                'data-scenario-cross-surface':
                    '${surface.name}-to-${_counterpart(surface).name}',
              },
              child: Component.text(
                surface == _ScenarioSurface.lab ? 'Abrir Quality' : 'Abrir Lab',
              ),
            ),
          if (_hasHistoricalContent && counterpartEnabled)
            Link(
              to: _path(
                _ScenarioSurface.lab,
                selection.scenario.id,
                selection.script.id,
              ),
              classes: 'studio-ui-button studio-ui-button--primary',
              attributes: const <String, String>{
                'data-quality-action': 'recollect',
              },
              child: Component.text('Coletar novamente'),
            ),
        ],
      ),
      ?runControls,
      if (surface == _ScenarioSurface.lab)
        ScenarioLabPanel(
          catalog: catalog,
          manifest: manifest,
          scenarioId: selection.scenario.id,
          scriptId: selection.script.id,
          runSnapshot: runSnapshot,
          runResult: runResult,
          qualitySnapshot: qualitySnapshot,
        )
      else
        ScenarioQualityDecisionExperience(
          catalog: catalog,
          manifest: manifest,
          scenarioId: selection.scenario.id,
          scriptId: selection.script.id,
          runSnapshot: runSnapshot,
          runResult: runResult,
          qualitySnapshot: qualitySnapshot,
          currentContentSetDigest: currentContentSetDigest,
          rpcMethods: qualityRpcMethods,
          qualityClient: qualityClient,
          resourceClient: qualityResourceClient,
        ),
    ],
  );

  Component _notFound(String scenarioId, String scriptId) => _boundary(
    state: 'notFound',
    child: StudioEmptyState(
      title: 'Seleção de $_title não encontrada',
      message:
          'O Scenario $scenarioId não declara exatamente o script $scriptId no ScenarioLabManifest atual.',
      tone: PresentationTone.warning,
      action: Link(
        to: '/$_prefix',
        classes: 'studio-ui-button studio-ui-button--primary',
        child: Component.text('Abrir índice de $_title'),
      ),
    ),
  );

  _ScenarioSelection? _selection(
    ScenarioLabManifest manifest,
    String scenarioId,
    String scriptId,
  ) {
    final scenarios = catalog.scenarios
        .where((item) => item.id.value == scenarioId)
        .toList(growable: false);
    final plans = manifest.plans
        .where((item) => item.scenarioId.value == scenarioId)
        .toList(growable: false);
    final scripts = manifest.scripts
        .where(
          (item) =>
              item.id.value == scriptId && item.scenarioId.value == scenarioId,
        )
        .toList(growable: false);
    if (scenarios.length != 1 || plans.length != 1 || scripts.length != 1) {
      return null;
    }
    final script = scripts.single;
    if (!plans.single.scriptIds.contains(script.id)) return null;
    return _ScenarioSelection(scenario: scenarios.single, script: script);
  }
}

final class _ScenarioSelection {
  const _ScenarioSelection({required this.scenario, required this.script});

  final Scenario scenario;
  final ScenarioScriptDefinition script;
}

_ScenarioSurface _counterpart(_ScenarioSurface surface) =>
    surface == _ScenarioSurface.lab
    ? _ScenarioSurface.quality
    : _ScenarioSurface.lab;

String _path(
  _ScenarioSurface surface,
  ScenarioId scenarioId,
  ScenarioScriptId scriptId, {
  ScenarioLabRunId? runId,
}) => Uri(
  path:
      '/${surface.name}/scenarios/${scenarioId.value}/scripts/${scriptId.value}',
  queryParameters: runId == null
      ? null
      : <String, String>{'runId': runId.value},
).toString();
