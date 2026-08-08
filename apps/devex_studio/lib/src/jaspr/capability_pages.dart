import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:devex_studio/src/remote/remote_session_grant_vault.dart';
import 'package:devex_studio/src/remote/remote_session_surface.dart';
import 'package:devex_studio/src/target_frame/target_frame.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

final class TargetSessionPage extends StatefulComponent {
  const TargetSessionPage({
    required this.enabled,
    required this.snapshot,
    required this.client,
    this.initialSession,
    this.gatewayOrigin,
    this.onSessionChanged,
    super.key,
  });

  final bool enabled;
  final WorkspaceSnapshot snapshot;
  final StudioHostSessionClient? client;
  final SessionSnapshot? initialSession;
  final Uri? gatewayOrigin;
  final ValueChanged<SessionSnapshot?>? onSessionChanged;

  @override
  State<TargetSessionPage> createState() => _TargetSessionPageState();
}

final class _TargetSessionPageState extends State<TargetSessionPage> {
  late String _launchProfileId;
  var _targetOrigin = 'http://127.0.0.1:8080';
  final TargetFrameController _frameController = TargetFrameController();
  SessionSnapshot? _session;
  String? _message;
  Object? _error;
  var _busy = false;
  var _stopping = false;

  @override
  void initState() {
    super.initState();
    _session = component.initialSession;
    _launchProfileId =
        component.snapshot.catalog.executionBindings
            .map((binding) => binding.launchProfileId)
            .whereType<String>()
            .firstOrNull ??
        '';
  }

