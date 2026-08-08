import 'dart:async';
import 'dart:math' as math;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:interaction_model/interaction_model.dart'
    show
        SpatialPoint,
        SpatialRect,
        SpatialEdge,
        SpatialIndex,
        SpatialItem,
        SpatialViewport,
        SpatialWindowPolicy,
        SequenceWindowPolicy;
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:studio/src/controllers/studio_filters_controller.dart';
import 'package:studio/src/controllers/studio_workspace_controller.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/host/studio_host_client_factory.dart';
import 'package:studio/src/inventory/inventory_projection.dart';
import 'package:studio/src/jaspr/capability_pages.dart';
import 'package:studio/src/jaspr/experience_authoring_page.dart';
import 'package:studio/src/jaspr/inventory_page.dart';
import 'package:studio/src/jaspr/journey_map_runtime.dart';
import 'package:studio/src/jaspr/motion_context_pages.dart';
import 'package:studio/src/jaspr/scenario_lab_quality_pages.dart';
import 'package:studio/src/jaspr/scenario_lab_run_controls.dart';
import 'package:studio/src/jaspr/verified_artifact_image.dart';
import 'package:studio/src/journey_map/journey_map_view_data.dart';
import 'package:studio/src/journey_map/journey_spatial_projection.dart';
import 'package:studio/src/journey_map/visual_evidence_presentation.dart';
import 'package:studio/src/lab/scenario_lab_relay_controller.dart';
import 'package:studio/src/lab/scenario_lab_relay_target.dart';
import 'package:studio/src/lab/scenario_lab_run_controller.dart';
import 'package:studio/src/lab/scenario_lab_ui_capabilities.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:studio/src/model/studio_filters.dart';
import 'package:studio/src/model/workspace_state.dart';
import 'package:studio/src/remote/remote_session_grant_vault.dart';
import 'package:studio/src/studio_composition.dart';
import 'package:studio/src/target_frame/target_frame.dart';
import 'package:studio_ui/studio_ui.dart';

final class StudioApplication extends StatefulComponent {
  const StudioApplication({
    this.clientFactory = createStudioHostClient,
    this.remoteSessions,
    this.reconnectDelay = const Duration(seconds: 2),
    super.key,
  });

  final StudioHostClientFactory clientFactory;
  final RemoteSessionGrantVault? remoteSessions;
  final Duration reconnectDelay;

  @override
  State<StudioApplication> createState() => _StudioApplicationState();
}

