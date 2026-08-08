import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/controllers/studio_filters_controller.dart';
import 'package:devex_studio/src/controllers/studio_workspace_controller.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:devex_studio/src/host/studio_host_client_factory.dart';
import 'package:devex_studio/src/jaspr/capability_pages.dart';
import 'package:devex_studio/src/jaspr/journey_map_runtime.dart';
import 'package:devex_studio/src/jaspr/verified_artifact_image.dart';
import 'package:devex_studio/src/journey_map/journey_map_view_data.dart';
import 'package:devex_studio/src/journey_map/visual_evidence_presentation.dart';
import 'package:devex_studio/src/model/studio_filters.dart';
import 'package:devex_studio/src/model/workspace_state.dart';
import 'package:devex_studio/src/remote/remote_session_grant_vault.dart';
import 'package:devex_studio/src/studio_composition.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:devex_ux_system/devex_ux_system.dart'
    show DevExSequenceWindowPolicy;
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

final class DevExStudioApp extends StatefulComponent {
  const DevExStudioApp({
    this.clientFactory = createStudioHostClient,
    this.remoteSessions,
    this.reconnectDelay = const Duration(seconds: 2),
    super.key,
  });

  final StudioHostClientFactory clientFactory;
  final RemoteSessionGrantVault? remoteSessions;
  final Duration reconnectDelay;

  @override
  State<DevExStudioApp> createState() => _DevExStudioAppState();
}

final class _DevExStudioAppState extends State<DevExStudioApp> {
  late final StudioWorkspaceController _workspaceController;
  late final StudioFiltersController _filtersController;
  late final StreamSubscription<StudioWorkspaceState> _workspaceSubscription;
  late final StreamSubscription<StudioFilters> _filtersSubscription;
  late final RemoteSessionGrantVault _remoteSessions;

  StudioWorkspaceState _workspace = const StudioWorkspaceState.initial();
  StudioFilters _filters = const StudioFilters();
  String _inspectorTab = 'general';
  bool _showMap = true;
  bool _showAdvancedFilters = false;
  double _mapZoom = 0.75;
  Map<String, Object?>? _collectionOperation;
  _PendingPreviewCollection? _pendingPreviewCollection;
  String? _revealedScenarioId;
  SessionSnapshot? _activeSession;
  Map<String, Object?>? _gatewayStatus;

  @override
  void initState() {
    super.initState();
    _workspaceController = StudioWorkspaceController(
      clientFactory: component.clientFactory,
      reconnectDelay: component.reconnectDelay,
    );
    _filtersController = StudioFiltersController();
    _remoteSessions = component.remoteSessions ?? RemoteSessionGrantVault();
    _workspaceSubscription = _workspaceController.changes.listen((state) {
      if (!mounted) return;
      final lostConnection =
          _workspace.connection.connected && !state.connection.connected;
      setState(() {
        _workspace = state;
        if (lostConnection) {
          _activeSession = null;
          _gatewayStatus = null;
        }
      });
    });
    _filtersSubscription = _filtersController.changes.listen((filters) {
      if (mounted) setState(() => _filters = filters);
    });
    unawaited(_workspaceController.connect());
  }

  @override
  void dispose() {
    unawaited(_workspaceSubscription.cancel());
    unawaited(_filtersSubscription.cancel());
    unawaited(_workspaceController.close());
    unawaited(_filtersController.close());
    _remoteSessions.clear();
    super.dispose();
  }