  Future<void> _start() async {
    final client = component.client;
    if (client == null || _busy) return;
    final origin = Uri.tryParse(_targetOrigin.trim());
    if (_launchProfileId.trim().isEmpty ||
        origin == null ||
        !origin.isAbsolute ||
        !const <String>{'http', 'https'}.contains(origin.scheme) ||
        !const <String>{
          'localhost',
          '127.0.0.1',
          '::1',
        }.contains(origin.host) ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      setState(() {
        _error =
            'Informe um LaunchProfile e uma origem HTTP(S) loopback canônica.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = 'Iniciando target…';
    });
    try {
      final session = await client.startSession(
        launchProfileId: _launchProfileId.trim(),
        targetOrigin: origin,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _message = 'Target pronto em ${session.target?.origin ?? origin}.';
      });
      component.onSessionChanged?.call(session);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final client = component.client;
    final session = _session;
    if (client == null || session == null || _busy) return;
    await _sessionAction(
      () => client.resetSession(session.id),
      success: 'Target restaurado ao estado inicial.',
    );
  }

  Future<void> _stop() async {
    final client = component.client;
    final session = _session;
    if (client == null || session == null || _busy) return;
    setState(() {
      _busy = true;
      _stopping = true;
      _error = null;
    });
    try {
      final stopped = await client.stopSession(session.id);
      if (!mounted) return;
      setState(() {
        _session = stopped;
        _message = 'Target encerrado e recursos liberados.';
      });
      component.onSessionChanged?.call(stopped);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _sessionAction(
    Future<SessionSnapshot> Function() action, {
    required String success,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await action();
      if (!mounted) return;
      setState(() {
        _session = session;
        _message = success;
      });
      component.onSessionChanged?.call(session);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.enabled) {
      return const DevExEmptyState(
        title: 'Target não habilitado',
        message: 'O profile atual não publicou studio.target.',
        tone: DevExTone.warning,
      );
    }
    final session = _session;
    final target = session?.target;
    final canOperate = session != null && !session.state.isTerminal;
    return section(classes: 'capability-page page-stack', <Component>[
      const DevExPageHeader(
        eyebrow: 'SESSÃO LOCAL ISOLADA',
        title: 'Target',
        description:
            'Inicie o app consumidor em origem separada e opere o iframe sem expor paths ou credenciais do Host.',
      ),
      DevExPanel(
        title: 'Iniciar sessão',
        description:
            'Os valores devem corresponder a um LaunchProfile configurado no Host.',
        children: <Component>[
          div(classes: 'capability-form-grid', <Component>[
            DevExTextInput(
              id: 'target-launch-profile',
              label: 'LaunchProfile ID',
              value: _launchProfileId,
              placeholder: 'sample-web',
              hint: component.snapshot.catalog.executionBindings.isEmpty
                  ? 'O catálogo não publicou bindings; informe o ID configurado no Host.'
                  : 'IDs conhecidos: ${component.snapshot.catalog.executionBindings.map((item) => item.launchProfileId).whereType<String>().toSet().join(', ')}',
              onInput: (value) => setState(() => _launchProfileId = value),
            ),
            DevExTextInput(
              id: 'target-origin',
              label: 'Origem do target',
              value: _targetOrigin,
              placeholder: 'http://127.0.0.1:8080',
              hint: 'Somente uma origem loopback HTTP(S) canônica é aceita.',
              onInput: (value) => setState(() => _targetOrigin = value),
            ),
          ]),
          div(classes: 'capability-actions', <Component>[
            DevExButton(
              label: _busy ? 'Iniciando…' : 'Iniciar target',
              leadingIcon: DevExIconName.play,
              onPressed: _busy || component.client == null
                  ? null
                  : () => unawaited(_start()),
              disabled: _busy || component.client == null,
            ),
            DevExButton(
              label: 'Restaurar',
              leadingIcon: DevExIconName.refresh,
              kind: DevExButtonKind.secondary,
              onPressed: canOperate && !_busy
                  ? () => unawaited(_reset())
                  : null,
              disabled: !canOperate || _busy,
            ),
            DevExButton(
              label: 'Encerrar',
              leadingIcon: DevExIconName.stop,
              kind: DevExButtonKind.danger,
              onPressed: canOperate && !_busy ? () => unawaited(_stop()) : null,
              disabled: !canOperate || _busy,
            ),
          ]),
          if (_message != null)
            DevExFeedbackBanner(
              title: 'Sessão',
              message: _message!,
              tone: DevExTone.info,
              live: true,
            ),
          if (_error != null)
            DevExFeedbackBanner(
              title: 'Não foi possível operar o target',
              message: '$_error',
              tone: DevExTone.critical,
              live: true,
            ),
        ],
      ),
      if (target != null && session!.state == SessionState.ready && !_stopping)
        DevExPanel(
          title: 'Aplicação em execução',
          description:
              '${session.id} · ${target.platform.name} · ${target.origin}',
          classes: 'target-panel',
          children: <Component>[
            TargetFrame(
              targetUri: target.origin,
              sessionId: session.id,
              nonce: session.digest.value,
              gatewayOrigin: component.gatewayOrigin,
              controller: _frameController,
              onAuthorizedMessage: (envelope) {
                if (!mounted) return;
                setState(() {
                  _message =
                      'Mensagem autorizada do target #${envelope.sequence}.';
                });
              },
            ),
          ],
        )
      else if (session != null)
        DevExPanel(
          title: 'Estado da sessão',
          children: <Component>[
            DevExDefinitionList(
              items: <(String, String)>[
                ('ID', session.id),
                ('Estado', session.state.name),
                ('LaunchProfile', session.launchProfileId),
                if (session.terminalReason != null)
                  ('Motivo terminal', session.terminalReason!),
              ],
            ),
          ],
        ),
    ]);
  }
}

final class GatewayLabPage extends StatefulComponent {
  const GatewayLabPage({
    required this.enabled,
    required this.client,
    required this.ownerSession,
    this.initialStatus,
    this.onStatusChanged,
    super.key,
  });

  final bool enabled;
  final StudioHostGatewayClient? client;
  final SessionSnapshot? ownerSession;
  final Map<String, Object?>? initialStatus;
  final ValueChanged<Map<String, Object?>?>? onStatusChanged;

  @override
  State<GatewayLabPage> createState() => _GatewayLabPageState();
}

final class _GatewayLabPageState extends State<GatewayLabPage> {
  var _gatewaySessionId = '';
  var _selectedPresetId = '';
  List<GatewayPlanArtifactDescriptor> _presets =
      const <GatewayPlanArtifactDescriptor>[];
  List<Map<String, Object?>> _traffic = const <Map<String, Object?>>[];
  Map<String, Object?>? _status;
  Object? _error;
  var _busy = false;
  var _loadingPresets = false;

  @override
  void initState() {
    super.initState();
    _status = component.initialStatus;
    _selectedPresetId = _status?['presetId'] as String? ?? '';
    _gatewaySessionId =
        _status?['gatewaySessionId'] as String? ??
        _status?['id'] as String? ??
        '';
    unawaited(_loadPresets());
    if (_gatewaySessionId.isNotEmpty) unawaited(_loadTraffic());
  }

  GatewayPlanArtifactDescriptor? get _selectedPreset => _presets
      .where((preset) => preset.presetId.value == _selectedPresetId)
      .firstOrNull;

  bool get _ownerReady => component.ownerSession?.state == SessionState.ready;

  bool get _canOperate =>
      _gatewaySessionId.isNotEmpty && _status?['state'] != 'stopped';

  Future<void> _loadPresets() async {
    final client = component.client;
    if (client == null || _loadingPresets) return;
    setState(() {
      _loadingPresets = true;
      _error = null;
    });
    try {
      final presets = await client.gatewayPresets();
      if (!mounted) return;
      setState(() {
        _presets = presets;
        if (!presets.any(
          (preset) => preset.presetId.value == _selectedPresetId,
        )) {
          _selectedPresetId = presets.firstOrNull?.presetId.value ?? '';
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loadingPresets = false);
    }
  }

  Future<void> _start() async {
    final client = component.client;
    if (client == null || _busy) return;
    final owner = component.ownerSession;
    final preset = _selectedPreset;
    if (owner == null || owner.state != SessionState.ready) {
      setState(() => _error = 'Inicie uma sessão Target pronta primeiro.');
      return;
    }
    if (preset == null) {
      setState(() => _error = 'Selecione um GatewayPreset compilado.');
      return;
    }
    await _operate(() async {
      final value = await client.startGateway(
        ownerSessionId: owner.id,
        planArtifactDigest: preset.artifactDigest,
      );
      final id = value['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('O Host retornou um Gateway sem ID.');
      }
      _gatewaySessionId = id;
      return <String, Object?>{
        ...await client.gatewayStatus(id),
        'presetId': preset.presetId.value,
      };
    });
  }

  Future<void> _refresh() => _operate(() {
    if (_gatewaySessionId.trim().isEmpty) {
      throw const FormatException('Informe o ID da sessão Gateway.');
    }
    return component.client!.gatewayStatus(_gatewaySessionId.trim());
  });

  Future<void> _reset() => _operate(() {
    if (_gatewaySessionId.trim().isEmpty) {
      throw const FormatException('Informe o ID da sessão Gateway.');
    }
    return component.client!.resetGateway(_gatewaySessionId.trim());
  });

  Future<void> _stop() => _operate(() {
    if (_gatewaySessionId.trim().isEmpty) {
      throw const FormatException('Informe o ID da sessão Gateway.');
    }
    return component.client!.stopGateway(_gatewaySessionId.trim());
  }, loadTraffic: false);

  Future<void> _operate(
    Future<Map<String, Object?>> Function() action, {
    bool loadTraffic = true,
  }) async {
    if (_busy || component.client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      final value = <String, Object?>{
        ...result,
        if (!result.containsKey('presetId') && _selectedPresetId.isNotEmpty)
          'presetId': _selectedPresetId,
      };
      setState(() {
        _status = value;
        if (value['gatewaySessionId'] case final String id) {
          _gatewaySessionId = id;
        }
        if (value['state'] == 'stopped') {
          _traffic = const <Map<String, Object?>>[];
        }
      });
      component.onStatusChanged?.call(value);
      if (loadTraffic && value['state'] != 'stopped') await _loadTraffic();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadTraffic() async {
    final client = component.client;
    if (client == null || _gatewaySessionId.isEmpty) return;
    try {
      final traffic = await client.gatewayTraffic(
        _gatewaySessionId,
        limit: 100,
      );
      if (mounted) setState(() => _traffic = traffic.reversed.toList());
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.enabled) {
      return const DevExEmptyState(
        title: 'Gateway não habilitado',
        message: 'O profile atual não publicou studio.gateway.',
        tone: DevExTone.warning,
      );
    }
    return section(classes: 'capability-page page-stack', <Component>[
      const DevExPageHeader(
        eyebrow: 'INTERCEPTOR CONTROLADO',
        title: 'Gateway Lab',
        description:
            'Associe um plano canônico do CAS a uma Session pronta. O sidecar continua supervisionado pelo Host.',
      ),
      if (!_ownerReady)
        DevExPanel(
          title: '1. Inicie o Target',
          description:
              'O Gateway é um sidecar pertencente a uma Session pronta. O Studio preencherá essa associação automaticamente.',
          children: const <Component>[
            Link(
              to: '/target',
              classes: 'dx-button dx-button--primary',
              child: Component.text('Abrir Target'),
            ),
          ],
        )
      else
        DevExPanel(
          title: '1. Target proprietário',
          description: 'Sessão pronta e mantida pelo Host.',
          children: <Component>[
            DevExDefinitionList(
              items: <(String, String)>[
                ('Session', component.ownerSession!.id),
                ('LaunchProfile', component.ownerSession!.launchProfileId),
                ('Estado', component.ownerSession!.state.name),
              ],
            ),
          ],
        ),
      DevExPanel(
        title: '2. Selecione o plano',
        description:
            'O Host compila os GatewayPresets do catálogo e mantém seus artifacts no CAS.',
        children: <Component>[
          if (_loadingPresets)
            const DevExProgress(label: 'Compilando GatewayPresets')
          else if (_presets.isEmpty)
            const DevExEmptyState(
              title: 'Nenhum GatewayPreset publicado',
              message:
                  'Adicione ao catálogo pelo menos um preset com rotas válidas.',
              tone: DevExTone.warning,
            )
          else ...<Component>[
            DevExSelect(
              id: 'gateway-preset',
              label: 'GatewayPreset',
              value: _selectedPresetId,
              options: <DevExSelectOption>[
                for (final preset in _presets)
                  DevExSelectOption(
                    value: preset.presetId.value,
                    label:
                        '${preset.presetId.value} · ${preset.backendMode.name}',
                  ),
              ],
              onChange: (value) => setState(() => _selectedPresetId = value),
            ),
            if (_selectedPreset case final preset?)
              DevExDefinitionList(
                items: <(String, String)>[
                  ('Descrição', preset.description),
                  ('Modo', preset.backendMode.name),
                  ('Rotas', '${preset.routeCount}'),
                  ('Plan digest', preset.planDigest.value),
                ],
              ),
          ],
          div(classes: 'capability-actions', <Component>[
            DevExButton(
              label: _busy ? 'Operando…' : 'Iniciar Gateway',
              leadingIcon: DevExIconName.play,
              onPressed: _busy || !_ownerReady || _selectedPreset == null
                  ? null
                  : () => unawaited(_start()),
              disabled:
                  _busy ||
                  !_ownerReady ||
                  _selectedPreset == null ||
                  _canOperate,
            ),
            DevExButton(
              label: 'Atualizar status',
              leadingIcon: DevExIconName.refresh,
              kind: DevExButtonKind.secondary,
              onPressed: _busy || !_canOperate
                  ? null
                  : () => unawaited(_refresh()),
              disabled: _busy || !_canOperate,
            ),
            DevExButton(
              label: 'Resetar tráfego',
              kind: DevExButtonKind.secondary,
              onPressed: _busy || !_canOperate
                  ? null
                  : () => unawaited(_reset()),
              disabled: _busy || !_canOperate,
            ),
            DevExButton(
              label: 'Encerrar',
              leadingIcon: DevExIconName.stop,
              kind: DevExButtonKind.danger,
              onPressed: _busy || !_canOperate
                  ? null
                  : () => unawaited(_stop()),
              disabled: _busy || !_canOperate,
            ),
          ]),
          if (_status != null) ...<Component>[
            h3(<Component>[Component.text('Estado operacional')]),
            DevExDefinitionList(
              items: <(String, String)>[
                ('GatewaySession', _gatewaySessionId),
                ('Estado', '${_status!['state'] ?? 'desconhecido'}'),
                if (_status!['dataOrigin'] != null)
                  ('Origem de dados', '${_status!['dataOrigin']}'),
                if (_status!['backendMode'] != null)
                  ('Backend', '${_status!['backendMode']}'),
                if (_status!['networkContainment'] != null)
                  ('Contenção', '${_status!['networkContainment']}'),
                if (_status!['trafficEvents'] != null)
                  ('Eventos', '${_status!['trafficEvents']}'),
              ],
            ),
          ],
          if (_error != null)
            DevExFeedbackBanner(
              title: 'Operação Gateway rejeitada',
              message: '$_error',
              tone: DevExTone.critical,
              live: true,
            ),
        ],
      ),
      if (_canOperate)
        DevExPanel(
          title: '3. Tráfego observado',
          description:
              'Volte ao Target para consumir a origem Gateway; depois atualize esta visão.',
          children: <Component>[
            div(classes: 'capability-actions', <Component>[
              const Link(
                to: '/target',
                classes: 'dx-button dx-button--secondary',
                child: Component.text('Abrir Target com Gateway'),
              ),
              DevExButton(
                label: 'Atualizar tráfego',
                leadingIcon: DevExIconName.refresh,
                kind: DevExButtonKind.secondary,
                onPressed: _busy ? null : () => unawaited(_loadTraffic()),
                disabled: _busy,
              ),
            ]),
            if (_traffic.isEmpty)
              const DevExEmptyState(
                title: 'Nenhuma requisição observada',
                message:
                    'Abra o Target com o Gateway ativo para produzir eventos.',
              )
            else
              div(classes: 'gateway-traffic-table-wrap', <Component>[
                table(classes: 'gateway-traffic-table', <Component>[
                  thead(<Component>[
                    tr(<Component>[
                      th(<Component>[Component.text('#')]),
                      th(<Component>[Component.text('Método')]),
                      th(<Component>[Component.text('Rota')]),
                      th(<Component>[Component.text('Resultado')]),
                      th(<Component>[Component.text('Status')]),
                      th(<Component>[Component.text('Duração')]),
                    ]),
                  ]),
                  tbody(<Component>[
                    for (final event in _traffic)
                      tr(<Component>[
                        td(<Component>[
                          Component.text('${event['sequence'] ?? '—'}'),
                        ]),
                        td(<Component>[
                          Component.text('${event['method'] ?? '—'}'),
                        ]),
                        td(<Component>[
                          Component.text('${event['routeTemplate'] ?? '—'}'),
                        ]),
                        td(<Component>[
                          Component.text('${event['outcome'] ?? '—'}'),
                        ]),
                        td(<Component>[
                          Component.text('${event['status'] ?? '—'}'),
                        ]),
                        td(<Component>[
                          Component.text(
                            '${event['durationMicroseconds'] ?? '—'} µs',
                          ),
                        ]),
                      ]),
                  ]),
                ]),
              ]),
          ],
        ),
    ]);
  }
}

final class ReviewGuidesPage extends StatelessComponent {
  const ReviewGuidesPage({required this.snapshot, super.key});

  final WorkspaceSnapshot snapshot;

  @override
  Component build(BuildContext context) {
    final guides = snapshot.catalog.reviewGuides;
    return section(classes: 'capability-page page-stack', <Component>[
      const DevExPageHeader(
        eyebrow: 'REVISÃO ORIENTADA',
        title: 'Review',
        description:
            'Execute critérios observáveis ligados aos Scenarios e bindings canônicos do catálogo.',
      ),
      if (guides.isEmpty)
        const DevExEmptyState(
          title: 'Nenhum ReviewGuide publicado',
          message:
              'Adicione reviewGuides ao CatalogManifest para habilitar uma revisão orientada.',
        )
      else
        for (final guide in guides)
          DevExPanel(
            title: guide.title,
            description: '${guide.id.value} · ${guide.steps.length} etapas',
            children: <Component>[
              ol(classes: 'review-step-list', <Component>[
                for (final step in guide.steps)
                  li(<Component>[
                    strong(<Component>[Component.text(step.instruction)]),
                    p(<Component>[Component.text(step.observationCriteria)]),
                    small(<Component>[
                      Component.text(
                        '${step.scenarioId.value} · ${step.bindingId.value}',
                      ),
                    ]),
                  ]),
              ]),
            ],
          ),
    ]);
  }
}

final class CapabilityStatusPage extends StatelessComponent {
  const CapabilityStatusPage({
    required this.enabled,
    required this.title,
    required this.contribution,
    required this.description,
    required this.unavailableMessage,
    super.key,
  });

  final bool enabled;
  final String title;
  final String contribution;
  final String description;
  final String unavailableMessage;

  @override
  Component build(BuildContext context) =>
      section(classes: 'capability-page page-stack', <Component>[
        DevExPageHeader(
          eyebrow: 'CAPABILITY CONDICIONAL',
          title: title,
          description: description,
        ),
        DevExEmptyState(
          title: enabled ? '$title habilitado' : '$title não habilitado',
          message: enabled
              ? unavailableMessage
              : 'O ResolvedKitPlan atual não publicou $contribution.',
          tone: enabled ? DevExTone.info : DevExTone.warning,
        ),
      ]);
}

final class RemoteSessionPage extends StatefulComponent {
  const RemoteSessionPage({
    required this.enabled,
    required this.runId,
    required this.grants,
    super.key,
  });

  final bool enabled;
  final String runId;
  final RemoteSessionGrantVault grants;

  @override
  State<RemoteSessionPage> createState() => _RemoteSessionPageState();
}

final class _RemoteSessionPageState extends State<RemoteSessionPage> {
  late RemoteSessionGrant? _grant;

  @override
  void initState() {
    super.initState();
    _grant = component.enabled ? component.grants.take(component.runId) : null;
  }

  @override
  Component build(BuildContext context) {
    final grant = _grant;
    return section(classes: 'capability-page remote-page page-stack', <
      Component
    >[
      const DevExPageHeader(
        eyebrow: 'CREDENCIAL EFÊMERA',
        title: 'Execução remota',
        description:
            'A sessão usa exatamente um transporte concedido e descarta o grant após a primeira abertura.',
      ),
      if (!component.enabled)
        const DevExEmptyState(
          title: 'Execução remota não habilitada',
          message: 'O profile atual não publicou studio.remote-session.',
          tone: DevExTone.warning,
        )
      else if (grant == null || grant.runId != component.runId)
        const DevExEmptyState(
          title: 'Sessão remota indisponível',
          message:
              'A credencial efêmera não está disponível. Solicite uma nova sessão ao control plane.',
          tone: DevExTone.warning,
        )
      else
        RemoteSessionSurface(
          grant: grant,
          onClosed: () {
            if (mounted) setState(() => _grant = null);
          },
        ),
    ]);
  }
}