final class _StudioApplicationState extends State<StudioApplication> {
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
  ScenarioLabRunController? _labRunController;
  ScenarioId? _labRunScenarioId;
  ScenarioScriptId? _labRunScriptId;
  Digest? _labRunContentSetDigest;
  ScenarioLabRunId? _pendingLabRunId;
  ScenarioLabRelayController? _labRelayController;
  TargetFrameController? _labRelayFrameController;
  _PendingScenarioLabRelayTerminalObservation?
  _pendingLabRelayTerminalObservation;
  var _labRelayTerminalRefreshInFlight = false;
  var _labRelayTerminalDrainScheduled = false;
  var _labRequestSequence = 0;

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
      final changedContent =
          _workspace.snapshot != null &&
          _workspace.contentIdentity?.contentSetDigest !=
              state.contentIdentity?.contentSetDigest;
      if (lostConnection || changedContent) _clearScenarioLabRuntime();
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
    _clearScenarioLabRuntime();
    unawaited(_filtersController.close());
    _remoteSessions.clear();
    super.dispose();
  }

  @override
  Component build(BuildContext context) => StudioTheme(
    child: Router(
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) => _shell(state, child),
          routes: <RouteBase>[
            Route(
              path: '/',
              title: 'Visão geral · Abel Studio',
              builder: (context, state) => _overview(),
            ),
            Route(
              path: '/journeys/:journeyId',
              title: 'Journey · Abel Studio',
              builder: (context, state) => _journey(context, state),
            ),
            Route(
              path: '/journeys/:journeyId/scenarios/:scenarioId',
              title: 'Scenario · Abel Studio',
              builder: (context, state) => _journey(context, state),
            ),
            Route(
              path: '/journeys/:journeyId/nodes/:nodeId',
              title: 'NodeInstance · Abel Studio',
              builder: (context, state) => _journey(context, state),
            ),
            Route(
              path: '/inventory',
              title: 'Inventory · Abel Studio',
              builder: (context, state) => _inventory(state),
            ),
            Route(
              path: '/inventory/:projectionId',
              title: 'Inventory Projection · Abel Studio',
              builder: (context, state) => _inventory(state),
            ),
            Route(
              path: '/inventory/:projectionId/nodes/:nodeId',
              title: 'Inventory NodeInstance · Abel Studio',
              builder: (context, state) => _inventory(state),
            ),
            Route(
              path: '/authoring/:projectionId',
              title: 'Experience Authoring · Abel Studio',
              builder: (context, state) => _authoring(state),
            ),
            Route(
              path: '/motion/:projectionId',
              title: 'Motion · Abel Studio',
              builder: (context, state) => _motion(state),
            ),
            Route(
              path: '/context/:projectionId',
              title: 'Context Builder · Abel Studio',
              builder: (context, state) => _contextBuilder(state),
            ),
            Route(
              path: '/lab',
              title: 'Scenario Lab · Abel Studio',
              builder: (context, state) => _lab(context, state),
            ),
            Route(
              path: '/lab/scenarios/:scenarioId/scripts/:scriptId',
              title: 'Scenario Lab · Abel Studio',
              builder: (context, state) => _lab(context, state),
            ),
            Route(
              path: '/quality',
              title: 'Quality · Abel Studio',
              builder: (context, state) => _quality(context, state),
            ),
            Route(
              path: '/quality/scenarios/:scenarioId/scripts/:scriptId',
              title: 'Quality · Abel Studio',
              builder: (context, state) => _quality(context, state),
            ),
            Route(
              path: '/target',
              title: 'Target · Abel Studio',
              builder: (context, state) => _target(),
            ),
            Route(
              path: '/gateway',
              title: 'Gateway Lab · Abel Studio',
              builder: (context, state) => _gateway(),
            ),
            Route(
              path: '/reviews',
              title: 'Review · Abel Studio',
              builder: (context, state) => _reviews(),
            ),
            Route(
              path: '/remote/:runId',
              title: 'Remote · Abel Studio',
              builder: (context, state) => _remote(state),
            ),
            Route(
              path: '/hosted',
              title: 'Hosted · Abel Studio',
              builder: (context, state) => _hosted(),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => StudioEmptyState(
        title: 'Página não encontrada',
        message: 'A rota ${state.location} não pertence ao Kit atual.',
        tone: PresentationTone.warning,
        action: const Link(
          to: '/',
          classes: 'studio-ui-button studio-ui-button--primary',
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
    final authoringProjection =
        _workspace.experienceBundle?.topology.projections.firstOrNull;
    final status = _workspace.connection.connected
        ? ('Host conectado', PresentationTone.positive)
        : _workspace.connection.isStale
        ? ('Snapshot desatualizado', PresentationTone.warning)
        : _workspace.failureMessage != null
        ? ('Host indisponível', PresentationTone.critical)
        : ('Conectando', PresentationTone.info);

    return div(classes: 'studio-shell', <Component>[
      aside(classes: 'studio-rail', <Component>[
        Link(
          to: '/',
          classes: 'studio-brand',
          attributes: const <String, String>{'aria-label': 'Abel Studio'},
          children: const <Component>[
            span(classes: 'studio-brand__mark', <Component>[
              Component.text('A'),
            ]),
            span(classes: 'studio-brand__copy', <Component>[
              strong(<Component>[Component.text('Abel')]),
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
                StudioIcon(name: StudioIconName.overview),
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
                  StudioIcon(name: StudioIconName.journey),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Journey Map'),
                  ]),
                ],
              ),
            if (composition?.inventoryEnabled == true)
              Link(
                to: '/inventory',
                classes:
                    'studio-nav__item${routePath.startsWith('/inventory') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/inventory'))
                    'aria-current': 'page',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.list),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Inventory'),
                  ]),
                ],
              ),
            if (composition?.authoringEnabled == true &&
                _workspace.hasContentGeneration &&
                authoringProjection != null)
              Link(
                to: '/authoring/${authoringProjection.id.value}',
                classes:
                    'studio-nav__item${routePath.startsWith('/authoring/') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/authoring/'))
                    'aria-current': 'page',
                  'data-studio-contribution': 'studio.authoring',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.review),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Authoring'),
                  ]),
                ],
              ),
            if (composition?.motionEnabled == true &&
                _workspace.motion != null &&
                authoringProjection != null)
              Link(
                to: '/motion/${authoringProjection.id.value}',
                classes:
                    'studio-nav__item${routePath.startsWith('/motion/') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/motion/')) 'aria-current': 'page',
                  'data-studio-contribution': 'studio.motion',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.play),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Motion'),
                  ]),
                ],
              ),
            if (composition?.contextEnabled == true &&
                authoringProjection != null)
              Link(
                to: '/context/${authoringProjection.id.value}',
                classes:
                    'studio-nav__item${routePath.startsWith('/context/') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/context/')) 'aria-current': 'page',
                  'data-studio-contribution': 'studio.context',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.review),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Context Builder'),
                  ]),
                ],
              ),
            if (composition?.labEnabled == true &&
                _workspace.scenarioLab != null &&
                _workspace.hasContentGeneration)
              Link(
                to: '/lab',
                classes:
                    'studio-nav__item${routePath.startsWith('/lab') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/lab')) 'aria-current': 'page',
                  'data-studio-contribution': 'studio.lab',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.play),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Scenario Lab'),
                  ]),
                ],
              ),
            if (composition?.qualityEnabled == true &&
                _workspace.scenarioLab != null &&
                _workspace.hasContentGeneration)
              Link(
                to: '/quality',
                classes:
                    'studio-nav__item${routePath.startsWith('/quality') ? ' is-active' : ''}',
                attributes: <String, String>{
                  if (routePath.startsWith('/quality')) 'aria-current': 'page',
                  'data-studio-contribution': 'studio.quality',
                },
                children: const <Component>[
                  StudioIcon(name: StudioIconName.success),
                  span(classes: 'studio-nav__copy', <Component>[
                    Component.text('Quality'),
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
                  StudioIcon(name: StudioIconName.target),
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
                  StudioIcon(name: StudioIconName.gateway),
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
                  StudioIcon(name: StudioIconName.review),
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
                  StudioIcon(name: StudioIconName.remote),
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
                  StudioIcon(name: StudioIconName.hosted),
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
            StudioStatusPill(label: status.$1, tone: status.$2, live: true),
            StudioButton(
              label: _workspace.connection.connected
                  ? 'Atualizar'
                  : 'Reconectar',
              leadingIcon: StudioIconName.refresh,
              kind: StudioButtonKind.quiet,
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
            const StudioEmptyState(
              title: 'Studio não habilitado',
              message: 'O ResolvedKitPlan atual não publicou studio.shell.',
              tone: PresentationTone.warning,
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
      return StudioEmptyState(
        title: 'Não foi possível conectar ao Workspace Host',
        message: failure,
        tone: PresentationTone.critical,
        live: true,
        action: StudioButton(
          label: 'Reconectar',
          leadingIcon: StudioIconName.refresh,
          onPressed: () => unawaited(_workspaceController.connect()),
        ),
      );
    }
    return const StudioPanel(
      classes: 'studio-bootstrap',
      children: <Component>[
        StudioProgress(label: 'Conectando ao Workspace Host'),
      ],
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

  PresentationTone _collectionTone(String state) => switch (state) {
    'completed' => PresentationTone.positive,
    'queued' || 'running' => PresentationTone.info,
    'cancelling' || 'completedWithFailures' => PresentationTone.warning,
    'failed' => PresentationTone.critical,
    _ => PresentationTone.neutral,
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
      StudioPageHeader(
        eyebrow: 'WORKSPACE AUTORITATIVO',
        title: 'Visão geral',
        description:
            'Acompanhe Journeys, Scenarios, módulos e cobertura visual publicados pelo Workspace Host.',
        actions: <Component>[
          StudioButton(
            label: 'Atualizar workspace',
            leadingIcon: StudioIconName.refresh,
            kind: StudioButtonKind.secondary,
            onPressed: () => unawaited(_refreshWorkspace()),
          ),
        ],
      ),
      div(classes: 'metric-grid', <Component>[
        StudioMetric(
          label: 'Aplicações',
          value: '${catalog.applications.length}',
          detail: 'targets configurados',
        ),
        StudioMetric(
          label: 'Journeys',
          value: '${catalog.journeys.length}',
          detail: '${catalog.scenarios.length} Scenarios documentados',
        ),
        StudioMetric(
          label: 'Módulos no plano',
          value: '${snapshot.effectiveKitManifest.modules.length}',
          detail: '$healthyModules com lifecycle saudável',
          tone: healthyModules == snapshot.effectiveKitManifest.modules.length
              ? PresentationTone.positive
              : PresentationTone.warning,
        ),
        StudioMetric(
          label: 'Cobertura visual',
          value: '${coverage.currentScenarios}/${coverage.totalScenarios}',
          detail: coverage.isComplete
              ? '${coverage.currentCaptures} capturas atuais'
              : '${coverage.scenariosWithoutCurrentCapture} sem imagem atual',
          tone: coverage.isComplete
              ? PresentationTone.positive
              : PresentationTone.warning,
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
            classes: 'studio-ui-button studio-ui-button--primary',
            child: const Component.text('Abrir Journey Map'),
          ),
        ]),
      div(classes: 'overview-grid', <Component>[
        StudioPanel(
          title: 'Journeys',
          description: 'Fluxos publicados no CatalogManifest.',
          classes: 'journey-list-panel',
          children: <Component>[
            if (catalog.journeys.isEmpty)
              const StudioEmptyState(
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
        StudioPanel(
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
                  StudioStatusPill(
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

  Component _inventory(RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final hostClient = _workspaceController.client;
    final StudioHostResourceClient? resourceClient =
        hostClient is StudioHostResourceClient
        ? hostClient as StudioHostResourceClient
        : null;
    return InventoryPage(
      enabled: composition.inventoryEnabled,
      journeyEnabled: composition.journeyMapEnabled,
      snapshot: snapshot,
      bundle: _workspace.experienceBundle,
      facets: _workspace.scenarioFacets,
      queryParameters: Uri.parse(route.location).queryParameters,
      projectionId: route.params['projectionId'],
      nodeId: route.params['nodeId'],
      resourceClient: resourceClient,
    );
  }

  Component _authoring(RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final host = _workspaceController.client;
    final StudioHostExperienceAuthoringClient? authoringClient =
        host is StudioHostExperienceAuthoringClient
        ? host as StudioHostExperienceAuthoringClient
        : null;
    return ExperienceAuthoringPage(
      enabled: composition.authoringEnabled,
      rpcMethods: snapshot.effectiveKitManifest.rpcMethods.toSet(),
      catalog: snapshot.catalog,
      projectionId: route.params['projectionId'] ?? '',
      bundle: _workspace.experienceBundle,
      scenarioLab: _workspace.scenarioLab,
      contentSetDigest: _workspace.contentIdentity?.contentSetDigest,
      resolvedPlanDigest: snapshot.effectiveKitManifest.resolvedPlanDigest,
      authoringClient: authoringClient,
      onRefreshWorkspace: (expectedContentSetDigest) async {
        await _workspaceController.refreshWorkspace();
        if (_workspaceController.state.contentIdentity?.contentSetDigest !=
            expectedContentSetDigest) {
          throw StateError(
            'Promoted content generation does not match its receipt',
          );
        }
      },
    );
  }

  Component _motion(RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final projectionId = _routeProjectionId(
      route.params['projectionId'],
      _workspace.experienceBundle,
    );
    if (projectionId == null) {
      return const StudioEmptyState(
        title: 'Motion indisponível',
        message: 'A projeção selecionada não pertence ao conteúdo atual.',
        tone: PresentationTone.warning,
      );
    }
    return MotionPage(
      enabled: composition.motionEnabled,
      projectionId: projectionId,
      bundle: _workspace.experienceBundle,
      motion: _workspace.motion,
      scenarioId: _routeScenarioId(route, projectionId),
    );
  }

  Component _contextBuilder(RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final methods = snapshot.effectiveKitManifest.rpcMethods.toSet();
    final host = _workspaceController.client;
    final StudioHostContextBuilderClient? contextClient =
        host is StudioHostContextBuilderClient
        ? host as StudioHostContextBuilderClient
        : null;
    return ContextBuilderPage(
      enabled:
          composition.contextEnabled &&
          methods.contains('context.describe') &&
          methods.contains('context.build'),
      contentSetDigest: _workspace.contentIdentity?.contentSetDigest,
      selection: _contextSelection(route),
      client: contextClient,
    );
  }

  ExperienceProjectionId? _routeProjectionId(
    String? raw,
    ExperienceTopologyBundle? bundle,
  ) {
    if (raw == null || bundle == null) return null;
    try {
      final id = ExperienceProjectionId(raw);
      return bundle.topology.projections.any((item) => item.id == id)
          ? id
          : null;
    } on Object {
      return null;
    }
  }

  ScenarioId? _routeScenarioId(
    RouteState route,
    ExperienceProjectionId projectionId,
  ) {
    final raw = Uri.parse(route.location).queryParameters['scenarioId'];
    if (raw == null) return null;
    try {
      final id = ScenarioId(raw);
      final topology = _workspace.experienceBundle?.topology;
      return topology?.nodes.any(
                (node) =>
                    node.projectionId == projectionId && node.scenarioId == id,
              ) ==
              true
          ? id
          : null;
    } on Object {
      return null;
    }
  }

  ContextSelection? _contextSelection(RouteState route) {
    final bundle = _workspace.experienceBundle;
    final projectionId = _routeProjectionId(
      route.params['projectionId'],
      bundle,
    );
    if (bundle == null || projectionId == null) return null;
    final projection = bundle.topology.projections
        .where((item) => item.id == projectionId)
        .firstOrNull;
    if (projection == null ||
        !bundle.topology.boards.any((item) => item.id == projection.boardId)) {
      return null;
    }
    final query = Uri.parse(route.location).queryParameters;
    final rawScenarioId = query['scenarioId'];
    final scenarioId = _routeScenarioId(route, projectionId);
    if (rawScenarioId != null && scenarioId == null) return null;
    Digest? changeSetDigest;
    final rawChangeSetDigest = query['changeSetDigest'];
    if (rawChangeSetDigest != null) {
      try {
        changeSetDigest = Digest(rawChangeSetDigest);
      } on Object {
        return null;
      }
    }
    return ContextSelection(
      boardId: projection.boardId,
      projectionId: projection.id,
      journeyId: projection.journeyId,
      scenarioId: scenarioId,
      changeSetDigest: changeSetDigest,
    );
  }

  Component _lab(BuildContext context, RouteState route) {
    final snapshot = _workspace.snapshot!;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final binding = _scenarioLabRouteBinding(route);
    final runSelection = _effectiveLabRunSelection(
      binding,
      _scenarioLabRunSelection(route),
    );
    final controller = _matchingScenarioLabController(binding, runSelection);
    final capabilities = _scenarioLabCapabilities(
      snapshot,
      composition,
      runtimeInputs: controller?.current?.runtimeInputs,
    );
    final relayTarget = _scenarioLabRelayTarget(
      binding,
      runSelection,
      controller,
    );
    return ScenarioLabRoutePage(
      enabled: composition.labEnabled,
      qualityEnabled: composition.qualityEnabled,
      catalog: snapshot.catalog,
      manifest: _workspace.scenarioLab,
      hasContentGeneration: _workspace.hasContentGeneration,
      scenarioId: route.params['scenarioId'],
      scriptId: route.params['scriptId'],
      selectedRunId: runSelection.runId,
      runSnapshot: controller?.current,
      runResult: controller?.result,
      runControls: binding == null
          ? null
          : ScenarioLabRunControls(
              capabilities: capabilities,
              allowMutations: true,
              invalidRunId: runSelection.invalid,
              selectedRunId: runSelection.runId,
              lifecycle: controller?.snapshot,
              runSnapshot: controller?.current,
              onStart:
                  capabilities.runAvailable &&
                      runSelection.runId == null &&
                      !runSelection.invalid
                  ? () =>
                        unawaited(_startScenarioLabRun(context, route, binding))
                  : null,
              onCancel: controller == null
                  ? null
                  : () => unawaited(controller.cancel()),
              onReattach:
                  capabilities.runAvailable &&
                      runSelection.runId != null &&
                      !runSelection.invalid
                  ? () => unawaited(
                      _reattachScenarioLabRun(binding, runSelection.runId!),
                    )
                  : null,
              onMountRelay:
                  capabilities.relayAvailable &&
                      controller?.current?.state.isTerminal == false
                  ? () => unawaited(_mountScenarioLabRelay(runSelection.runId!))
                  : null,
              relayTarget: relayTarget,
            ),
    );
  }

  Component _quality(BuildContext context, RouteState route) {
    final snapshot = _workspace.snapshot!;
    final hostClient = _workspaceController.client;
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final capabilities = _scenarioLabCapabilities(snapshot, composition);
    final binding = _scenarioLabRouteBinding(route);
    final runSelection = _scenarioLabRunSelection(route);
    final controller = _matchingScenarioLabController(
      binding,
      runSelection,
      allowHistoricalTerminalContent: true,
    );
    return ScenarioQualityRoutePage(
      enabled: composition.qualityEnabled,
      labEnabled: composition.labEnabled,
      catalog: snapshot.catalog,
      manifest: _workspace.scenarioLab,
      hasContentGeneration: _workspace.hasContentGeneration,
      scenarioId: route.params['scenarioId'],
      scriptId: route.params['scriptId'],
      selectedRunId: runSelection.runId,
      runSnapshot: controller?.current,
      runResult: controller?.result,
      currentContentSetDigest: _workspace.contentIdentity?.contentSetDigest,
      qualityRpcMethods: snapshot.effectiveKitManifest.rpcMethods.toSet(),
      qualityClient: hostClient is StudioHostScenarioQualityClient
          ? hostClient as StudioHostScenarioQualityClient
          : null,
      qualityResourceClient:
          hostClient is StudioHostScenarioQualityResourceClient
          ? hostClient as StudioHostScenarioQualityResourceClient
          : null,
      runControls: binding == null
          ? null
          : ScenarioLabRunControls(
              capabilities: capabilities,
              allowMutations: false,
              invalidRunId: runSelection.invalid,
              selectedRunId: runSelection.runId,
              lifecycle: controller?.snapshot,
              runSnapshot: controller?.current,
              onReattach:
                  capabilities.runAvailable &&
                      runSelection.runId != null &&
                      !runSelection.invalid
                  ? () => unawaited(
                      _reattachScenarioLabRun(
                        binding,
                        runSelection.runId!,
                        allowHistoricalTerminalContent: true,
                      ),
                    )
                  : null,
            ),
    );
  }

  ScenarioLabUiCapabilities _scenarioLabCapabilities(
    WorkspaceSnapshot snapshot,
    StudioComposition composition, {
    ScenarioLabRuntimeInputBinding? runtimeInputs,
  }) => ScenarioLabUiCapabilities.resolve(
    labModuleEnabled: composition.labEnabled,
    hasContentGeneration: _workspace.hasContentGeneration,
    contentIdentity: _workspace.contentIdentity,
    manifest: _workspace.scenarioLab,
    client: _workspaceController.client,
    rpcMethods: snapshot.effectiveKitManifest.rpcMethods,
    runtimeInputs: runtimeInputs,
  );

  _ScenarioLabRouteBinding? _scenarioLabRouteBinding(RouteState route) {
    final rawScenarioId = route.params['scenarioId'];
    final rawScriptId = route.params['scriptId'];
    if (rawScenarioId == null || rawScriptId == null) return null;
    try {
      return _ScenarioLabRouteBinding(
        scenarioId: ScenarioId(rawScenarioId),
        scriptId: ScenarioScriptId(rawScriptId),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  _ScenarioLabRunSelection _scenarioLabRunSelection(RouteState route) {
    final rawRunId = Uri.parse(route.location).queryParameters['runId'];
    if (rawRunId == null) return const _ScenarioLabRunSelection();
    try {
      return _ScenarioLabRunSelection(runId: ScenarioLabRunId(rawRunId));
    } on FormatException {
      return const _ScenarioLabRunSelection(invalid: true);
    } on ArgumentError {
      return const _ScenarioLabRunSelection(invalid: true);
    }
  }

  _ScenarioLabRunSelection _effectiveLabRunSelection(
    _ScenarioLabRouteBinding? binding,
    _ScenarioLabRunSelection requested,
  ) {
    if (requested.invalid || requested.runId != null || binding == null) {
      return requested;
    }
    final pendingRunId = _pendingLabRunId;
    if (pendingRunId != null &&
        _labRunScenarioId == binding.scenarioId &&
        _labRunScriptId == binding.scriptId) {
      return _ScenarioLabRunSelection(runId: pendingRunId);
    }
    return requested;
  }

  ScenarioLabRunController? _matchingScenarioLabController(
    _ScenarioLabRouteBinding? binding,
    _ScenarioLabRunSelection selection, {
    bool allowHistoricalTerminalContent = false,
  }) {
    final controller = _labRunController;
    if (controller == null || binding == null || selection.invalid) return null;
    if (_labRunScenarioId != binding.scenarioId ||
        _labRunScriptId != binding.scriptId ||
        _labRunContentSetDigest !=
            _workspace.contentIdentity?.contentSetDigest) {
      return null;
    }
    if (!allowHistoricalTerminalContent &&
        controller.current?.contentSetDigest != null &&
        controller.current!.contentSetDigest !=
            _workspace.contentIdentity?.contentSetDigest) {
      return null;
    }
    final ownedRunId = controller.snapshot.runId;
    if (selection.runId == null) {
      return ownedRunId == null ? controller : null;
    }
    return ownedRunId == selection.runId ? controller : null;
  }

  Component? _scenarioLabRelayTarget(
    _ScenarioLabRouteBinding? binding,
    _ScenarioLabRunSelection selection,
    ScenarioLabRunController? run,
  ) {
    final runId = selection.runId;
    final relay = _labRelayController;
    final frame = _labRelayFrameController;
    final current = run?.current;
    if (binding == null ||
        runId == null ||
        run == null ||
        current == null ||
        relay == null ||
        frame == null ||
        relay.isTerminal ||
        !identical(_labRunController, run) ||
        _labRunScenarioId != binding.scenarioId ||
        _labRunScriptId != binding.scriptId ||
        _labRunContentSetDigest !=
            _workspace.contentIdentity?.contentSetDigest ||
        run.snapshot.runId != runId ||
        current.runId != runId ||
        current.scenarioId != binding.scenarioId ||
        current.scriptId != binding.scriptId ||
        current.contentSetDigest != _labRunContentSetDigest ||
        current.startRequestDigest != relay.binding.startRequestDigest ||
        current.runtimeInputs?.digest != relay.binding.runtimeInputs.digest ||
        relay.runId != runId ||
        relay.binding.scenarioId != binding.scenarioId) {
      return null;
    }
    return ScenarioLabRelayTarget(
      controller: relay,
      frameController: frame,
      onStateChanged: (snapshot) {
        scheduleMicrotask(() {
          if (mounted && identical(_labRelayController, relay)) {
            if (snapshot.isTerminal) {
              _latchScenarioLabRunObservationAfterRelayTerminal(
                relay: relay,
                relaySnapshot: snapshot,
              );
            }
            setState(() {});
          }
        });
      },
      onDisposed: () {
        scheduleMicrotask(() {
          if (!mounted || !identical(_labRelayController, relay)) return;
          _labRelayController = null;
          if (identical(_labRelayFrameController, frame)) {
            _labRelayFrameController = null;
          }
        });
      },
    );
  }

  void _latchScenarioLabRunObservationAfterRelayTerminal({
    required ScenarioLabRelayController relay,
    required ScenarioLabRelayControllerSnapshot relaySnapshot,
  }) {
    if (!relaySnapshot.isTerminal ||
        !mounted ||
        !identical(_labRelayController, relay)) {
      return;
    }
    final run = _labRunController;
    final scenarioId = _labRunScenarioId;
    final scriptId = _labRunScriptId;
    final contentSetDigest = _labRunContentSetDigest;
    final current = run?.current;
    if (run == null ||
        scenarioId == null ||
        scriptId == null ||
        contentSetDigest == null ||
        run.snapshot.runId != relaySnapshot.runId ||
        current == null ||
        current.runId != relaySnapshot.runId ||
        current.scenarioId != scenarioId ||
        current.scriptId != scriptId ||
        current.contentSetDigest != contentSetDigest ||
        current.startRequestDigest != relay.binding.startRequestDigest ||
        relay.binding.scenarioId != scenarioId ||
        current.state.isTerminal) {
      return;
    }
    _pendingLabRelayTerminalObservation =
        _PendingScenarioLabRelayTerminalObservation(
          relay: relay,
          run: run,
          runId: relaySnapshot.runId,
          scenarioId: scenarioId,
          scriptId: scriptId,
          contentSetDigest: contentSetDigest,
        );
    _scheduleScenarioLabRelayTerminalDrain();
  }

  void _scheduleScenarioLabRelayTerminalDrain() {
    if (_labRelayTerminalDrainScheduled) return;
    _labRelayTerminalDrainScheduled = true;
    scheduleMicrotask(() {
      _labRelayTerminalDrainScheduled = false;
      if (mounted) unawaited(_drainScenarioLabRelayTerminalObservation());
    });
  }

  Future<void> _drainScenarioLabRelayTerminalObservation() async {
    if (_labRelayTerminalRefreshInFlight) return;
    final pending = _pendingLabRelayTerminalObservation;
    if (pending == null) return;
    final run = _labRunController;
    final currentRelay = _labRelayController;
    final current = run?.current;
    final exact =
        mounted &&
        identical(run, pending.run) &&
        (currentRelay == null || identical(currentRelay, pending.relay)) &&
        pending.relay.isTerminal &&
        pending.relay.runId == pending.runId &&
        pending.relay.binding.scenarioId == pending.scenarioId &&
        _labRunScenarioId == pending.scenarioId &&
        _labRunScriptId == pending.scriptId &&
        _labRunContentSetDigest == pending.contentSetDigest &&
        _workspace.contentIdentity?.contentSetDigest ==
            pending.contentSetDigest &&
        run?.snapshot.runId == pending.runId &&
        current?.runId == pending.runId &&
        current?.scenarioId == pending.scenarioId &&
        current?.scriptId == pending.scriptId &&
        current?.contentSetDigest == pending.contentSetDigest &&
        current?.startRequestDigest == pending.relay.binding.startRequestDigest;
    if (!exact || current!.state.isTerminal || run!.snapshot.isTerminal) {
      if (identical(_pendingLabRelayTerminalObservation, pending)) {
        _pendingLabRelayTerminalObservation = null;
      }
      return;
    }
    if (_scenarioLabRunOperationBusy(run.status)) {
      return;
    }
    if (run.status != ScenarioLabRunControllerStatus.nonTerminal &&
        run.status != ScenarioLabRunControllerStatus.active) {
      if (identical(_pendingLabRelayTerminalObservation, pending)) {
        _pendingLabRelayTerminalObservation = null;
      }
      return;
    }

    _pendingLabRelayTerminalObservation = null;
    _labRelayTerminalRefreshInFlight = true;
    try {
      await run.reattachKnownRun(
        runId: pending.runId,
        scenarioId: pending.scenarioId,
        scriptId: pending.scriptId,
      );
    } finally {
      _labRelayTerminalRefreshInFlight = false;
      _scheduleScenarioLabRelayTerminalDrain();
    }
  }

  void _clearScenarioLabRelayTerminalObservation({
    ScenarioLabRunController? run,
  }) {
    final pending = _pendingLabRelayTerminalObservation;
    if (pending == null || (run != null && !identical(pending.run, run))) {
      return;
    }
    _pendingLabRelayTerminalObservation = null;
  }

  bool _scenarioLabRunOperationBusy(ScenarioLabRunControllerStatus status) =>
      const <ScenarioLabRunControllerStatus>{
        ScenarioLabRunControllerStatus.starting,
        ScenarioLabRunControllerStatus.polling,
        ScenarioLabRunControllerStatus.cancelling,
        ScenarioLabRunControllerStatus.reattaching,
      }.contains(status);

  Future<void> _startScenarioLabRun(
    BuildContext context,
    RouteState route,
    _ScenarioLabRouteBinding binding,
  ) async {
    final snapshot = _workspace.snapshot;
    final identity = _workspace.contentIdentity;
    final manifest = _workspace.scenarioLab;
    final host = _workspaceController.client;
    final runHost = switch (host) {
      final StudioHostScenarioLabRunClient value => value,
      _ => null,
    };
    if (snapshot == null ||
        identity == null ||
        manifest == null ||
        runHost == null) {
      return;
    }
    final capabilities = _scenarioLabCapabilities(
      snapshot,
      StudioComposition.fromManifest(snapshot.effectiveKitManifest),
    );
    if (!capabilities.runAvailable) return;

    final controller = _replaceScenarioLabRunController(
      host: runHost,
      identity: identity,
      manifest: manifest,
      binding: binding,
    );
    final requestedAt = DateTime.now().toUtc();
    final request = ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId(
        'studio-${requestedAt.microsecondsSinceEpoch}-${++_labRequestSequence}',
      ),
      expectedContentSetDigest: identity.contentSetDigest,
      expectedScenarioLabManifestDigest: manifest.digest,
      scenarioId: binding.scenarioId,
      scriptId: binding.scriptId,
      requestedAt: requestedAt,
    );
    await controller.start(request);
    if (!mounted || !identical(_labRunController, controller)) return;
    final runId = controller.snapshot.runId;
    if (runId == null) return;
    _pendingLabRunId = runId;
    await _mountScenarioLabRelay(runId);
    if (!mounted || !identical(_labRunController, controller)) return;
    final current = Uri.parse(route.location);
    try {
      await Router.of(context).replace(
        current
            .replace(
              queryParameters: <String, String>{
                ...current.queryParameters,
                'runId': runId.value,
              },
            )
            .toString(),
      );
      if (mounted && _pendingLabRunId == runId) {
        _pendingLabRunId = null;
      }
    } on UnsupportedError {
      // Component tests use the server history facade. The browser route is
      // still authoritative in production; retain only this freshly started
      // run until a real URL writer is available.
    }
  }

  Future<void> _reattachScenarioLabRun(
    _ScenarioLabRouteBinding binding,
    ScenarioLabRunId runId, {
    bool allowHistoricalTerminalContent = false,
  }) async {
    final snapshot = _workspace.snapshot;
    final identity = _workspace.contentIdentity;
    final manifest = _workspace.scenarioLab;
    final host = _workspaceController.client;
    final runHost = switch (host) {
      final StudioHostScenarioLabRunClient value => value,
      _ => null,
    };
    if (snapshot == null ||
        identity == null ||
        manifest == null ||
        runHost == null) {
      return;
    }
    final capabilities = _scenarioLabCapabilities(
      snapshot,
      StudioComposition.fromManifest(snapshot.effectiveKitManifest),
    );
    if (!capabilities.runAvailable) return;

    var controller = _matchingScenarioLabController(
      binding,
      _ScenarioLabRunSelection(runId: runId),
      allowHistoricalTerminalContent: allowHistoricalTerminalContent,
    );
    controller ??= _replaceScenarioLabRunController(
      host: runHost,
      identity: identity,
      manifest: manifest,
      binding: binding,
    );
    await controller.reattachKnownRun(
      runId: runId,
      scenarioId: binding.scenarioId,
      scriptId: binding.scriptId,
      allowHistoricalTerminalContent: allowHistoricalTerminalContent,
    );
  }

  ScenarioLabRunController _replaceScenarioLabRunController({
    required StudioHostScenarioLabRunClient host,
    required ExperienceContentSetIdentity identity,
    required ScenarioLabManifest manifest,
    required _ScenarioLabRouteBinding binding,
  }) {
    _clearScenarioLabRelayTerminalObservation();
    _labRunController?.setStateListener(null);
    _labRunController?.close();
    _labRelayController?.setStateListener(null);
    _labRelayController?.close();
    _labRelayController = null;
    _labRelayFrameController = null;

    late final ScenarioLabRunController controller;
    controller = ScenarioLabRunController(
      host: host,
      contentIdentity: identity,
      manifest: manifest,
      onStateChanged: (_) {
        if (mounted && identical(_labRunController, controller)) {
          if (controller.snapshot.isTerminal) {
            _clearScenarioLabRelayTerminalObservation(run: controller);
            _labRelayController?.close();
            _labRelayController = null;
            _labRelayFrameController = null;
          }
          setState(() {});
          _scheduleScenarioLabRelayTerminalDrain();
        }
      },
    );
    _labRunController = controller;
    _labRunScenarioId = binding.scenarioId;
    _labRunScriptId = binding.scriptId;
    _labRunContentSetDigest = identity.contentSetDigest;
    if (mounted) setState(() {});
    return controller;
  }

  Future<void> _mountScenarioLabRelay(ScenarioLabRunId runId) async {
    final snapshot = _workspace.snapshot;
    final manifest = _workspace.scenarioLab;
    final host = _workspaceController.client;
    final relayHost = switch (host) {
      final StudioHostLabRelayClient value => value,
      _ => null,
    };
    final run = _labRunController;
    if (snapshot == null ||
        manifest == null ||
        relayHost == null ||
        run?.snapshot.runId != runId ||
        run?.current?.state.isTerminal != false) {
      return;
    }
    if (run!.current!.runtimeInputs == null) {
      await run.poll();
      if (!mounted ||
          !identical(_labRunController, run) ||
          _workspace.snapshot?.digest != snapshot.digest ||
          _workspace.scenarioLab?.digest != manifest.digest ||
          run.snapshot.runId != runId ||
          run.current?.state.isTerminal != false ||
          run.current?.runtimeInputs == null) {
        return;
      }
    }
    final StudioLabRelayRunBinding relayBinding;
    try {
      relayBinding = StudioLabRelayRunBinding.fromSnapshot(
        snapshot: run.current!,
        catalog: snapshot.catalog,
        manifest: manifest,
      );
    } on ArgumentError {
      return;
    }
    final capabilities = _scenarioLabCapabilities(
      snapshot,
      StudioComposition.fromManifest(snapshot.effectiveKitManifest),
      runtimeInputs: relayBinding.runtimeInputs,
    );
    if (!capabilities.relayAvailable) return;

    _labRelayController?.setStateListener(null);
    _labRelayController?.close();
    final frame = TargetFrameController();
    final relay = ScenarioLabRelayController(
      binding: relayBinding,
      host: relayHost,
      target: TargetFrameRelayCommandTarget(frame),
    );
    setState(() {
      _labRelayFrameController = frame;
      _labRelayController = relay;
    });
  }

  void _clearScenarioLabRuntime() {
    _clearScenarioLabRelayTerminalObservation();
    _labRunController?.setStateListener(null);
    _labRunController?.close();
    _labRelayController?.setStateListener(null);
    _labRelayController?.close();
    _labRunController = null;
    _labRunScenarioId = null;
    _labRunScriptId = null;
    _labRunContentSetDigest = null;
    _pendingLabRunId = null;
    _labRelayController = null;
    _labRelayFrameController = null;
  }

  Component _journey(BuildContext context, RouteState route) {
    final snapshot = _workspace.snapshot!;
    final catalog = snapshot.catalog;
    final journeyId = route.params['journeyId'] ?? '';
    final journey = catalog.journeys
        .where((item) => item.id.value == journeyId)
        .firstOrNull;
    if (journey == null) {
      return StudioEmptyState(
        title: 'Journey não encontrada',
        message: 'O catálogo não contém a Journey $journeyId.',
        tone: PresentationTone.warning,
      );
    }

    final scenariosById = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final spatial = JourneySpatialProjectionResolution.resolve(
      bundle: _workspace.experienceBundle,
      journey: journey,
    );
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
    final visibleScenarioIds = scenarios.map((scenario) => scenario.id).toSet();
    final projectedNodes = spatial.isReady
        ? spatial.nodes
              .where((node) => visibleScenarioIds.contains(node.scenarioId))
              .toList(growable: false)
        : const <NodeInstance>[];
    final projectedScenarios = <(NodeInstance, Scenario)>[
      for (final node in projectedNodes)
        if (scenariosById[node.scenarioId] case final scenario?)
          (node, scenario),
    ];
    final routeNodeId = route.params['nodeId'];
    final routeScenarioId = route.params['scenarioId'];
    final selectedNode =
        projectedNodes
            .where((item) => item.id.value == routeNodeId)
            .firstOrNull ??
        projectedNodes
            .where((item) => item.scenarioId.value == routeScenarioId)
            .firstOrNull ??
        projectedNodes.firstOrNull;
    final selectedScenario = selectedNode == null
        ? scenarios
                  .where((item) => item.id.value == routeScenarioId)
                  .firstOrNull ??
              scenarios.firstOrNull
        : scenariosById[selectedNode.scenarioId];
    const outlinePolicy = SequenceWindowPolicy(maximumVisibleItems: 48);
    final projectedOutline = outlinePolicy.around(
      projectedScenarios,
      selectedIndex: math.max(
        0,
        projectedScenarios.indexWhere((entry) => entry.$1 == selectedNode),
      ),
    );
    final scenarioOutline = outlinePolicy.around(
      scenarios,
      selectedIndex: math.max(
        0,
        scenarios.indexWhere((scenario) => scenario == selectedScenario),
      ),
    );
    final outlineTotal = spatial.isReady
        ? projectedOutline.total
        : scenarioOutline.total;
    final outlineRendered = spatial.isReady
        ? projectedOutline.items.length
        : scenarioOutline.items.length;
    final outlineStart = spatial.isReady
        ? projectedOutline.start
        : scenarioOutline.start;
    final outlineBefore = spatial.isReady
        ? projectedOutline.before
        : scenarioOutline.before;
    final outlineAfter = spatial.isReady
        ? projectedOutline.after
        : scenarioOutline.after;
    final previousOutlinePath = outlineBefore == 0
        ? null
        : spatial.isReady
        ? '/journeys/${journey.id.value}/nodes/${projectedScenarios[outlineStart - 1].$1.id.value}'
        : '/journeys/${journey.id.value}/scenarios/${scenarios[outlineStart - 1].id.value}';
    final nextOutlinePath = outlineAfter == 0
        ? null
        : spatial.isReady
        ? '/journeys/${journey.id.value}/nodes/${projectedScenarios[projectedOutline.endExclusive].$1.id.value}'
        : '/journeys/${journey.id.value}/scenarios/${scenarios[scenarioOutline.endExclusive].id.value}';
    final selectedVisual = selectedScenario == null
        ? null
        : visuals[selectedScenario.id];
    final composition = StudioComposition.fromManifest(
      snapshot.effectiveKitManifest,
    );
    final inventoryTarget =
        composition.inventoryEnabled && selectedScenario != null
        ? InventoryProjectionIndex(
            catalog: catalog,
            bundle: _workspace.experienceBundle,
          ).uniqueNodeForScenario(
            kind: ProjectionKind.inventory,
            applicationId: journey.applicationId,
            scenarioId: selectedScenario.id,
          )
        : null;
    final revealedItemId = selectedNode?.id.value ?? selectedScenario?.id.value;
    if (revealedItemId != null && _revealedScenarioId != revealedItemId) {
      _revealedScenarioId = revealedItemId;
      revealJourneyScenario('scenario-card-$revealedItemId');
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
    final displayedMapZoom = spatial.layout == null
        ? _mapZoom
        : spatial.layout!.camera.zoom * (_mapZoom / 0.75);

    return section(classes: 'journey-page', <Component>[
      header(classes: 'journey-toolbar', <Component>[
        div(classes: 'journey-toolbar__title', <Component>[
          StudioBreadcrumbs(
            items: <StudioBreadcrumbItem>[
              const StudioBreadcrumbItem(label: 'Visão geral', href: '/'),
              StudioBreadcrumbItem(label: journey.title),
            ],
          ),
          h1(<Component>[Component.text(journey.title)]),
        ]),
        div(classes: 'journey-toolbar__filters', <Component>[
          StudioSearchField(
            id: 'journey-query',
            label: 'Buscar Scenario',
            value: _filters.query,
            placeholder: 'Título ou ID',
            onInput: _filtersController.setQuery,
          ),
          StudioSelect(
            id: 'journey-variant',
            label: 'Variant',
            value: _filters.variantId?.value ?? '',
            options: <StudioSelectOption>[
              const StudioSelectOption(value: '', label: 'Automática'),
              for (final variant in variants)
                StudioSelectOption(
                  value: variant.id.value,
                  label: variant.id.value,
                ),
            ],
            onChange: (value) => _filtersController.selectVariant(
              value.isEmpty ? null : VariantId(value),
            ),
          ),
          StudioSelect(
            id: 'journey-provider',
            label: 'Evidence provider',
            value: providerId?.value ?? '',
            options: <StudioSelectOption>[
              const StudioSelectOption(value: '', label: 'Nenhum'),
              for (final provider in snapshot.providers)
                StudioSelectOption(
                  value: provider.providerId.value,
                  label: provider.displayName,
                ),
            ],
            onChange: (value) => _filtersController.selectProvider(
              value.isEmpty ? null : ModuleId(value),
            ),
          ),
          StudioButton(
            label: advancedFilterCount == 0
                ? 'Filtros'
                : 'Filtros ($advancedFilterCount)',
            leadingIcon: StudioIconName.filters,
            kind: _showAdvancedFilters
                ? StudioButtonKind.secondary
                : StudioButtonKind.quiet,
            attributes: <String, String>{
              'aria-expanded': '$_showAdvancedFilters',
              'aria-controls': 'journey-advanced-filters',
            },
            onPressed: () => setState(() {
              _showAdvancedFilters = !_showAdvancedFilters;
            }),
          ),
          StudioStatusPill(
            label:
                '${coverage.currentScenarios}/${coverage.totalScenarios} com imagem',
            tone: coverage.isComplete
                ? PresentationTone.positive
                : PresentationTone.warning,
          ),
        ]),
        if (_showAdvancedFilters)
          div(
            id: 'journey-advanced-filters',
            classes: 'journey-advanced-filters',
            <Component>[
              StudioSelect(
                id: 'journey-status',
                label: 'Status',
                value: _filters.status?.name ?? '',
                options: <StudioSelectOption>[
                  const StudioSelectOption(value: '', label: 'Todos'),
                  for (final status in VisualEvidenceStatus.values)
                    StudioSelectOption(
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
              StudioSelect(
                id: 'journey-freshness',
                label: 'Atualidade',
                value: _filters.freshness?.name ?? '',
                options: <StudioSelectOption>[
                  const StudioSelectOption(value: '', label: 'Todas'),
                  for (final freshness in EvidenceFreshness.values)
                    StudioSelectOption(
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
              StudioSelect(
                id: 'journey-fidelity',
                label: 'Fidelidade',
                value: _filters.fidelity?.name ?? '',
                options: <StudioSelectOption>[
                  const StudioSelectOption(value: '', label: 'Todas'),
                  for (final fidelity in RuntimeFidelity.values)
                    StudioSelectOption(
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
                StudioButton(
                  label: 'Limpar filtros',
                  kind: StudioButtonKind.quiet,
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
        aside(
          classes: 'journey-outline',
          attributes: const <String, String>{
            'aria-label': 'Outline da Journey',
          },
          <Component>[
            div(classes: 'journey-pane-heading', <Component>[
              div(<Component>[
                const span(classes: 'studio-ui-eyebrow', <Component>[
                  Component.text('ESTRUTURA'),
                ]),
                h2(<Component>[
                  Component.text(
                    spatial.isReady
                        ? '${projectedScenarios.length} ${projectedScenarios.length == 1 ? 'NodeInstance' : 'NodeInstances'}'
                        : '${scenarios.length} ${scenarios.length == 1 ? 'Scenario' : 'Scenarios'}',
                  ),
                ]),
              ]),
            ]),
            if ((spatial.isReady && projectedScenarios.isEmpty) ||
                (!spatial.isReady && scenarios.isEmpty))
              const StudioEmptyState(
                title: 'Nenhum item visível',
                message: 'Remova ou ajuste os filtros desta Journey.',
              )
            else if (spatial.isReady)
              div(<Component>[
                ol(
                  classes: 'scenario-outline-list',
                  attributes: <String, String>{
                    'data-outline-total': '$outlineTotal',
                    'data-outline-rendered': '$outlineRendered',
                    'data-outline-start': '$outlineStart',
                  },
                  <Component>[
                    for (final (index, entry) in projectedOutline.items.indexed)
                      li(<Component>[
                        Link(
                          to: '/journeys/${journey.id.value}/nodes/${entry.$1.id.value}',
                          classes:
                              'scenario-outline-item${entry.$1.id == selectedNode?.id ? ' is-selected' : ''}',
                          attributes: <String, String>{
                            if (entry.$1.id == selectedNode?.id)
                              'aria-current': 'step',
                          },
                          children: <Component>[
                            span(
                              classes: 'scenario-outline-item__index',
                              <Component>[
                                Component.text(
                                  '${projectedOutline.start + index + 1}'
                                      .padLeft(2, '0'),
                                ),
                              ],
                            ),
                            span(classes: 'scenario-outline-item__copy', <
                              Component
                            >[
                              strong(<Component>[
                                Component.text(entry.$2.title),
                              ]),
                              small(<Component>[
                                Component.text(
                                  '${entry.$2.id.value} · ${entry.$1.id.value}',
                                ),
                              ]),
                            ]),
                            _visualDot(visuals[entry.$2.id]),
                          ],
                        ),
                      ]),
                  ],
                ),
                if (outlineBefore > 0 || outlineAfter > 0)
                  nav(
                    classes: 'scenario-outline-window',
                    attributes: const <String, String>{
                      'aria-label': 'Navegação da janela do Outline',
                    },
                    <Component>[
                      p(<Component>[
                        Component.text(
                          'Itens ${outlineStart + 1}–${outlineStart + outlineRendered} de $outlineTotal.',
                        ),
                      ]),
                      if (previousOutlinePath != null)
                        Link(
                          to: previousOutlinePath,
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Janela anterior'),
                        ),
                      if (nextOutlinePath != null)
                        Link(
                          to: nextOutlinePath,
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Próxima janela'),
                        ),
                    ],
                  ),
              ])
            else
              div(<Component>[
                ol(
                  classes: 'scenario-outline-list',
                  attributes: <String, String>{
                    'data-outline-total': '$outlineTotal',
                    'data-outline-rendered': '$outlineRendered',
                    'data-outline-start': '$outlineStart',
                  },
                  <Component>[
                    for (final (index, scenario)
                        in scenarioOutline.items.indexed)
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
                            span(
                              classes: 'scenario-outline-item__index',
                              <Component>[
                                Component.text(
                                  '${scenarioOutline.start + index + 1}'
                                      .padLeft(2, '0'),
                                ),
                              ],
                            ),
                            span(
                              classes: 'scenario-outline-item__copy',
                              <Component>[
                                strong(<Component>[
                                  Component.text(scenario.title),
                                ]),
                                small(<Component>[
                                  Component.text(scenario.id.value),
                                ]),
                              ],
                            ),
                            _visualDot(visuals[scenario.id]),
                          ],
                        ),
                      ]),
                  ],
                ),
                if (outlineBefore > 0 || outlineAfter > 0)
                  nav(
                    classes: 'scenario-outline-window',
                    attributes: const <String, String>{
                      'aria-label': 'Navegação da janela do Outline',
                    },
                    <Component>[
                      p(<Component>[
                        Component.text(
                          'Itens ${outlineStart + 1}–${outlineStart + outlineRendered} de $outlineTotal.',
                        ),
                      ]),
                      if (previousOutlinePath != null)
                        Link(
                          to: previousOutlinePath,
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Janela anterior'),
                        ),
                      if (nextOutlinePath != null)
                        Link(
                          to: nextOutlinePath,
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Próxima janela'),
                        ),
                    ],
                  ),
              ]),
          ],
        ),
        section(classes: 'journey-canvas', <Component>[
          div(classes: 'journey-canvas__toolbar', <Component>[
            div(classes: 'view-switcher', <Component>[
              StudioButton(
                label: 'Mapa',
                leadingIcon: StudioIconName.map,
                kind: _showMap
                    ? StudioButtonKind.secondary
                    : StudioButtonKind.quiet,
                onPressed: () => setState(() => _showMap = true),
              ),
              StudioButton(
                label: 'Lista',
                leadingIcon: StudioIconName.list,
                kind: !_showMap
                    ? StudioButtonKind.secondary
                    : StudioButtonKind.quiet,
                onPressed: () => setState(() => _showMap = false),
              ),
              if (_showMap) ...<Component>[
                StudioButton(
                  label: 'Reduzir',
                  leadingIcon: StudioIconName.zoomOut,
                  kind: StudioButtonKind.quiet,
                  disabled: _mapZoom <= 0.75,
                  onPressed: () => setState(() {
                    _mapZoom = (_mapZoom - 0.25).clamp(0.75, 1.5);
                  }),
                ),
                StudioStatusPill(
                  label: '${(displayedMapZoom * 100).round()}%',
                  tone: PresentationTone.neutral,
                ),
                StudioButton(
                  label: 'Ampliar',
                  leadingIcon: StudioIconName.zoomIn,
                  kind: StudioButtonKind.quiet,
                  disabled: _mapZoom >= 1.5,
                  onPressed: () => setState(() {
                    _mapZoom = (_mapZoom + 0.25).clamp(0.75, 1.5);
                  }),
                ),
                StudioButton(
                  label: 'Ajustar',
                  leadingIcon: StudioIconName.fit,
                  kind: StudioButtonKind.quiet,
                  onPressed: () => setState(() {
                    _mapZoom = spatial.layout == null && scenarios.length == 1
                        ? 1
                        : 0.75;
                  }),
                ),
              ],
            ]),
            small(<Component>[
              Component.text(
                spatial.isReady
                    ? '${spatial.projection!.title} · ${spatial.nodes.length} instâncias · ${snapshot.providers.length} providers'
                    : '${journey.scenarioIds.length} no catálogo · ${snapshot.providers.length} providers',
              ),
            ]),
          ]),
          if ((spatial.isReady && projectedScenarios.isEmpty) ||
              (!spatial.isReady && scenarios.isEmpty))
            const StudioEmptyState(
              title: 'Mapa sem resultados',
              message: 'Os filtros atuais ocultaram todos os itens.',
            )
          else if (!_showMap)
            div(classes: 'scenario-board is-list', <Component>[
              if (spatial.isReady)
                for (final (index, entry) in projectedOutline.items.indexed)
                  _scenarioCard(
                    journey: journey,
                    scenario: entry.$2,
                    nodeInstanceId: entry.$1.id,
                    visual: visuals[entry.$2.id],
                    index: projectedOutline.start + index,
                    selected: entry.$1.id == selectedNode?.id,
                    resourceClient: resourceClient,
                  )
              else
                for (final (index, scenario) in scenarioOutline.items.indexed)
                  _scenarioCard(
                    journey: journey,
                    scenario: scenario,
                    visual: visuals[scenario.id],
                    index: scenarioOutline.start + index,
                    selected: scenario.id == selectedScenario?.id,
                    resourceClient: resourceClient,
                  ),
            ])
          else if (spatial.isReady)
            _spatialScenarioFlow(
              journey: journey,
              projection: spatial.projection!,
              layout: spatial.layout!,
              nodes: projectedNodes,
              edges: spatial.edges,
              scenariosById: scenariosById,
              transitionsById: <TransitionId, Transition>{
                for (final transition in catalog.transitions)
                  transition.id: transition,
              },
              visuals: visuals,
              selectedNodeId: selectedNode?.id,
              resourceClient: resourceClient,
            )
          else
            div(classes: 'journey-map-fallback', <Component>[
              StudioEmptyState(
                title: 'Layout espacial indisponível',
                message:
                    '${spatial.fallbackMessage} A lista abaixo preserva somente a ordem semântica declarada pela Journey.',
                tone: PresentationTone.warning,
              ),
              div(classes: 'scenario-board is-list', <Component>[
                for (final (index, scenario) in scenarioOutline.items.indexed)
                  _scenarioCard(
                    journey: journey,
                    scenario: scenario,
                    visual: visuals[scenario.id],
                    index: scenarioOutline.start + index,
                    selected: scenario.id == selectedScenario?.id,
                    resourceClient: resourceClient,
                  ),
              ]),
            ]),
        ]),
        aside(
          classes: 'journey-inspector',
          attributes: const <String, String>{
            'aria-label': 'Inspector da Journey',
          },
          <Component>[
            if (selectedScenario == null)
              const StudioEmptyState(
                title: 'Selecione um Scenario',
                message:
                    'O Inspector mostra contexto, Variant e Evidence da seleção.',
              )
            else ...<Component>[
              header(classes: 'inspector-header', <Component>[
                span(classes: 'studio-ui-eyebrow', <Component>[
                  Component.text(
                    selectedNode == null
                        ? selectedScenario.id.value
                        : '${selectedScenario.id.value} · ${selectedNode.id.value}',
                  ),
                ]),
                h2(<Component>[Component.text(selectedScenario.title)]),
                if (selectedVisual != null)
                  StudioStatusPill(
                    label: visualEvidenceStatusLabel(
                      selectedVisual.status,
                      selectedVisual.freshness,
                    ),
                    tone: _visualTone(selectedVisual),
                  ),
              ]),
              StudioTabs(
                label: 'Detalhes do Scenario',
                tabs: const <StudioTab>[
                  StudioTab(id: 'general', label: 'Geral'),
                  StudioTab(id: 'evidence', label: 'Evidence'),
                  StudioTab(id: 'modules', label: 'Módulos'),
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
                      node: selectedNode,
                      projection: spatial.projection,
                      layout: spatial.layout,
                      inventoryEnabled: composition.inventoryEnabled,
                      inventoryTarget: inventoryTarget,
                      previewClient: previewClient,
                      canCollect: canCollect,
                    ),
                  },
                ],
              ),
            ],
          ],
        ),
      ]),
      if (_pendingPreviewCollection != null)
        StudioDialog(
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
            StudioButton(
              label: 'Cancelar',
              kind: StudioButtonKind.quiet,
              onPressed: _dismissPreviewDialog,
            ),
            StudioButton(
              label: 'Confirmo dados sintéticos',
              leadingIcon: StudioIconName.capture,
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
    NodeInstanceId? nodeInstanceId,
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
    final visualIdentity = nodeInstanceId?.value ?? scenario.id.value;
    final destination = nodeInstanceId == null
        ? '/journeys/${journey.id.value}/scenarios/${scenario.id.value}'
        : '/journeys/${journey.id.value}/nodes/${nodeInstanceId.value}';
    return article(
      id: 'scenario-card-$visualIdentity',
      classes: 'scenario-card${selected ? ' is-selected' : ''}',
      <Component>[
        Link(
          to: destination,
          classes: 'scenario-card__link',
          attributes: <String, String>{
            if (selected) 'aria-current': 'step',
            'aria-label': nodeInstanceId == null
                ? 'Scenario ${index + 1}: ${scenario.title}'
                : 'NodeInstance ${nodeInstanceId.value}, Scenario ${scenario.title}',
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
                  Component.text(
                    nodeInstanceId?.value ?? '${index + 1}'.padLeft(2, '0'),
                  ),
                ]),
                if (visual != null)
                  StudioStatusPill(
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

  Component _spatialScenarioFlow({
    required Journey journey,
    required ExperienceProjection projection,
    required ProjectionLayoutManifest layout,
    required List<NodeInstance> nodes,
    required List<EdgeInstance> edges,
    required Map<ScenarioId, Scenario> scenariosById,
    required Map<TransitionId, Transition> transitionsById,
    required Map<ScenarioId, JourneyMapNodeViewData> visuals,
    required NodeInstanceId? selectedNodeId,
    required StudioHostResourceClient? resourceClient,
  }) {
    final framesByNode = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in layout.nodeFrames) frame.nodeInstanceId: frame,
    };
    final candidateNodeIds = nodes.map((node) => node.id).toSet();
    final candidateEdges = edges
        .where(
          (edge) =>
              candidateNodeIds.contains(edge.fromNodeId) &&
              candidateNodeIds.contains(edge.toNodeId),
        )
        .toList(growable: false);
    final index = SpatialIndex(
      items: <SpatialItem>[
        for (final node in nodes)
          SpatialItem(
            id: node.id.value,
            bounds: SpatialRect.fromLTWH(
              framesByNode[node.id]!.x,
              framesByNode[node.id]!.y,
              framesByNode[node.id]!.width,
              framesByNode[node.id]!.height,
            ),
          ),
      ],
      edges: <SpatialEdge>[
        for (final edge in candidateEdges)
          SpatialEdge(
            id: edge.id.value,
            fromId: edge.fromNodeId.value,
            toId: edge.toNodeId.value,
          ),
      ],
    );
    final bounds = index.contentBounds!;
    final zoom = layout.camera.zoom * (_mapZoom / 0.75);
    final viewport = SpatialViewport(
      worldOrigin: SpatialPoint(bounds.left, bounds.top),
      width: math.max(bounds.width * zoom, 1),
      height: math.max(bounds.height * zoom, 1),
      zoom: zoom,
    );
    final window =
        SpatialWindowPolicy(
          maximumVisibleItems: 64,
          maximumRenderableEdges: 256,
          maximumBoundaryEdges: 256,
          overscan: 160,
          minimumZoom: 0.05,
          maximumZoom: 64,
        ).window(
          index: index,
          viewport: viewport,
          selectedItemId: selectedNodeId?.value,
        );
    final renderedNodeIds = window.itemIds.toSet();
    final renderedEdgeIds = window.renderableEdges
        .map((edge) => edge.id)
        .toSet();
    final renderedNodes = nodes
        .where((node) => renderedNodeIds.contains(node.id.value))
        .toList(growable: false);
    final renderedEdges = candidateEdges
        .where((edge) => renderedEdgeIds.contains(edge.id.value))
        .toList(growable: false);
    final geometry = _ProjectionCanvasGeometry(layout: layout, zoom: zoom);
    const maximumDecorationsPerKind = 128;
    final decorationsTruncated =
        layout.groups.length > maximumDecorationsPerKind ||
        layout.lanes.length > maximumDecorationsPerKind ||
        layout.annotations.length > maximumDecorationsPerKind;
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
          classes: 'journey-map-stage is-spatial',
          attributes: <String, String>{
            'data-projection-id': projection.id.value,
            'data-layout-digest': layout.digest.value,
            ...geometry.canvasAttributes(),
            'data-camera-x': '${layout.camera.x}',
            'data-camera-y': '${layout.camera.y}',
            'data-camera-zoom': '${layout.camera.zoom}',
            'data-window-candidates': '${window.visibleCandidateCount}',
            'data-window-rendered': '${renderedNodes.length}',
            'data-renderable-edge-total': '${window.renderableEdgeCount}',
            'data-renderable-edge-rendered': '${renderedEdges.length}',
            'data-boundary-edge-total': '${window.boundaryEdgeCount}',
            'data-boundary-edge-retained': '${window.boundaryEdges.length}',
          },
          <Component>[
            for (final lane in layout.lanes.take(maximumDecorationsPerKind))
              div(
                classes: 'journey-map-lane',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    lane.x,
                    lane.y,
                    lane.width,
                    lane.height,
                  ),
                  'role': 'group',
                  'aria-label': 'Lane ${lane.title}',
                  'data-lane-id': lane.id.value,
                },
                <Component>[
                  span(<Component>[Component.text(lane.title)]),
                ],
              ),
            for (final group in layout.groups.take(maximumDecorationsPerKind))
              div(
                classes: 'journey-map-group',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    group.x,
                    group.y,
                    group.width,
                    group.height,
                  ),
                  'role': 'group',
                  'aria-label': 'Group ${group.title}',
                  'data-group-id': group.id.value,
                },
                <Component>[
                  span(<Component>[Component.text(group.title)]),
                ],
              ),
            svg(
              <Component>[
                for (final edge in renderedEdges)
                  _spatialEdge(
                    edge: edge,
                    transition: transitionsById[edge.transitionId],
                    from: framesByNode[edge.fromNodeId]!,
                    to: framesByNode[edge.toNodeId]!,
                    geometry: geometry,
                  ),
              ],
              viewBox: geometry.viewBox,
              classes: 'journey-map-edges',
              attributes: <String, String>{
                'width': geometry.number(geometry.width),
                'height': geometry.number(geometry.height),
                'role': 'group',
                'aria-label': 'EdgeInstances do Journey Map',
              },
            ),
            for (final edge in renderedEdges)
              _spatialEdgeLabel(
                edge: edge,
                transition: transitionsById[edge.transitionId],
                from: framesByNode[edge.fromNodeId]!,
                to: framesByNode[edge.toNodeId]!,
                geometry: geometry,
              ),
            for (final annotation in layout.annotations.take(
              maximumDecorationsPerKind,
            ))
              aside(
                classes: 'journey-map-annotation',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    annotation.x,
                    annotation.y,
                    annotation.width,
                    annotation.height,
                  ),
                  'role': 'note',
                  'data-annotation-id': annotation.id.value,
                },
                <Component>[Component.text(annotation.text)],
              ),
            for (final (index, node) in renderedNodes.indexed)
              if (scenariosById[node.scenarioId] case final scenario?)
                div(
                  classes: 'journey-map-node is-authored',
                  attributes: <String, String>{
                    ...geometry.frameAttributes(framesByNode[node.id]!),
                    'data-node-instance-id': node.id.value,
                    'data-scenario-id': scenario.id.value,
                  },
                  <Component>[
                    _scenarioCard(
                      journey: journey,
                      nodeInstanceId: node.id,
                      scenario: scenario,
                      visual: visuals[scenario.id],
                      index: index,
                      selected: node.id == selectedNodeId,
                      resourceClient: resourceClient,
                    ),
                  ],
                ),
          ],
        ),
        const p(
          classes: 'journey-map-geometry-unsupported',
          attributes: <String, String>{'role': 'status'},
          <Component>[
            Component.text(
              'Este navegador não oferece o suporte necessário para aplicar a geometria autorada com a política de segurança ativa. Use a estrutura semântica para navegar pelos NodeInstances.',
            ),
          ],
        ),
        if (window.isTruncated ||
            window.boundaryEdgeCount > 0 ||
            window.renderableEdgesTruncated)
          p(classes: 'journey-map-notice', <Component>[
            Component.text(
              'Janela espacial limitada a ${renderedNodes.length} NodeInstances; '
              '${window.renderableEdgeCount - renderedEdges.length} conexões internas omitidas e '
              '${window.boundaryEdgeCount} conexões cruzam o limite sem endpoints artificiais.',
            ),
          ]),
        if (decorationsTruncated)
          const p(classes: 'journey-map-notice', <Component>[
            Component.text(
              'A renderização limita cada tipo de decoração a 128 itens.',
            ),
          ]),
      ],
    );
  }

  Component _spatialEdge({
    required EdgeInstance edge,
    required Transition? transition,
    required ProjectionNodeFrame from,
    required ProjectionNodeFrame to,
    required _ProjectionCanvasGeometry geometry,
  }) {
    final fromX = geometry.x(from.x + from.width / 2);
    final fromY = geometry.y(from.y + from.height / 2);
    final toX = geometry.x(to.x + to.width / 2);
    final toY = geometry.y(to.y + to.height / 2);
    final label = transition?.label ?? transition?.id.value ?? edge.id.value;
    return line(
      const <Component>[],
      x1: geometry.number(fromX),
      y1: geometry.number(fromY),
      x2: geometry.number(toX),
      y2: geometry.number(toY),
      classes: 'journey-map-edge',
      attributes: <String, String>{
        'role': 'img',
        'aria-label':
            'EdgeInstance ${edge.id.value}: ${edge.fromNodeId.value} para ${edge.toNodeId.value}, $label',
        'data-edge-instance-id': edge.id.value,
        'data-from-node-id': edge.fromNodeId.value,
        'data-to-node-id': edge.toNodeId.value,
      },
    );
  }

  Component _spatialEdgeLabel({
    required EdgeInstance edge,
    required Transition? transition,
    required ProjectionNodeFrame from,
    required ProjectionNodeFrame to,
    required _ProjectionCanvasGeometry geometry,
  }) {
    final fromX = geometry.x(from.x + from.width / 2);
    final fromY = geometry.y(from.y + from.height / 2);
    final toX = geometry.x(to.x + to.width / 2);
    final toY = geometry.y(to.y + to.height / 2);
    final label = transition?.label ?? transition?.id.value ?? edge.id.value;
    return span(
      classes: 'journey-map-edge__label',
      attributes: <String, String>{
        ...geometry.pointAttributes((fromX + toX) / 2, (fromY + toY) / 2),
        'aria-hidden': 'true',
        'data-edge-label-for': edge.id.value,
      },
      <Component>[Component.text(label)],
    );
  }

  Component _generalInspector(
    Journey journey,
    Scenario scenario,
    JourneyMapNodeViewData? visual, {
    required NodeInstance? node,
    required ExperienceProjection? projection,
    required ProjectionLayoutManifest? layout,
    required bool inventoryEnabled,
    required ExperienceOccurrenceTarget? inventoryTarget,
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
          StudioStatusPill(
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
          StudioButton(
            label: visual.status == VisualEvidenceStatus.collected
                ? 'Coletar novamente'
                : 'Coletar AutoPreview',
            leadingIcon: StudioIconName.capture,
            onPressed: () => _requestPreviewCollection(
              client: previewClient,
              applicationId: journey.applicationId,
              scenarioId: scenario.id,
              variantId: visual.selectedVariant.id,
            ),
          ),
      ]),
    StudioDefinitionList(
      items: <(String, String)>[
        ('Journey', journey.id.value),
        ('Scenario', scenario.id.value),
        if (node != null) ('NodeInstance', node.id.value),
        if (projection != null) ('Projection', projection.id.value),
        if (layout != null) ('Layout digest', layout.digest.value),
        ('Application', scenario.applicationId.value),
        ('Variant', visual?.selectedVariant.id.value ?? 'Não selecionada'),
      ],
    ),
    if (inventoryTarget != null)
      Link(
        to: '/inventory/${inventoryTarget.projection.id.value}/nodes/${inventoryTarget.node.id.value}',
        classes: 'studio-ui-button studio-ui-button--secondary',
        attributes: const <String, String>{
          'data-cross-lens': 'journey-to-inventory',
        },
        child: const Component.text('Abrir occurrence única na Inventory'),
      )
    else if (inventoryEnabled)
      const p(classes: 'inventory-cross-lens-note', <Component>[
        Component.text(
          'Não há uma occurrence Inventory única para este Scenario; nenhum destino foi escolhido arbitrariamente.',
        ),
      ]),
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
      return const StudioEmptyState(
        title: 'Sem Evidence vinculada',
        message:
            'O Host não declarou uma projection para este Scenario e Provider.',
        tone: PresentationTone.warning,
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
      StudioDefinitionList(
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
            'Limite: flutter-test oferece fidelidade estrutural, não host-native. O Widget Previewer é a experiência interativa; a exportação PNG é responsabilidade do runner controlado do Abel.',
          ),
        ]),
      if (canCollect && previewClient != null)
        StudioButton(
          label: visual.status == VisualEvidenceStatus.collected
              ? 'Coletar novamente'
              : 'Coletar AutoPreview',
          leadingIcon: StudioIconName.capture,
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
          StudioStatusPill(
            label: _collectionStateLabel(state),
            tone: _collectionTone(state),
          ),
        ]),
        if (active)
          const StudioProgress(label: 'Capturando Evidence estrutural')
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
            StudioButton(
              label: 'Cancelar coleta',
              kind: StudioButtonKind.danger,
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
          StudioStatusPill(
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

  PresentationTone _moduleTone(ModuleHealth health) => switch (health) {
    ModuleHealth.healthy => PresentationTone.positive,
    ModuleHealth.degraded => PresentationTone.warning,
    ModuleHealth.unhealthy => PresentationTone.critical,
    ModuleHealth.unknown => PresentationTone.warning,
    ModuleHealth.notApplicable => PresentationTone.neutral,
  };

  PresentationTone _visualTone(JourneyMapNodeViewData visual) {
    if (visual.status == VisualEvidenceStatus.collected &&
        visual.freshness == EvidenceFreshness.fresh) {
      return PresentationTone.positive;
    }
    if (visual.status == VisualEvidenceStatus.failed ||
        visual.freshness == EvidenceFreshness.invalid) {
      return PresentationTone.critical;
    }
    return PresentationTone.warning;
  }
}

final class _ScenarioLabRouteBinding {
  const _ScenarioLabRouteBinding({
    required this.scenarioId,
    required this.scriptId,
  });

  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
}

final class _ScenarioLabRunSelection {
  const _ScenarioLabRunSelection({this.runId, this.invalid = false});

  final ScenarioLabRunId? runId;
  final bool invalid;
}

final class _PendingScenarioLabRelayTerminalObservation {
  const _PendingScenarioLabRelayTerminalObservation({
    required this.relay,
    required this.run,
    required this.runId,
    required this.scenarioId,
    required this.scriptId,
    required this.contentSetDigest,
  });

  final ScenarioLabRelayController relay;
  final ScenarioLabRunController run;
  final ScenarioLabRunId runId;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final Digest contentSetDigest;
}

final class _ProjectionCanvasGeometry {
  _ProjectionCanvasGeometry({
    required ProjectionLayoutManifest layout,
    required this.zoom,
  }) {
    var bounds = SpatialRect.fromLTWH(layout.camera.x, layout.camera.y, 1, 1);
    for (final frame in layout.nodeFrames) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(frame.x, frame.y, frame.width, frame.height),
      );
    }
    for (final group in layout.groups) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(group.x, group.y, group.width, group.height),
      );
    }
    for (final lane in layout.lanes) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(lane.x, lane.y, lane.width, lane.height),
      );
    }
    for (final annotation in layout.annotations) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(
          annotation.x,
          annotation.y,
          annotation.width,
          annotation.height,
        ),
      );
    }
    _bounds = bounds;
  }

  static const double _padding = 32;
  final double zoom;
  late final SpatialRect _bounds;

  double get width => _bounds.width * zoom + _padding * 2;
  double get height => _bounds.height * zoom + _padding * 2;
  String get viewBox => '0 0 ${number(width)} ${number(height)}';

  double x(double worldX) => (worldX - _bounds.left) * zoom + _padding;
  double y(double worldY) => (worldY - _bounds.top) * zoom + _padding;

  String number(double value) {
    if (!value.isFinite) {
      throw StateError('Projection canvas geometry must remain finite');
    }
    final encoded = value.toString();
    return encoded.endsWith('.0')
        ? encoded.substring(0, encoded.length - 2)
        : encoded;
  }

  Map<String, String> canvasAttributes() => <String, String>{
    'data-canvas-width': number(width),
    'data-canvas-height': number(height),
  };

  Map<String, String> frameAttributes(ProjectionNodeFrame frame) =>
      positionAttributes(frame.x, frame.y, frame.width, frame.height);

  Map<String, String> pointAttributes(double canvasX, double canvasY) =>
      <String, String>{'data-x': number(canvasX), 'data-y': number(canvasY)};

  Map<String, String> positionAttributes(
    double worldX,
    double worldY,
    double worldWidth,
    double worldHeight,
  ) => <String, String>{
    'data-x': number(x(worldX)),
    'data-y': number(y(worldY)),
    'data-width': number(worldWidth * zoom),
    'data-height': number(worldHeight * zoom),
  };
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