  @override
  Component build(BuildContext context) => DevExTheme(
    child: Router(
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) => _shell(state, child),
          routes: <RouteBase>[
            Route(
              path: '/',
              title: 'Visão geral · DevExKit Studio',
              builder: (context, state) => _overview(),
            ),
            Route(
              path: '/journeys/:journeyId',
              title: 'Journey · DevExKit Studio',
              builder: (context, state) => _journey(context, state),
            ),
            Route(
              path: '/journeys/:journeyId/scenarios/:scenarioId',
              title: 'Scenario · DevExKit Studio',
              builder: (context, state) => _journey(context, state),
            ),
            Route(
              path: '/target',
              title: 'Target · DevExKit Studio',
              builder: (context, state) => _target(),
            ),
            Route(
              path: '/gateway',
              title: 'Gateway Lab · DevExKit Studio',
              builder: (context, state) => _gateway(),
            ),
            Route(
              path: '/reviews',
              title: 'Review · DevExKit Studio',
              builder: (context, state) => _reviews(),
            ),
            Route(
              path: '/remote/:runId',
              title: 'Remote · DevExKit Studio',
              builder: (context, state) => _remote(state),
            ),
            Route(
              path: '/hosted',
              title: 'Hosted · DevExKit Studio',
              builder: (context, state) => _hosted(),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => DevExEmptyState(
        title: 'Página não encontrada',
        message: 'A rota ${state.location} não pertence ao Kit atual.',
        tone: DevExTone.warning,
        action: const Link(
          to: '/',
          classes: 'dx-button dx-button--primary',
          child: Component.text('Voltar à visão geral'),
        ),
      ),
    ),
  );

  Component _shell(RouteState route, Component child) {
    final routePath = Uri.parse(route.location).path;
    final snapshot = _workspace.snapshot;
    final composition = snapshot == null
        ? null
        : StudioComposition.fromManifest(snapshot.effectiveKitManifest);
    final status = _workspace.connection.connected
        ? ('Host conectado', DevExTone.positive)
        : _workspace.connection.isStale
        ? ('Snapshot desatualizado', DevExTone.warning)
        : _workspace.failureMessage != null
        ? ('Host indisponível', DevExTone.critical)
        : ('Conectando', DevExTone.info);

    return div(classes: 'studio-shell', <Component>[
      aside(classes: 'studio-rail', <Component>[
        Link(
          to: '/',
          classes: 'studio-brand',
          attributes: const <String, String>{'aria-label': 'DevExKit Studio'},
          children: const <Component>[
            span(classes: 'studio-brand__mark', <Component>[
              Component.text('DX'),
            ]),
            span(classes: 'studio-brand__copy', <Component>[
              strong(<Component>[Component.text('DevExKit')]),
              small(<Component>[Component.text('Studio')]),
            ]),
          ],
        ),
        nav(
          classes: 'studio-nav',
          attributes: const <String, String>{
            'aria-label': 'Navegação principal',
          },
          <Component>[
            p(classes: 'studio-nav__label', <Component>[
              const Component.text('Workspace'),
            ]),
            Link(
              to: '/',
              classes:
                  'studio-nav__item${routePath == '/' ? ' is-active' : ''}',
              attributes: <String, String>{
                if (routePath == '/') 'aria-current': 'page',
              },
              children: const <Component>[
                DevExIcon(name: DevExIconName.overview),
                span(classes: 'studio-nav__copy', <Component>[
                  Component.text('Visão geral'),
                ]),
              ],
            ),
            if (snapshot?.catalog.journeys.firstOrNull case final first?)
              Link(
                to: '/journeys/${first.id.value}',
                classes:
                    'studio-nav__item${routePath.startsWith('/journeys/') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/journeys/'))
                    'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.journey),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Journey Map'),
                  ]),
                ],
              ),
            if (composition?.targetEnabled == true)
              Link(
                to: '/target',
                classes:
                    'studio-nav__item${routePath == '/target' ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath == '/target') 'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.target),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Target'),
                  ]),
                ],
              ),
            if (composition?.gatewayEnabled == true)
              Link(
                to: '/gateway',
                classes:
                    'studio-nav__item${routePath == '/gateway' ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath == '/gateway') 'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.gateway),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Gateway Lab'),
                  ]),
                ],
              ),
            if (snapshot?.catalog.reviewGuides.isNotEmpty == true)
              Link(
                to: '/reviews',
                classes:
                    'studio-nav__item${routePath == '/reviews' ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath == '/reviews') 'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.review),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Review'),
                  ]),
                ],
              ),
            if (composition?.remoteSessionEnabled == true)
              Link(
                to: '/remote/new',
                classes:
                    'studio-nav__item${routePath.startsWith('/remote/') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/remote/')) 'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.remote),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Remote'),
                  ]),
                ],
              ),
            if (composition?.hostedEnabled == true)
              Link(
                to: '/hosted',
                classes:
                    'studio-nav__item${routePath == '/hosted' ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath == '/hosted') 'aria-current': 'page',
                },
                children: const <Component>[
                  DevExIcon(name: DevExIconName.hosted),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Hosted'),
                  ]),
                ],
              ),
          ],
        ),
        div(classes: 'studio-rail__footer', <Component>[
          const p(<Component>[Component.text('Renderer')]),
          const strong(<Component>[Component.text('Jaspr · HTML/CSS')]),
        ]),
      ]),
      div(classes: 'studio-workspace', <Component>[
        header(classes: 'studio-topbar', <Component>[
          div(classes: 'studio-topbar__context', <Component>[
            span(<Component>[
              Component.text(
                snapshot?.catalog.workspace.displayName ?? 'Workspace local',
              ),
            ]),
            if (snapshot != null)
              small(<Component>[
                Component.text('revisão ${snapshot.revision}'),
              ]),
          ]),
          div(classes: 'studio-topbar__actions', <Component>[
            DevExStatusPill(label: status.$1, tone: status.$2, live: true),
            DevExButton(
              label: _workspace.connection.connected
                  ? 'Atualizar'
                  : 'Reconectar',
              leadingIcon: DevExIconName.refresh,
              kind: DevExButtonKind.quiet,
              onPressed: _workspace.connection.connected
                  ? () => unawaited(_refreshWorkspace())
                  : () => unawaited(_workspaceController.connect()),
            ),
          ]),
        ]),
        main_(id: 'main-content', classes: 'studio-main', <Component>[
          if (snapshot == null)
            _bootstrapState()
          else if (composition?.shellEnabled != true)
            const DevExEmptyState(
              title: 'Studio não habilitado',
              message: 'O ResolvedKitPlan atual não publicou studio.shell.',
              tone: DevExTone.warning,
            )
          else
            child,
        ]),
      ]),
    ]);
  }

  Component _bootstrapState() {
    final failure = _workspace.failureMessage;
    if (failure != null) {
      return DevExEmptyState(
        title: 'Não foi possível conectar ao DevEx Host',
        message: failure,
        tone: DevExTone.critical,
        live: true,
        action: DevExButton(
          label: 'Reconectar',
          leadingIcon: DevExIconName.refresh,
          onPressed: () => unawaited(_workspaceController.connect()),
        ),
      );
    }
    return const DevExPanel(
      classes: 'studio-bootstrap',
      children: <Component>[DevExProgress(label: 'Conectando ao DevEx Host')],
    );
  }

  Future<void> _refreshWorkspace() async {
    try {
      await _workspaceController.refreshWorkspace();
    } on Object {
      // The controller exposes stale/reconnect state to the live region.
    }
  }

  void _requestPreviewCollection({
    required StudioHostPreviewClient client,
    required ApplicationId applicationId,
    required ScenarioId scenarioId,
    required VariantId? variantId,
  }) {
    setState(() {
      _pendingPreviewCollection = _PendingPreviewCollection(
        client: client,
        applicationId: applicationId,
        scenarioId: scenarioId,
        variantId: variantId,
      );
    });
  }

  Future<void> _confirmPreviewCollection() async {
    final request = _pendingPreviewCollection;
    if (request == null) return;
    setState(() {
      _pendingPreviewCollection = null;
      _collectionOperation = <String, Object?>{
        'state': 'queued',
        'completedItems': 0,
        'totalItems': 1,
      };
    });
    try {
      var operation = await request.client.collectPreview(
        applicationId: request.applicationId.value,
        scenarioId: request.scenarioId.value,
        variantId: request.variantId?.value,
        syntheticDataConfirmed: true,
      );
      if (!mounted) return;
      setState(() => _collectionOperation = operation);
      final deadline = DateTime.now().add(const Duration(minutes: 6));
      while (!_terminalCollectionState(operation['state']) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        final operationId = operation['operationId'];
        if (operationId is! String || operationId.isEmpty) {
          throw const FormatException(
            'O Host retornou uma operação AutoPreview inválida.',
          );
        }
        operation = await request.client.previewStatus(operationId);
        if (!mounted) return;
        setState(() => _collectionOperation = operation);
      }
      if (!_terminalCollectionState(operation['state'])) {
        throw TimeoutException(
          'A coleta AutoPreview não terminou em seis minutos.',
        );
      }
      if (operation['state'] == 'completed' ||
          operation['state'] == 'completedWithFailures') {
        await _refreshWorkspace();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _collectionOperation = <String, Object?>{
          ...?_collectionOperation,
          'state': 'failed',
          'error': '$error',
        };
      });
    }
  }

  Future<void> _cancelPreviewCollection(StudioHostPreviewClient client) async {
    final operationId = _collectionOperation?['operationId'];
    if (operationId is! String || operationId.isEmpty) return;
    try {
      final operation = await client.cancelPreview(operationId);
      if (!mounted) return;
      setState(() => _collectionOperation = operation);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _collectionOperation = <String, Object?>{
          ...?_collectionOperation,
          'state': 'failed',
          'error': 'Não foi possível cancelar a coleta: $error',
        };
      });
    }
  }

  bool _terminalCollectionState(Object? state) =>
      state == 'cancelled' ||
      state == 'completed' ||
      state == 'completedWithFailures' ||
      state == 'failed';

  bool _activeCollectionState(Object? state) =>
      state == 'queued' || state == 'running' || state == 'cancelling';

  String _collectionStateLabel(String state) => switch (state) {
    'queued' => 'Na fila',
    'running' => 'Em execução',
    'cancelling' => 'Cancelando',
    'cancelled' => 'Cancelada',
    'completed' => 'Concluída',
    'completedWithFailures' => 'Concluída parcialmente',
    'failed' => 'Falhou',
    _ => 'Estado desconhecido',
  };

  DevExTone _collectionTone(String state) => switch (state) {
    'completed' => DevExTone.positive,
    'queued' || 'running' => DevExTone.info,
    'cancelling' || 'completedWithFailures' => DevExTone.warning,
    'failed' => DevExTone.critical,
    _ => DevExTone.neutral,
  };

  Component _overview() {
    final snapshot = _workspace.snapshot!;
    final catalog = snapshot.catalog;
    final boundEvidence = snapshot.visualProjections
        .where((item) => item.status != VisualEvidenceStatus.unbound)
        .toList(growable: false);
    final coverage = VisualEvidenceCoverage.forScenarios(
      scenarioIds: catalog.scenarios.map((item) => item.id),
      projections: boundEvidence,
    );
    final healthyModules = snapshot.effectiveKitManifest.modules
        .where((module) => module.health == ModuleHealth.healthy)
        .length;
    final attentionJourney = catalog.journeys.where((journey) {
      final expected = journey.scenarioIds.toSet();
      return boundEvidence
              .where(
                (item) =>
                    item.scenarioId != null &&
                    expected.contains(item.scenarioId) &&
                    item.status == VisualEvidenceStatus.collected &&
                    item.freshness == EvidenceFreshness.fresh,
              )
              .map((item) => item.scenarioId)
              .toSet()
              .length <
          expected.length;
    }).firstOrNull;

    return section(classes: 'overview-page page-stack', <Component>[
      DevExPageHeader(
        eyebrow: 'WORKSPACE AUTORITATIVO',
        title: 'Visão geral',
        description:
            'Acompanhe Journeys, Scenarios, módulos e cobertura visual publicados pelo DevEx Host.',
        actions: <Component>[
          DevExButton(
            label: 'Atualizar workspace',
            leadingIcon: DevExIconName.refresh,
            kind: DevExButtonKind.secondary,
            onPressed: () => unawaited(_refreshWorkspace()),
          ),
        ],
      ),
      div(classes: 'metric-grid', <Component>[
        DevExMetric(
          label: 'Aplicações',
          value: '${catalog.applications.length}',
          detail: 'targets configurados',
        ),
        DevExMetric(
          label: 'Journeys',
          value: '${catalog.journeys.length}',
          detail: '${catalog.scenarios.length} Scenarios documentados',
        ),
        DevExMetric(
          label: 'Módulos no plano',
          value: '${snapshot.effectiveKitManifest.modules.length}',
          detail: '$healthyModules com lifecycle saudável',
          tone: healthyModules == snapshot.effectiveKitManifest.modules.length
              ? DevExTone.positive
              : DevExTone.warning,
        ),
        DevExMetric(
          label: 'Cobertura visual',
          value: '${coverage.currentScenarios}/${coverage.totalScenarios}',
          detail: coverage.isComplete
              ? '${coverage.currentCaptures} capturas atuais'
              : '${coverage.scenariosWithoutCurrentCapture} sem imagem atual',
          tone: coverage.isComplete ? DevExTone.positive : DevExTone.warning,
        ),
      ]),
      if (attentionJourney != null)
        aside(classes: 'coverage-callout', <Component>[
          div(<Component>[
            const strong(<Component>[
              Component.text('Cobertura requer atenção'),
            ]),
            p(<Component>[
              Component.text(
                '${coverage.scenariosWithoutCurrentCapture} Scenarios ainda não possuem Evidence visual atual.',
              ),
            ]),
          ]),
          Link(
            to: '/journeys/${attentionJourney.id.value}',
            classes: 'dx-button dx-button--primary',
            child: const Component.text('Abrir Journey Map'),
          ),
        ]),
      div(classes: 'overview-grid', <Component>[
        DevExPanel(
          title: 'Journeys',
          description: 'Fluxos publicados no CatalogManifest.',
          classes: 'journey-list-panel',
          children: <Component>[
            if (catalog.journeys.isEmpty)
              const DevExEmptyState(
                title: 'Nenhuma Journey',
                message: 'O catálogo atual ainda não publicou fluxos.',
              )
            else
              ol(classes: 'journey-list', <Component>[
                for (final journey in catalog.journeys)
                  li(<Component>[
                    Link(
                      to: '/journeys/${journey.id.value}',
                      classes: 'journey-list__link',
                      children: <Component>[
                        span(classes: 'journey-list__title', <Component>[
                          Component.text(journey.title),
                        ]),
                        small(<Component>[
                          Component.text(
                            '${journey.scenarioIds.length} Scenarios · ${journey.id.value}',
                          ),
                        ]),
                      ],
                    ),
                  ]),
              ]),
          ],
        ),
        DevExPanel(
          title: 'Kit em execução',
          description: 'Módulos efetivos, sem inferir recursos desabilitados.',
          children: <Component>[
            ul(classes: 'module-list', <Component>[
              for (final module in snapshot.effectiveKitManifest.modules)
                li(<Component>[
                  div(<Component>[
                    strong(<Component>[Component.text(module.moduleId.value)]),
                    small(<Component>[
                      Component.text(
                        '${module.effectiveCapabilities.length} capabilities',
                      ),
                    ]),
                  ]),
                  DevExStatusPill(
                    label: module.health.name,
                    tone: _moduleTone(module.health),
                  ),
                ]),
            ]),
          ],
        ),
      ]),
    ]);
  }

  Component _target() {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final hostClient = _workspaceController.client;
    return TargetSessionPage(
      enabled: composition.targetEnabled,
      snapshot: snapshot,
      initialSession: _activeSession,
      gatewayOrigin: _gatewayDataOrigin,
      onSessionChanged: (session) => setState(() {
        _activeSession = session;
        if (session == null || session.state.isTerminal) {
          _gatewayStatus = null;
        }
      }),
      client: hostClient is StudioHostSessionClient
          ? hostClient as StudioHostSessionClient
          : null,
    );
  }

  Component _gateway() {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final hostClient = _workspaceController.client;
    return GatewayLabPage(
      enabled: composition.gatewayEnabled,
      ownerSession: _activeSession,
      initialStatus: _gatewayStatus,
      onStatusChanged: (status) => setState(() => _gatewayStatus = status),
      client: hostClient is StudioHostGatewayClient
          ? hostClient as StudioHostGatewayClient
          : null,
    );
  }

  Uri? get _gatewayDataOrigin {
    final status = _gatewayStatus;
    if (status == null || status['state'] != 'running') return null;
    final raw = status['dataOrigin'];
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.isAbsolute ||
        !const <String>{'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
      return null;
    }
    return uri;
  }

  Component _reviews() => ReviewGuidesPage(snapshot: _workspace.snapshot!);

  Component _remote(RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    return RemoteSessionPage(
      enabled: composition.remoteSessionEnabled,
      runId: route.params['runId'] ?? '',
      grants: _remoteSessions,
    );
  }

  Component _hosted() {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    return CapabilityStatusPage(
      enabled: composition.hostedEnabled,
      title: 'Colaboração hosted',
      contribution: 'studio.hosted',
      description:
          'O Studio local exibe o estado negociado sem incorporar credenciais ou assumir conectividade externa.',
      unavailableMessage:
          'A capability está habilitada; a vinculação ao control plane deve ser fornecida por uma distribuição hosted.',
    );
  }

  Component _journey(BuildContext context, RouteState route) {
    final snapshot = _workspace.snapshot!;
    final catalog = snapshot.catalog;
    final journeyId = route.params['journeyId'] ?? '';
    final journey = catalog.journeys
        .where((item) => item.id.value == journeyId)
        .firstOrNull;
    if (journey == null) {
      return DevExEmptyState(
        title: 'Journey não encontrada',
        message: 'O catálogo não contém a Journey $journeyId.',
        tone: DevExTone.warning,
      );
    }

    final scenariosById = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final variants = snapshot.variantManifest.variants
        .where((item) => item.applicationId == journey.applicationId)
        .toList(growable: false);
    final providerId = _selectedProvider(snapshot, journey.applicationId);
    final requestedVariant = variants
        .where((item) => item.id == _filters.variantId)
        .firstOrNull;
    final selectedVariants = requestedVariant == null
        ? const <ScenarioId, VariantId>{}
        : <ScenarioId, VariantId>{
            for (final id in journey.scenarioIds) id: requestedVariant.id,
          };
    final visuals = providerId == null
        ? const <ScenarioId, JourneyMapNodeViewData>{}
        : const WorkspaceJourneyProjector().project(
            snapshot: snapshot,
            providerId: providerId,
            selectedVariants: selectedVariants,
          );
    final query = _filters.query.toLowerCase();
    final scenarios = journey.scenarioIds
        .map((id) => scenariosById[id])
        .whereType<Scenario>()
        .where((scenario) {
          final visual = visuals[scenario.id];
          return (query.isEmpty ||
                  scenario.id.value.toLowerCase().contains(query) ||
                  scenario.title.toLowerCase().contains(query) ||
                  (scenario.description?.toLowerCase().contains(query) ??
                      false)) &&
              (_filters.status == null || visual?.status == _filters.status) &&
              (_filters.freshness == null ||
                  visual?.freshness == _filters.freshness) &&
              (_filters.fidelity == null ||
                  visual?.fidelity == _filters.fidelity);
        })
        .toList(growable: false);
    final routeScenarioId = route.params['scenarioId'];
    final selectedScenario =
        scenarios
            .where((item) => item.id.value == routeScenarioId)
            .firstOrNull ??
        scenarios.firstOrNull;
    final selectedVisual = selectedScenario == null
        ? null
        : visuals[selectedScenario.id];
    if (selectedScenario != null &&
        _revealedScenarioId != selectedScenario.id.value) {
      _revealedScenarioId = selectedScenario.id.value;
      revealJourneyScenario('scenario-card-${selectedScenario.id.value}');
    }
    final coverage = VisualEvidenceCoverage.forScenarios(
      scenarioIds: journey.scenarioIds,
      projections: visuals.values.map((item) => item.projection),
    );
    final selectedProviderState = snapshot.providers
        .where((item) => item.providerId == providerId)
        .firstOrNull;
    final hostClient = _workspaceController.client;
    final StudioHostPreviewClient? previewClient =
        hostClient is StudioHostPreviewClient
        ? hostClient as StudioHostPreviewClient
        : null;
    final StudioHostResourceClient? resourceClient =
        hostClient is StudioHostResourceClient
        ? hostClient as StudioHostResourceClient
        : null;
    final collectionIsActive = _activeCollectionState(
      _collectionOperation?['state'],
    );
    final canCollect =
        previewClient != null &&
        providerId?.value == 'evidence.auto-preview' &&
        selectedProviderState?.supportsCollection == true &&
        selectedScenario != null &&
        selectedVisual?.projection.capturePolicyId != null &&
        !collectionIsActive;
    final advancedFilterCount = <Object?>[
      _filters.status,
      _filters.freshness,
      _filters.fidelity,
    ].where((item) => item != null).length;

    return section(classes: 'journey-page', <Component>[
      header(classes: 'journey-toolbar', <Component>[
        div(classes: 'journey-toolbar__title', <Component>[
          DevExBreadcrumbs(
            items: <DevExBreadcrumbItem>[
              const DevExBreadcrumbItem(label: 'Visão geral', href: '/'),
              DevExBreadcrumbItem(label: journey.title),
            ],
          ),
          h1(<Component>[Component.text(journey.title)]),
        ]),
        div(classes: 'journey-toolbar__filters', <Component>[
          DevExSearchField(
            id: 'journey-query',
            label: 'Buscar Scenario',
            value: _filters.query,
            placeholder: 'Título ou ID',
            onInput: _filtersController.setQuery,
          ),
          DevExSelect(
            id: 'journey-variant',
            label: 'Variant',
            value: _filters.variantId?.value ?? '',
            options: <DevExSelectOption>[
              const DevExSelectOption(value: '', label: 'Automática'),
              for (final variant in variants)
                DevExSelectOption(
                  value: variant.id.value,
                  label: variant.id.value,
                ),
            ],
            onChange: (value) => _filtersController.selectVariant(
              value.isEmpty ? null : VariantId(value),
            ),
          ),
          DevExSelect(
            id: 'journey-provider',
            label: 'Evidence provider',
            value: providerId?.value ?? '',
            options: <DevExSelectOption>[
              const DevExSelectOption(value: '', label: 'Nenhum'),
              for (final provider in snapshot.providers)
                DevExSelectOption(
                  value: provider.providerId.value,
                  label: provider.displayName,
                ),
            ],
            onChange: (value) => _filtersController.selectProvider(
              value.isEmpty ? null : ModuleId(value),
            ),
          ),
          DevExButton(
            label: advancedFilterCount == 0
                ? 'Filtros'
                : 'Filtros ($advancedFilterCount)',
            leadingIcon: DevExIconName.filters,
            kind: _showAdvancedFilters
                ? DevExButtonKind.secondary
                : DevExButtonKind.quiet,
            attributes: <String, String>{
              'aria-expanded': '$_showAdvancedFilters',
              'aria-controls': 'journey-advanced-filters',
            },
            onPressed: () => setState(() {
              _showAdvancedFilters = !_showAdvancedFilters;
            }),
          ),
          DevExStatusPill(
            label:
                '${coverage.currentScenarios}/${coverage.totalScenarios} com imagem',
            tone: coverage.isComplete ? DevExTone.positive : DevExTone.warning,
          ),
        ]),
        if (_showAdvancedFilters)
          div(
            id: 'journey-advanced-filters',
            classes: 'journey-advanced-filters',
            <Component>[
              DevExSelect(
                id: 'journey-status',
                label: 'Status',
                value: _filters.status?.name ?? '',
                options: <DevExSelectOption>[
                  const DevExSelectOption(value: '', label: 'Todos'),
                  for (final status in VisualEvidenceStatus.values)
                    DevExSelectOption(
                      value: status.name,
                      label: visualEvidenceStatusFilterLabel(status),
                    ),
                ],
                onChange: (value) => _filtersController.selectStatus(
                  VisualEvidenceStatus.values
                      .where((item) => item.name == value)
                      .firstOrNull,
                ),
              ),
              DevExSelect(
                id: 'journey-freshness',
                label: 'Atualidade',
                value: _filters.freshness?.name ?? '',
                options: <DevExSelectOption>[
                  const DevExSelectOption(value: '', label: 'Todas'),
                  for (final freshness in EvidenceFreshness.values)
                    DevExSelectOption(
                      value: freshness.name,
                      label: evidenceFreshnessLabel(freshness),
                    ),
                ],
                onChange: (value) => _filtersController.selectFreshness(
                  EvidenceFreshness.values
                      .where((item) => item.name == value)
                      .firstOrNull,
                ),
              ),
              DevExSelect(
                id: 'journey-fidelity',
                label: 'Fidelidade',
                value: _filters.fidelity?.name ?? '',
                options: <DevExSelectOption>[
                  const DevExSelectOption(value: '', label: 'Todas'),
                  for (final fidelity in RuntimeFidelity.values)
                    DevExSelectOption(
                      value: fidelity.name,
                      label: runtimeFidelityLabel(fidelity),
                    ),
                ],
                onChange: (value) => _filtersController.selectFidelity(
                  RuntimeFidelity.values
                      .where((item) => item.name == value)
                      .firstOrNull,
                ),
              ),
              if (advancedFilterCount > 0)
                DevExButton(
                  label: 'Limpar filtros',
                  kind: DevExButtonKind.quiet,
                  onPressed: () {
                    _filtersController.selectStatus(null);
                    _filtersController.selectFreshness(null);
                    _filtersController.selectFidelity(null);
                  },
                ),
            ],
          ),
      ]),
      div(classes: 'journey-layout', <Component>[
        aside(classes: 'journey-outline', <Component>[
          div(classes: 'journey-pane-heading', <Component>[
            div(<Component>[
              const span(classes: 'dx-eyebrow', <Component>[
                Component.text('ESTRUTURA'),
              ]),
              h2(<Component>[
                Component.text(
                  '${scenarios.length} ${scenarios.length == 1 ? 'Scenario' : 'Scenarios'}',
                ),
              ]),
            ]),
          ]),
          if (scenarios.isEmpty)
            const DevExEmptyState(
              title: 'Nenhum Scenario visível',
              message: 'Remova ou ajuste os filtros desta Journey.',
            )
          else
            ol(classes: 'scenario-outline-list', <Component>[
              for (final (index, scenario) in scenarios.indexed)
                li(<Component>[
                  Link(
                    to: '/journeys/${journey.id.value}/scenarios/${scenario.id.value}',
                    classes:
                        'scenario-outline-item${scenario.id == selectedScenario?.id ? ' is-selected' : ''}',
                    attributes: <String, String>{
                      if (scenario.id == selectedScenario?.id)
                        'aria-current': 'step',
                    },
                    children: <Component>[
                      span(classes: 'scenario-outline-item__index', <Component>[
                        Component.text('${index + 1}'.padLeft(2, '0')),
                      ]),
                      span(classes: 'scenario-outline-item__copy', <Component>[
                        strong(<Component>[Component.text(scenario.title)]),
                        small(<Component>[Component.text(scenario.id.value)]),
                      ]),
                      _visualDot(visuals[scenario.id]),
                    ],
                  ),
                ]),
            ]),
        ]),
        section(classes: 'journey-canvas', <Component>[
          div(classes: 'journey-canvas__toolbar', <Component>[
            div(classes: 'view-switcher', <Component>[
              DevExButton(
                label: 'Mapa',
                leadingIcon: DevExIconName.map,
                kind: _showMap
                    ? DevExButtonKind.secondary
                    : DevExButtonKind.quiet,
                onPressed: () => setState(() => _showMap = true),
              ),
              DevExButton(
                label: 'Lista',
                leadingIcon: DevExIconName.list,
                kind: !_showMap
                    ? DevExButtonKind.secondary
                    : DevExButtonKind.quiet,
                onPressed: () => setState(() => _showMap = false),
              ),
              if (_showMap) ...<Component>[
                DevExButton(
                  label: 'Reduzir',
                  leadingIcon: DevExIconName.zoomOut,
                  kind: DevExButtonKind.quiet,
                  disabled: _mapZoom <= 0.75,
                  onPressed: () => setState(() {
                    _mapZoom = (_mapZoom - 0.25).clamp(0.75, 1.5);
                  }),
                ),
                DevExStatusPill(
                  label: '${(_mapZoom * 100).round()}%',
                  tone: DevExTone.neutral,
                ),
                DevExButton(
                  label: 'Ampliar',
                  leadingIcon: DevExIconName.zoomIn,
                  kind: DevExButtonKind.quiet,
                  disabled: _mapZoom >= 1.5,
                  onPressed: () => setState(() {
                    _mapZoom = (_mapZoom + 0.25).clamp(0.75, 1.5);
                  }),
                ),
                DevExButton(
                  label: 'Ajustar',
                  leadingIcon: DevExIconName.fit,
                  kind: DevExButtonKind.quiet,
                  onPressed: () => setState(() {
                    _mapZoom = scenarios.length > 1 ? 0.75 : 1;
                  }),
                ),
              ],
            ]),
            small(<Component>[
              Component.text(
                '${journey.scenarioIds.length} no fluxo · ${snapshot.providers.length} providers',
              ),
            ]),
          ]),
          if (scenarios.isEmpty)
            const DevExEmptyState(
              title: 'Mapa sem resultados',
              message: 'Os filtros atuais ocultaram todos os Scenarios.',
            )
          else
            _showMap
                ? _scenarioFlow(
                    journey: journey,
                    scenarios: scenarios,
                    transitions: catalog.transitions
                        .where((item) => item.journeyId == journey.id)
                        .toList(growable: false),
                    visuals: visuals,
                    selectedScenarioId: selectedScenario?.id,
                    resourceClient: resourceClient,
                  )
                : div(classes: 'scenario-board is-list', <Component>[
                    for (final (index, scenario) in scenarios.indexed)
                      _scenarioCard(
                        journey: journey,
                        scenario: scenario,
                        visual: visuals[scenario.id],
                        index: index,
                        selected: scenario.id == selectedScenario?.id,
                        resourceClient: resourceClient,
                      ),
                  ]),
        ]),
        aside(classes: 'journey-inspector', <Component>[
          if (selectedScenario == null)
            const DevExEmptyState(
              title: 'Selecione um Scenario',
              message:
                  'O Inspector mostra contexto, Variant e Evidence da seleção.',
            )
          else ...<Component>[
            header(classes: 'inspector-header', <Component>[
              span(classes: 'dx-eyebrow', <Component>[
                Component.text(selectedScenario.id.value),
              ]),
              h2(<Component>[Component.text(selectedScenario.title)]),
              if (selectedVisual != null)
                DevExStatusPill(
                  label: visualEvidenceStatusLabel(
                    selectedVisual.status,
                    selectedVisual.freshness,
                  ),
                  tone: _visualTone(selectedVisual),
                ),
            ]),
            DevExTabs(
              label: 'Detalhes do Scenario',
              tabs: const <DevExTab>[
                DevExTab(id: 'general', label: 'Geral'),
                DevExTab(id: 'evidence', label: 'Evidence'),
                DevExTab(id: 'modules', label: 'Módulos'),
              ],
              selectedId: _inspectorTab,
              onSelect: (value) => setState(() => _inspectorTab = value),
            ),
            div(
              id: '$_inspectorTab-panel',
              classes: 'inspector-content',
              attributes: <String, String>{
                'role': 'tabpanel',
                'aria-labelledby': '$_inspectorTab-tab',
              },
              <Component>[
                switch (_inspectorTab) {
                  'evidence' => _evidenceInspector(
                    selectedScenario,
                    selectedVisual,
                    previewClient: previewClient,
                    resourceClient: resourceClient,
                    canCollect: canCollect,
                    collectionIsActive: collectionIsActive,
                  ),
                  'modules' => _modulesInspector(snapshot, providerId),
                  _ => _generalInspector(
                    journey,
                    selectedScenario,
                    selectedVisual,
                    previewClient: previewClient,
                    canCollect: canCollect,
                  ),
                },
              ],
            ),
          ],
        ]),
      ]),
      if (_pendingPreviewCollection != null)
        DevExDialog(
          id: 'preview-confirmation',
          title: 'Coletar AutoPreview?',
          description:
              'A captura executará código Flutter do projeto em subprocesso e persistirá os pixels no CAS.',
          onDismiss: _dismissPreviewDialog,
          children: const <Component>[
            p(classes: 'preview-constraints', <Component>[
              Component.text(
                'Confirme somente se a tela usa dados sintéticos. O renderer flutter-test produz Evidence estrutural, não host-native; não prova plugins, permissões, teclado ou integração com o sistema operacional.',
              ),
            ]),
          ],
          actions: <Component>[
            DevExButton(
              label: 'Cancelar',
              kind: DevExButtonKind.quiet,
              onPressed: _dismissPreviewDialog,
            ),
            DevExButton(
              label: 'Confirmo dados sintéticos',
              leadingIcon: DevExIconName.capture,
              autofocus: true,
              onPressed: () => unawaited(_confirmPreviewCollection()),
            ),
          ],
        ),
    ]);
  }

  void _dismissPreviewDialog() => setState(() {
    _pendingPreviewCollection = null;
  });

  Component _scenarioCard({
    required Journey journey,
    required Scenario scenario,
    required JourneyMapNodeViewData? visual,
    required int index,
    required bool selected,
    required StudioHostResourceClient? resourceClient,
  }) {
    final orientation = visual == null
        ? ''
        : visual.selectedVariant.logicalWidth >
              visual.selectedVariant.logicalHeight
        ? ' is-landscape'
        : ' is-portrait';
    return article(
      id: 'scenario-card-${scenario.id.value}',
      classes: 'scenario-card${selected ? ' is-selected' : ''}',
      <Component>[
        Link(
          to: '/journeys/${journey.id.value}/scenarios/${scenario.id.value}',
          classes: 'scenario-card__link',
          attributes: <String, String>{
            if (selected) 'aria-current': 'step',
            'aria-label': 'Scenario ${index + 1}: ${scenario.title}',
          },
          children: <Component>[
            div(classes: 'scenario-card__media$orientation', <Component>[
              if (visual?.artifact case final artifact?)
                VerifiedArtifactImage(
                  handle: artifact,
                  client: resourceClient,
                  alt: 'Captura estrutural de ${scenario.title}',
                  classes: 'scenario-card__image',
                  loading: MediaLoading.lazy,
                )
              else
                div(classes: 'scenario-card__placeholder', <Component>[
                  strong(<Component>[Component.text('Sem imagem atual')]),
                  small(<Component>[
                    Component.text(
                      visual == null
                          ? 'Sem vínculo canônico'
                          : 'Evidence ${visual.status.name}',
                    ),
                  ]),
                ]),
            ]),
            div(classes: 'scenario-card__body', <Component>[
              div(classes: 'scenario-card__meta', <Component>[
                span(<Component>[
                  Component.text('${index + 1}'.padLeft(2, '0')),
                ]),
                if (visual != null)
                  DevExStatusPill(
                    label: visualEvidenceStatusLabel(
                      visual.status,
                      visual.freshness,
                    ),
                    tone: _visualTone(visual),
                  ),
              ]),
              h3(<Component>[Component.text(scenario.title)]),
              p(<Component>[
                Component.text(scenario.description ?? scenario.id.value),
              ]),
            ]),
          ],
        ),
      ],
    );
  }

  Component _scenarioFlow({
    required Journey journey,
    required List<Scenario> scenarios,
    required List<Transition> transitions,
    required Map<ScenarioId, JourneyMapNodeViewData> visuals,
    required ScenarioId? selectedScenarioId,
    required StudioHostResourceClient? resourceClient,
  }) {
    final selectedIndex = scenarios.indexWhere(
      (item) => item.id == selectedScenarioId,
    );
    final window = const DevExSequenceWindowPolicy().around(
      scenarios,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
    );
    final visibleIds = window.items.map((item) => item.id).toSet();
    final visibleTransitions = transitions
        .where(
          (item) =>
              visibleIds.contains(item.from) && visibleIds.contains(item.to),
        )
        .toList(growable: false);
    return div(
      classes: 'journey-map-viewport',
      attributes: const <String, String>{
        'role': 'region',
        'aria-label': 'Viewport do Journey Map',
        'tabindex': '0',
        'aria-describedby': 'journey-map-instructions',
      },
      <Component>[
        p(id: 'journey-map-instructions', classes: 'sr-only', <Component>[
          const Component.text(
            'Use as barras de rolagem ou as setas do teclado para percorrer o mapa. Use Reduzir, Ampliar e Ajustar para controlar o zoom.',
          ),
        ]),
        div(
          classes: 'journey-map-stage is-zoom-${(_mapZoom * 100).round()}',
          <Component>[
            for (final (windowIndex, scenario)
                in window.items.indexed) ...<Component>[
              if (windowIndex == 0 && window.before > 0)
                _virtualizationBoundary(
                  count: window.before,
                  direction: 'anteriores',
                ),
              div(classes: 'journey-map-node', <Component>[
                _scenarioCard(
                  journey: journey,
                  scenario: scenario,
                  visual: visuals[scenario.id],
                  index: window.start + windowIndex,
                  selected: scenario.id == selectedScenarioId,
                  resourceClient: resourceClient,
                ),
              ]),
              if (windowIndex < window.items.length - 1)
                _transitionConnector(
                  from: scenario.id,
                  to: window.items[windowIndex + 1].id,
                  transitions: visibleTransitions,
                ),
              if (windowIndex == window.items.length - 1 && window.after > 0)
                _virtualizationBoundary(
                  count: window.after,
                  direction: 'posteriores',
                ),
            ],
          ],
        ),
        if (visibleTransitions.isEmpty && scenarios.length > 1)
          const p(classes: 'journey-map-notice', <Component>[
            Component.text(
              'O catálogo não declarou transições entre os Scenarios visíveis.',
            ),
          ]),
      ],
    );
  }

  Component _virtualizationBoundary({
    required int count,
    required String direction,
  }) => aside(
    classes: 'journey-map-window-boundary',
    attributes: const <String, String>{'role': 'note'},
    <Component>[
      strong(<Component>[Component.text('$count Scenarios $direction')]),
      span(<Component>[
        const Component.text('Selecione pelo Outline para centralizar.'),
      ]),
    ],
  );

  Component _transitionConnector({
    required ScenarioId from,
    required ScenarioId to,
    required List<Transition> transitions,
  }) {
    final transition = transitions
        .where((item) => item.from == from && item.to == to)
        .firstOrNull;
    return div(
      classes:
          'journey-transition${transition == null ? ' is-undeclared' : ''}',
      attributes: <String, String>{
        'aria-label': transition == null
            ? 'Sem transição declarada entre ${from.value} e ${to.value}'
            : 'Transição de ${from.value} para ${to.value}${transition.label == null ? '' : ': ${transition.label}'}',
      },
      <Component>[
        span(classes: 'journey-transition__line', const <Component>[]),
        span(classes: 'journey-transition__label', <Component>[
          Component.text(transition?.label ?? transition?.id.value ?? '—'),
        ]),
      ],
    );
  }

  Component _generalInspector(
    Journey journey,
    Scenario scenario,
    JourneyMapNodeViewData? visual, {
    required StudioHostPreviewClient? previewClient,
    required bool canCollect,
  }) => div(classes: 'inspector-stack', <Component>[
    p(classes: 'inspector-lede', <Component>[
      Component.text(scenario.description ?? 'Scenario sem descrição.'),
    ]),
    if (visual != null)
      div(classes: 'preview-operation', <Component>[
        div(classes: 'preview-operation__heading', <Component>[
          strong(<Component>[
            Component.text(
              visual.providerId.value == 'evidence.auto-preview'
                  ? 'AutoPreview'
                  : visual.providerId.value,
            ),
          ]),
          DevExStatusPill(
            label: visualEvidenceStatusLabel(visual.status, visual.freshness),
            tone: _visualTone(visual),
          ),
        ]),
        p(<Component>[
          Component.text(
            visual.fidelity == null
                ? 'Sem claim de fidelidade.'
                : 'Fidelidade ${runtimeFidelityLabel(visual.fidelity!).toLowerCase()} · ${visual.selectedVariant.logicalWidth.toInt()} × ${visual.selectedVariant.logicalHeight.toInt()} lógico.',
          ),
        ]),
        if (canCollect && previewClient != null)
          DevExButton(
            label: visual.status == VisualEvidenceStatus.collected
                ? 'Coletar novamente'
                : 'Coletar AutoPreview',
            leadingIcon: DevExIconName.capture,
            onPressed: () => _requestPreviewCollection(
              client: previewClient,
              applicationId: journey.applicationId,
              scenarioId: scenario.id,
              variantId: visual.selectedVariant.id,
            ),
          ),
      ]),
    DevExDefinitionList(
      items: <(String, String)>[
        ('Journey', journey.id.value),
        ('Scenario', scenario.id.value),
        ('Application', scenario.applicationId.value),
        ('Variant', visual?.selectedVariant.id.value ?? 'Não selecionada'),
      ],
    ),
  ]);

  Component _evidenceInspector(
    Scenario scenario,
    JourneyMapNodeViewData? visual, {
    required StudioHostPreviewClient? previewClient,
    required StudioHostResourceClient? resourceClient,
    required bool canCollect,
    required bool collectionIsActive,
  }) {
    if (visual == null) {
      return const DevExEmptyState(
        title: 'Sem Evidence vinculada',
        message:
            'O Host não declarou uma projection para este Scenario e Provider.',
        tone: DevExTone.warning,
      );
    }
    return div(classes: 'inspector-stack', <Component>[
      if (_collectionOperation != null)
        _previewOperation(
          previewClient: previewClient,
          active: collectionIsActive,
        ),
      if (visual.artifact case final artifact?)
        figure(classes: 'inspector-preview', <Component>[
          VerifiedArtifactImage(
            handle: artifact,
            client: resourceClient,
            alt: 'Evidence visual de ${scenario.title}',
            classes: 'inspector-preview__image',
            loading: MediaLoading.eager,
          ),
          figcaption(<Component>[
            Component.text(
              '${visual.selectedVariant.logicalWidth.toInt()} × ${visual.selectedVariant.logicalHeight.toInt()} lógico',
            ),
          ]),
        ]),
      DevExDefinitionList(
        items: <(String, String)>[
          ('Provider', visual.providerId.value),
          (
            'Status',
            visualEvidenceStatusLabel(visual.status, visual.freshness),
          ),
          (
            'Fidelidade',
            visual.fidelity == null
                ? 'Não declarada'
                : runtimeFidelityLabel(visual.fidelity!),
          ),
          ('Variant', visual.selectedVariant.id.value),
          ('Capture key', visual.projection.captureKey?.value ?? 'Ausente'),
          (
            'Artifact digest',
            visual.projection.artifactDigest?.value ?? 'Ausente',
          ),
        ],
      ),
      if (visual.providerId.value == 'evidence.auto-preview')
        const p(classes: 'preview-constraints', <Component>[
          Component.text(
            'Limite: flutter-test oferece fidelidade estrutural, não host-native. O Widget Previewer é a experiência interativa; a exportação PNG é responsabilidade do runner controlado do DevExKit.',
          ),
        ]),
      if (canCollect && previewClient != null)
        DevExButton(
          label: visual.status == VisualEvidenceStatus.collected
              ? 'Coletar novamente'
              : 'Coletar AutoPreview',
          leadingIcon: DevExIconName.capture,
          onPressed: () => _requestPreviewCollection(
            client: previewClient,
            applicationId: scenario.applicationId,
            scenarioId: scenario.id,
            variantId: visual.selectedVariant.id,
          ),
        ),
      if (visual.diagnostics.isNotEmpty)
        details(<Component>[
          const summary(<Component>[Component.text('Diagnósticos')]),
          ul(<Component>[
            for (final diagnostic in visual.diagnostics)
              li(<Component>[Component.text(diagnostic.message)]),
          ]),
        ]),
    ]);
  }

  Component _previewOperation({
    required StudioHostPreviewClient? previewClient,
    required bool active,
  }) {
    final operation = _collectionOperation!;
    final state = '${operation['state'] ?? 'unknown'}';
    final completed = operation['completedItems'];
    final total = operation['totalItems'];
    final failed = operation['failedItems'];
    final error = operation['error'];
    return section(
      classes: 'preview-operation',
      attributes: <String, String>{
        'aria-live': active ? 'polite' : 'off',
        'aria-label': 'Operação de coleta AutoPreview',
      },
      <Component>[
        div(classes: 'preview-operation__heading', <Component>[
          const strong(<Component>[Component.text('Coleta AutoPreview')]),
          DevExStatusPill(
            label: _collectionStateLabel(state),
            tone: _collectionTone(state),
          ),
        ]),
        if (active)
          const DevExProgress(label: 'Capturando Evidence estrutural')
        else
          p(<Component>[
            Component.text(
              completed is int && total is int
                  ? '$completed de $total itens concluídos${failed is int && failed > 0 ? ' · $failed falharam' : ''}.'
                  : 'A operação terminou sem contagem detalhada.',
            ),
          ]),
        if (error != null)
          p(classes: 'is-critical', <Component>[Component.text('$error')]),
        if (active && previewClient != null)
          div(classes: 'preview-operation__actions', <Component>[
            DevExButton(
              label: 'Cancelar coleta',
              kind: DevExButtonKind.danger,
              onPressed: () =>
                  unawaited(_cancelPreviewCollection(previewClient)),
            ),
          ]),
      ],
    );
  }

  Component _modulesInspector(
    WorkspaceSnapshot snapshot,
    ModuleId? providerId,
  ) {
    final modules = snapshot.effectiveKitManifest.modules
        .where((module) => providerId == null || module.moduleId == providerId)
        .toList(growable: false);
    return ul(classes: 'module-list module-list--inspector', <Component>[
      for (final module in modules)
        li(<Component>[
          div(<Component>[
            strong(<Component>[Component.text(module.moduleId.value)]),
            small(<Component>[Component.text(module.state.name)]),
          ]),
          DevExStatusPill(
            label: module.health.name,
            tone: _moduleTone(module.health),
          ),
        ]),
    ]);
  }

  Component _visualDot(JourneyMapNodeViewData? visual) => span(
    classes:
        'visual-dot ${visual == null ? 'is-neutral' : _visualTone(visual).name}',
    attributes: <String, String>{
      'aria-label': visual == null
          ? 'Sem projection'
          : visualEvidenceStatusLabel(visual.status, visual.freshness),
    },
    const <Component>[],
  );

  ModuleId? _selectedProvider(
    WorkspaceSnapshot snapshot,
    ApplicationId applicationId,
  ) {
    final requested = _filters.providerId;
    if (requested != null &&
        snapshot.providers.any((item) => item.providerId == requested)) {
      return requested;
    }
    final bindings =
        snapshot.providerBindings
            .where(
              (item) =>
                  item.capability.id == 'evidence.visual' &&
                  (item.applicationId == null ||
                      item.applicationId == applicationId.value),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final leftSpecific = left.applicationId == applicationId.value
                ? 0
                : 1;
            final rightSpecific = right.applicationId == applicationId.value
                ? 0
                : 1;
            return leftSpecific.compareTo(rightSpecific);
          });
    for (final binding in bindings) {
      for (final id in binding.providerModuleIds) {
        if (snapshot.providers.any((item) => item.providerId == id)) return id;
      }
    }
    return snapshot.providers.firstOrNull?.providerId;
  }

  DevExTone _moduleTone(ModuleHealth health) => switch (health) {
    ModuleHealth.healthy => DevExTone.positive,
    ModuleHealth.degraded => DevExTone.warning,
    ModuleHealth.unhealthy => DevExTone.critical,
    ModuleHealth.unknown => DevExTone.warning,
    ModuleHealth.notApplicable => DevExTone.neutral,
  };

  DevExTone _visualTone(JourneyMapNodeViewData visual) {
    if (visual.status == VisualEvidenceStatus.collected &&
        visual.freshness == EvidenceFreshness.fresh) {
      return DevExTone.positive;
    }
    if (visual.status == VisualEvidenceStatus.failed ||
        visual.freshness == EvidenceFreshness.invalid) {
      return DevExTone.critical;
    }
    return DevExTone.warning;
  }
}

final class _PendingPreviewCollection {
  const _PendingPreviewCollection({
    required this.client,
    required this.applicationId,
    required this.scenarioId,
    required this.variantId,
  });

  final StudioHostPreviewClient client;
  final ApplicationId applicationId;
  final ScenarioId scenarioId;
  final VariantId? variantId;
}
