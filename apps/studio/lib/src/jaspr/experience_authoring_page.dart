import 'dart:async';
import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:studio/src/authoring/experience_authoring_controller.dart';
import 'package:studio/src/authoring/studio_experience_authoring_transport.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio_ui/studio_ui.dart';

final class ExperienceAuthoringPage extends StatefulComponent {
  const ExperienceAuthoringPage({
    required this.enabled,
    required this.rpcMethods,
    required this.catalog,
    required this.projectionId,
    this.bundle,
    this.scenarioLab,
    this.contentSetDigest,
    this.resolvedPlanDigest,
    this.authoringClient,
    this.onRefreshWorkspace,
    super.key,
  });

  final bool enabled;
  final Set<String> rpcMethods;
  final CatalogManifest catalog;
  final String projectionId;
  final ExperienceTopologyBundle? bundle;
  final ScenarioLabManifest? scenarioLab;
  final Digest? contentSetDigest;
  final Digest? resolvedPlanDigest;
  final StudioHostExperienceAuthoringClient? authoringClient;
  final Future<void> Function(Digest expectedContentSetDigest)?
  onRefreshWorkspace;

  @override
  State<ExperienceAuthoringPage> createState() =>
      _ExperienceAuthoringPageState();
}

enum _AuthoringConfirmation { restart, reject, approve, promote }

final class _ExperienceAuthoringPageState
    extends State<ExperienceAuthoringPage> {
  ExperienceAuthoringController? _controller;
  ExperienceAuthoringControllerSnapshot? _view;
  String? _boundary;
  String _boundaryState = 'unavailable';
  Digest? _expectedPromotedContentSetDigest;

  final Map<String, String> _xInputs = <String, String>{};
  final Map<String, String> _yInputs = <String, String>{};
  String _findingSubject = '';
  ExperienceFindingSeverity _findingSeverity = ExperienceFindingSeverity.info;
  String _findingSummary = '';
  String _findingDetail = '';
  String _conceptTitle = '';
  String _conceptRationale = '';
  String _commentSubject = '';
  String _commentBody = '';
  String _decisionRationale = '';
  _AuthoringConfirmation? _confirmation;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateComponent(ExperienceAuthoringPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.enabled != component.enabled ||
        oldComponent.authoringClient != component.authoringClient ||
        oldComponent.catalog.digest != component.catalog.digest ||
        oldComponent.bundle?.digest != component.bundle?.digest ||
        oldComponent.scenarioLab?.digest != component.scenarioLab?.digest ||
        oldComponent.contentSetDigest != component.contentSetDigest ||
        oldComponent.resolvedPlanDigest != component.resolvedPlanDigest ||
        oldComponent.projectionId != component.projectionId ||
        !_sameMethods(oldComponent.rpcMethods, component.rpcMethods)) {
      _detachController();
      _attachController();
    }
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  void _attachController() {
    _boundary = null;
    _boundaryState = 'unavailable';
    _view = null;
    if (!component.enabled) {
      _boundary = 'O ResolvedKitPlan atual não publicou studio.authoring.';
      return;
    }
    final bundle = component.bundle;
    final contentSetDigest = component.contentSetDigest;
    final resolvedPlanDigest = component.resolvedPlanDigest;
    if (bundle == null || contentSetDigest == null) {
      _boundary =
          'Authoring exige uma geração atômica de conteúdo Experience v2.';
      return;
    }
    if (resolvedPlanDigest == null) {
      _boundary = 'O plano efetivo não possui identidade verificável.';
      return;
    }
    final expectedPromotion = _expectedPromotedContentSetDigest;
    if (expectedPromotion != null && contentSetDigest != expectedPromotion) {
      _boundaryState = 'protocolViolation';
      _boundary =
          'A geração atual não corresponde ao receipt da promoção aplicada.';
      return;
    }
    if (expectedPromotion == contentSetDigest) {
      _expectedPromotedContentSetDigest = null;
    }
    StudioHostExperienceAuthoringClient? host;
    late final StudioExperienceAuthoringTransportAvailability transport;
    try {
      transport = selectStudioExperienceAuthoringTransport(
        component.rpcMethods,
      );
    } on FormatException {
      _boundaryState = 'protocolViolation';
      _boundary =
          'O Host publicou apenas parte dos 16 métodos Experience Authoring.';
      return;
    }
    if (transport == StudioExperienceAuthoringTransportAvailability.v1) {
      host = component.authoringClient;
      if (host == null) {
        _boundaryState = 'protocolViolation';
        _boundary =
            'O Host anunciou Authoring completo, mas não publicou o facade tipado.';
        return;
      }
    }
    try {
      final controller = ExperienceAuthoringController(
        host: host,
        catalog: component.catalog,
        bundle: bundle,
        contentSetDigest: contentSetDigest,
        resolvedPlanDigest: resolvedPlanDigest,
        projectionId: ExperienceProjectionId(component.projectionId),
        scenarioLab: component.scenarioLab,
        onPromotionRefresh: _refreshAfterPromotion,
      );
      _controller = controller;
      _view = controller.snapshot;
      controller.setStateListener((snapshot) {
        if (!mounted) return;
        setState(() {
          _view = snapshot;
          if (snapshot.pendingContentRefreshDigest case final expected?) {
            _expectedPromotedContentSetDigest = expected;
          }
          _synchronizeFormSelections(snapshot.review);
        });
      });
      unawaited(controller.load());
    } on Object {
      _boundaryState = 'protocolViolation';
      _boundary =
          'A rota não corresponde a uma projeção Authoring válida desta geração.';
    }
  }

  void _detachController() {
    final controller = _controller;
    _controller = null;
    controller?.setStateListener(null);
    controller?.close();
    _view = null;
    _confirmation = null;
    _xInputs.clear();
    _yInputs.clear();
  }

  Future<void> _refreshAfterPromotion(Digest expectedContentSetDigest) async {
    final refresh = component.onRefreshWorkspace;
    if (refresh != null) await refresh(expectedContentSetDigest);
  }

  void _synchronizeFormSelections(ExperienceAuthoringReviewView? review) {
    final keys =
        review?.subjectOptions.map((item) => item.key).toSet() ??
        const <String>{};
    if (!keys.contains(_findingSubject)) {
      _findingSubject = review?.subjectOptions.firstOrNull?.key ?? '';
    }
    if (!keys.contains(_commentSubject)) {
      _commentSubject = review?.subjectOptions.firstOrNull?.key ?? '';
    }
  }

  @override
  Component build(BuildContext context) {
    final boundary = _boundary;
    if (boundary != null) {
      return section(
        classes: 'authoring-page page-stack',
        attributes: <String, String>{'data-authoring-state': _boundaryState},
        <Component>[
          const StudioPageHeader(
            eyebrow: 'EXPERIENCE AUTHORING',
            title: 'Authoring e review',
            description:
                'Edite layouts e materialize decisões sem retirar autoridade do Host.',
          ),
          StudioEmptyState(
            title: 'Authoring indisponível',
            message: boundary,
            tone: PresentationTone.warning,
          ),
        ],
      );
    }
    final view = _view;
    final controller = _controller;
    if (view == null || controller == null) {
      return const StudioProgress(label: 'Preparando Experience Authoring');
    }
    final nodes = view.draft?.nodes ?? view.baseNodes;
    return section(
      classes: 'authoring-page page-stack',
      attributes: <String, String>{
        'data-authoring-state': view.phase.name,
        'data-authoring-availability': view.availability.name,
        'data-authoring-role': view.isAuthor
            ? 'author'
            : view.isViewer
            ? 'viewer'
            : 'unsupported',
        'data-authoring-projection': view.projectionId.value,
      },
      <Component>[
        StudioPageHeader(
          eyebrow: 'EXPERIENCE AUTHORING',
          title: view.projectionTitle,
          description:
              'Draft local, comparação e review permanecem CAS-fenced e Host-authoritative.',
          actions: <Component>[
            StudioButton(
              label: 'Atualizar estado',
              kind: StudioButtonKind.quiet,
              leadingIcon: StudioIconName.refresh,
              disabled: view.busy,
              onPressed: view.busy
                  ? null
                  : () => unawaited(controller.refresh()),
              attributes: const <String, String>{
                'data-authoring-action': 'refresh',
              },
            ),
          ],
        ),
        _status(view),
        if (view.pendingContentRefreshDigest != null)
          const StudioFeedbackBanner(
            title: 'Promoção aplicada',
            message:
                'Aguardando a nova geração de conteúdo do Host antes de liberar outra edição.',
            tone: PresentationTone.info,
            live: true,
          ),
        _layoutPanel(view, nodes),
        if (view.comparison case final comparison?)
          _comparisonPanel(comparison),
        if (view.review case final review?) ...<Component>[
          _guidePanel(review),
          if (view.isAuthor) _reviewInputs(view, review),
          _reviewRecord(review),
          _automatedAcceptance(view, review),
          _humanDecisions(view, review),
        ],
        _promotionHistory(view),
        if (_confirmation case final confirmation?)
          _confirmationDialog(view, confirmation),
      ],
    );
  }

  Component _status(ExperienceAuthoringControllerSnapshot view) {
    final (title, message, tone) = switch (view.phase) {
      ExperienceAuthoringControllerPhase.loading => (
        'Carregando estado autoritativo',
        'Consultando o head atual sem solicitar grant.',
        PresentationTone.info,
      ),
      ExperienceAuthoringControllerPhase.submitting => (
        'Aplicando operação',
        'A autorização efêmera será consumida somente pela operação vinculada.',
        PresentationTone.info,
      ),
      ExperienceAuthoringControllerPhase.conflict => (
        'Writer desatualizado',
        'Outro writer venceu o CAS. Atualize antes de tentar novamente.',
        PresentationTone.warning,
      ),
      ExperienceAuthoringControllerPhase.protocolViolation => (
        'Resposta incompatível',
        'O Studio recusou dados que não pertencem à geração ou ao subject atual.',
        PresentationTone.critical,
      ),
      ExperienceAuthoringControllerPhase.transportFailure => (
        'Host indisponível',
        'A operação não pôde ser confirmada. Atualize o estado antes de repetir.',
        PresentationTone.critical,
      ),
      _ when view.isViewer => (
        'Modo Viewer',
        'Layouts promovidos e review estão disponíveis somente para leitura.',
        PresentationTone.info,
      ),
      _ when view.isAuthor => (
        'Modo Author',
        'Cada efeito exige autorização Host-issued imediatamente antes da aplicação.',
        PresentationTone.positive,
      ),
      _ => (
        'Authoring não suportado',
        'O Host não publicou a capability para este subject.',
        PresentationTone.warning,
      ),
    };
    return StudioFeedbackBanner(
      title: title,
      message: view.failureCode == null
          ? message
          : '$message Código tipado: ${view.failureCode!.name}.',
      tone: tone,
      live: true,
      action: view.phase == ExperienceAuthoringControllerPhase.conflict
          ? StudioButton(
              label: 'Recarregar head',
              kind: StudioButtonKind.secondary,
              onPressed: () => unawaited(_controller!.refresh()),
              attributes: const <String, String>{
                'data-authoring-action': 'resolve-stale',
              },
            )
          : null,
    );
  }

  Component _layoutPanel(
    ExperienceAuthoringControllerSnapshot view,
    List<ExperienceAuthoringNodeView> nodes,
  ) {
    final draft = view.draft;
    final canEdit = view.isAuthor && draft != null && !view.busy;
    final canMove = canEdit && view.allows(AuthoringOperation.moveNode);
    return StudioPanel(
      title: draft == null ? 'Layout publicado' : 'Draft de layout',
      description: draft == null
          ? 'Frames da geração v2 atualmente aberta.'
          : 'Revisão ${draft.revision}, posição ${draft.cursor} de ${draft.historyLength}.',
      classes: 'authoring-layout',
      actions: view.isAuthor
          ? <Component>[
              if (draft == null)
                StudioButton(
                  label: 'Iniciar draft',
                  disabled:
                      view.busy || !view.allows(AuthoringOperation.openDraft),
                  onPressed:
                      view.busy || !view.allows(AuthoringOperation.openDraft)
                      ? null
                      : () => unawaited(_controller!.openDraft()),
                  attributes: const <String, String>{
                    'data-authoring-action': 'open-draft',
                  },
                )
              else ...<Component>[
                StudioButton(
                  label: 'Desfazer',
                  kind: StudioButtonKind.quiet,
                  disabled:
                      !canEdit ||
                      !draft.canUndo ||
                      !view.allows(AuthoringOperation.undo),
                  onPressed:
                      !canEdit ||
                          !draft.canUndo ||
                          !view.allows(AuthoringOperation.undo)
                      ? null
                      : () => unawaited(_controller!.undo()),
                  attributes: const <String, String>{
                    'data-authoring-action': 'undo',
                  },
                ),
                StudioButton(
                  label: 'Refazer',
                  kind: StudioButtonKind.quiet,
                  disabled:
                      !canEdit ||
                      !draft.canRedo ||
                      !view.allows(AuthoringOperation.redo),
                  onPressed:
                      !canEdit ||
                          !draft.canRedo ||
                          !view.allows(AuthoringOperation.redo)
                      ? null
                      : () => unawaited(_controller!.redo()),
                  attributes: const <String, String>{
                    'data-authoring-action': 'redo',
                  },
                ),
                StudioButton(
                  label: 'Resetar',
                  kind: StudioButtonKind.secondary,
                  disabled:
                      !canEdit ||
                      !draft.canReset ||
                      !view.allows(AuthoringOperation.reset),
                  onPressed:
                      !canEdit ||
                          !draft.canReset ||
                          !view.allows(AuthoringOperation.reset)
                      ? null
                      : () => unawaited(_controller!.reset()),
                  attributes: const <String, String>{
                    'data-authoring-action': 'reset',
                  },
                ),
                StudioButton(
                  label: 'Reiniciar draft',
                  kind: StudioButtonKind.danger,
                  disabled:
                      view.busy ||
                      !view.allows(AuthoringOperation.abandonDraft) ||
                      !view.allows(AuthoringOperation.openDraft),
                  onPressed:
                      view.busy ||
                          !view.allows(AuthoringOperation.abandonDraft) ||
                          !view.allows(AuthoringOperation.openDraft)
                      ? null
                      : () => setState(
                          () => _confirmation = _AuthoringConfirmation.restart,
                        ),
                  attributes: const <String, String>{
                    'data-authoring-action': 'restart-draft',
                  },
                ),
                StudioButton(
                  label: 'Preparar review',
                  disabled:
                      !canEdit ||
                      !draft.changed ||
                      !view.allows(AuthoringOperation.prepareReview),
                  onPressed:
                      !canEdit ||
                          !draft.changed ||
                          !view.allows(AuthoringOperation.prepareReview)
                      ? null
                      : () => unawaited(_controller!.prepareReview()),
                  attributes: const <String, String>{
                    'data-authoring-action': 'prepare-review',
                  },
                ),
              ],
            ]
          : const <Component>[],
      children: <Component>[
        p(classes: 'authoring-layout__hint', <Component>[
          Component.text(
            canMove
                ? 'Use os botões direcionais ou informe X e Y. Nenhuma ação depende de arrastar.'
                : 'Posições em unidades lógicas do ProjectionLayoutManifest.',
          ),
        ]),
        div(classes: 'authoring-node-grid', <Component>[
          for (final node in nodes) _nodeCard(node, canMove),
        ]),
      ],
    );
  }

  Component _nodeCard(ExperienceAuthoringNodeView node, bool canEdit) {
    final key = node.id.value;
    final xValue = _xInputs[key] ?? _number(node.x);
    final yValue = _yInputs[key] ?? _number(node.y);
    final x = double.tryParse(xValue);
    final y = double.tryParse(yValue);
    final coordinatesValid =
        x != null &&
        y != null &&
        _validAuthoringCoordinate(x) &&
        _validAuthoringCoordinate(y);
    return article(
      classes: 'authoring-node${node.changed ? ' is-changed' : ''}',
      attributes: <String, String>{
        'data-authoring-node': node.id.value,
        'data-authoring-node-changed': '${node.changed}',
      },
      <Component>[
        header(<Component>[
          div(<Component>[
            strong(<Component>[Component.text(node.scenarioTitle)]),
            small(<Component>[Component.text(node.id.value)]),
          ]),
          if (node.changed)
            const StudioStatusPill(
              label: 'Alterado',
              tone: PresentationTone.warning,
            ),
        ]),
        p(<Component>[
          Component.text(
            'X ${_number(node.x)} · Y ${_number(node.y)} · ${_number(node.width)} × ${_number(node.height)}',
          ),
        ]),
        if (canEdit) ...<Component>[
          div(
            classes: 'authoring-direction-controls',
            attributes: <String, String>{
              'role': 'group',
              'aria-label': 'Mover ${node.scenarioTitle} em incrementos',
            },
            <Component>[
              _moveButton(node, 'Esquerda', dx: -20, dy: 0),
              _moveButton(node, 'Cima', dx: 0, dy: -20),
              _moveButton(node, 'Baixo', dx: 0, dy: 20),
              _moveButton(node, 'Direita', dx: 20, dy: 0),
            ],
          ),
          div(classes: 'authoring-coordinate-form', <Component>[
            StudioTextInput(
              id: 'authoring-${_safeId(key)}-x',
              label: 'Coordenada X',
              value: xValue,
              hint: 'Entre -1.000.000 e 1.000.000',
              onInput: (value) => setState(() => _xInputs[key] = value),
            ),
            StudioTextInput(
              id: 'authoring-${_safeId(key)}-y',
              label: 'Coordenada Y',
              value: yValue,
              hint: 'Entre -1.000.000 e 1.000.000',
              onInput: (value) => setState(() => _yInputs[key] = value),
            ),
            StudioButton(
              label: 'Aplicar coordenadas',
              kind: StudioButtonKind.secondary,
              disabled: !coordinatesValid || _view!.busy,
              onPressed: !coordinatesValid || _view!.busy
                  ? null
                  : () {
                      _xInputs.remove(key);
                      _yInputs.remove(key);
                      unawaited(_controller!.moveNode(node.id, toX: x, toY: y));
                    },
              attributes: <String, String>{
                'data-authoring-action': 'move-node-coordinates',
                'data-authoring-node': node.id.value,
              },
            ),
          ]),
        ],
      ],
    );
  }

  Component _moveButton(
    ExperienceAuthoringNodeView node,
    String label, {
    required double dx,
    required double dy,
  }) => StudioButton(
    label: label,
    kind: StudioButtonKind.quiet,
    disabled: _view!.busy,
    onPressed: _view!.busy
        ? null
        : () => unawaited(_controller!.moveNodeBy(node.id, dx: dx, dy: dy)),
    attributes: <String, String>{
      'data-authoring-action': 'move-node-${label.toLowerCase()}',
      'data-authoring-node': node.id.value,
    },
  );

  Component _comparisonPanel(
    ExperienceAuthoringComparisonView comparison,
  ) => StudioPanel(
    title: 'Comparison e ChangeSet',
    description:
        '${comparison.changedFrames.length} frame(s) alterado(s) no par validado.',
    classes: 'authoring-comparison',
    children: <Component>[
      div(classes: 'authoring-table-scroll', <Component>[
        table(<Component>[
          thead(<Component>[
            tr(<Component>[
              th(scope: 'col', <Component>[const Component.text('Node')]),
              th(scope: 'col', <Component>[const Component.text('Antes')]),
              th(scope: 'col', <Component>[const Component.text('Depois')]),
            ]),
          ]),
          tbody(<Component>[
            for (final frame in comparison.changedFrames)
              tr(<Component>[
                th(scope: 'row', <Component>[
                  Component.text(frame.nodeInstanceId.value),
                ]),
                td(<Component>[
                  Component.text(
                    'X ${_number(frame.beforeX)}, Y ${_number(frame.beforeY)}',
                  ),
                ]),
                td(<Component>[
                  Component.text(
                    'X ${_number(frame.afterX)}, Y ${_number(frame.afterY)}',
                  ),
                ]),
              ]),
          ]),
        ]),
      ]),
    ],
  );

  Component _guidePanel(ExperienceAuthoringReviewView review) => StudioPanel(
    title: 'ReviewGuide · ${review.guide.title}',
    description:
        'Step ${review.guide.stepId} para ${review.guide.scenarioId.value}.',
    classes: 'authoring-review-guide',
    children: <Component>[
      p(
        attributes: const <String, String>{
          'data-authoring-review-instruction': 'true',
        },
        <Component>[Component.text(review.guide.instruction)],
      ),
      p(<Component>[
        strong(<Component>[const Component.text('Critério: ')]),
        Component.text(review.guide.observationCriteria),
      ]),
      if (review.guide.labRoute case final route?)
        Link(
          to: route,
          classes: 'studio-ui-button studio-ui-button--secondary',
          attributes: const <String, String>{
            'data-authoring-review-guide-link': 'true',
          },
          child: const Component.text('Executar cenário no Lab'),
        )
      else
        const StudioFeedbackBanner(
          title: 'Execução indisponível',
          message:
              'Nenhuma rota Lab única corresponde ao binding tipado deste step.',
          tone: PresentationTone.warning,
        ),
    ],
  );

  Component _reviewInputs(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) => div(classes: 'authoring-review-inputs', <Component>[
    _findingForm(view, review),
    _conceptForm(view, review),
    _commentForm(view, review),
  ]);

  Component _findingForm(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) {
    final subject = review.subjectOptions
        .where((item) => item.key == _findingSubject)
        .singleOrNull;
    final canSubmit =
        !view.busy &&
        view.allows(AuthoringOperation.appendFinding) &&
        subject != null &&
        _validAuthoringText(_findingSummary.trim(), 512) &&
        _validAuthoringText(_findingDetail.trim(), 2048) &&
        review.findings.length < experienceAuthoringMaxFindings;
    return StudioPanel(
      title: 'Registrar finding',
      description:
          'O subject é sempre scenario, transition ou artifact catalogado.',
      classes: 'authoring-review-form',
      children: <Component>[
        StudioSelect(
          id: 'authoring-finding-subject',
          label: 'Subject do finding',
          value: _findingSubject,
          options: <StudioSelectOption>[
            for (final option in review.subjectOptions)
              StudioSelectOption(value: option.key, label: option.label),
          ],
          onChange: (value) => setState(() => _findingSubject = value),
        ),
        StudioSelect(
          id: 'authoring-finding-severity',
          label: 'Severidade',
          value: _findingSeverity.name,
          options: const <StudioSelectOption>[
            StudioSelectOption(value: 'info', label: 'Informativa'),
            StudioSelectOption(value: 'warning', label: 'Atenção'),
            StudioSelectOption(value: 'blocking', label: 'Bloqueante'),
          ],
          onChange: (value) => setState(
            () => _findingSeverity = ExperienceFindingSeverity.values
                .firstWhere((item) => item.name == value),
          ),
        ),
        StudioTextInput(
          id: 'authoring-finding-summary',
          label: 'Resumo',
          value: _findingSummary,
          hint: 'Até 512 bytes em UTF-8',
          onInput: (value) => setState(() => _findingSummary = value),
        ),
        StudioTextInput(
          id: 'authoring-finding-detail',
          label: 'Detalhe',
          value: _findingDetail,
          hint: 'Até 2.048 bytes em UTF-8',
          onInput: (value) => setState(() => _findingDetail = value),
        ),
        StudioButton(
          label: 'Adicionar finding',
          disabled: !canSubmit,
          onPressed: !canSubmit
              ? null
              : () {
                  unawaited(
                    _controller!.appendFinding(
                      subject: subject.subject,
                      severity: _findingSeverity,
                      summary: _findingSummary.trim(),
                      detail: _findingDetail.trim(),
                    ),
                  );
                  setState(() {
                    _findingSummary = '';
                    _findingDetail = '';
                  });
                },
          attributes: const <String, String>{
            'data-authoring-action': 'append-finding',
          },
        ),
      ],
    );
  }

  Component _conceptForm(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) {
    final canSubmit =
        !view.busy &&
        view.allows(AuthoringOperation.proposeConcept) &&
        _validAuthoringText(_conceptTitle.trim(), 256) &&
        _validAuthoringText(_conceptRationale.trim(), 1024) &&
        review.concepts.length < experienceAuthoringMaxConcepts;
    return StudioPanel(
      title: 'Propor conceito',
      description:
          'Novo Scenario sintético com lifecycle explicitamente concept.',
      classes: 'authoring-review-form',
      children: <Component>[
        StudioDefinitionList(
          items: <(String, String)>[
            ('Lifecycle', ScenarioLifecycle.concept.name),
            ('Scenario proposto', review.syntheticConceptScenarioId.value),
          ],
        ),
        StudioTextInput(
          id: 'authoring-concept-title',
          label: 'Título do conceito',
          value: _conceptTitle,
          hint: 'Até 256 bytes em UTF-8',
          onInput: (value) => setState(() => _conceptTitle = value),
        ),
        StudioTextInput(
          id: 'authoring-concept-rationale',
          label: 'Racional',
          value: _conceptRationale,
          hint: 'Até 1.024 bytes em UTF-8',
          onInput: (value) => setState(() => _conceptRationale = value),
        ),
        StudioButton(
          label: 'Propor concept',
          disabled: !canSubmit,
          onPressed: !canSubmit
              ? null
              : () {
                  unawaited(
                    _controller!.proposeConcept(
                      title: _conceptTitle.trim(),
                      rationale: _conceptRationale.trim(),
                    ),
                  );
                  setState(() {
                    _conceptTitle = '';
                    _conceptRationale = '';
                  });
                },
          attributes: const <String, String>{
            'data-authoring-action': 'propose-concept',
          },
        ),
      ],
    );
  }

  Component _commentForm(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) {
    final subject = review.subjectOptions
        .where((item) => item.key == _commentSubject)
        .singleOrNull;
    final canSubmit =
        !view.busy &&
        view.allows(AuthoringOperation.appendComment) &&
        subject != null &&
        _validAuthoringText(_commentBody.trim(), 1024) &&
        review.comments.length < experienceAuthoringMaxComments;
    return StudioPanel(
      title: 'Comentar review',
      description: 'Comentários são append-only e vinculados ao subject.',
      classes: 'authoring-review-form',
      children: <Component>[
        StudioSelect(
          id: 'authoring-comment-subject',
          label: 'Subject do comentário',
          value: _commentSubject,
          options: <StudioSelectOption>[
            for (final option in review.subjectOptions)
              StudioSelectOption(value: option.key, label: option.label),
          ],
          onChange: (value) => setState(() => _commentSubject = value),
        ),
        StudioTextInput(
          id: 'authoring-comment-body',
          label: 'Comentário',
          value: _commentBody,
          hint: 'Até 1.024 bytes em UTF-8',
          onInput: (value) => setState(() => _commentBody = value),
        ),
        StudioButton(
          label: 'Adicionar comentário',
          disabled: !canSubmit,
          onPressed: !canSubmit
              ? null
              : () {
                  unawaited(
                    _controller!.appendComment(
                      subject: subject.subject,
                      body: _commentBody.trim(),
                    ),
                  );
                  setState(() => _commentBody = '');
                },
          attributes: const <String, String>{
            'data-authoring-action': 'append-comment',
          },
        ),
      ],
    );
  }

  Component _reviewRecord(ExperienceAuthoringReviewView review) => StudioPanel(
    title: 'Review materializado',
    description:
        '${review.findings.length} finding(s), ${review.concepts.length} conceito(s) e ${review.comments.length} comentário(s).',
    classes: 'authoring-review-record',
    children: <Component>[
      if (review.findings.isNotEmpty) ...<Component>[
        h3(<Component>[const Component.text('Findings')]),
        ol(<Component>[
          for (final finding in review.findings)
            li(<Component>[
              strong(<Component>[Component.text(finding.summary)]),
              p(<Component>[
                Component.text(
                  '${finding.subjectLabel} · ${finding.severity.name}',
                ),
              ]),
              p(<Component>[Component.text(finding.detail)]),
            ]),
        ]),
      ],
      if (review.concepts.isNotEmpty) ...<Component>[
        h3(<Component>[const Component.text('Conceitos propostos')]),
        ol(<Component>[
          for (final concept in review.concepts)
            li(<Component>[
              strong(<Component>[Component.text(concept.title)]),
              p(<Component>[
                Component.text(
                  '${concept.scenarioId.value} · lifecycle ${concept.lifecycle.name}',
                ),
              ]),
              p(<Component>[Component.text(concept.rationale)]),
            ]),
        ]),
      ],
      if (review.comments.isNotEmpty) ...<Component>[
        h3(<Component>[const Component.text('Comentários')]),
        ol(<Component>[
          for (final comment in review.comments)
            li(<Component>[
              strong(<Component>[
                Component.text(
                  '#${comment.sequence} · ${comment.subjectLabel}',
                ),
              ]),
              p(<Component>[Component.text(comment.body)]),
            ]),
        ]),
      ],
    ],
  );

  Component _automatedAcceptance(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) {
    final acceptance = review.automatedAcceptance;
    return StudioPanel(
      title: 'Automated acceptance',
      description:
          'Resultado automatizado separado da decisão humana append-only.',
      classes: 'authoring-automated-acceptance',
      actions: view.isAuthor && acceptance == null
          ? <Component>[
              StudioButton(
                label: 'Executar avaliação',
                kind: StudioButtonKind.secondary,
                disabled:
                    view.busy ||
                    !view.allows(
                      AuthoringOperation.evaluateAutomatedAcceptance,
                    ),
                onPressed:
                    view.busy ||
                        !view.allows(
                          AuthoringOperation.evaluateAutomatedAcceptance,
                        )
                    ? null
                    : () =>
                          unawaited(_controller!.evaluateAutomatedAcceptance()),
                attributes: const <String, String>{
                  'data-authoring-action': 'evaluate-acceptance',
                },
              ),
            ]
          : const <Component>[],
      children: <Component>[
        if (acceptance == null)
          const p(<Component>[
            Component.text('Ainda não há resultado automatizado.'),
          ])
        else
          StudioFeedbackBanner(
            title: acceptance.outcome == AutomatedAcceptanceOutcome.passed
                ? 'Automated acceptance passou'
                : 'Automated acceptance falhou',
            message: acceptance.summary,
            tone: acceptance.outcome == AutomatedAcceptanceOutcome.passed
                ? PresentationTone.positive
                : PresentationTone.critical,
          ),
      ],
    );
  }

  Component _humanDecisions(
    ExperienceAuthoringControllerSnapshot view,
    ExperienceAuthoringReviewView review,
  ) {
    final hasAcceptance = review.automatedAcceptance != null;
    final validRationale = _validAuthoringText(_decisionRationale.trim(), 1024);
    return StudioPanel(
      title: 'Decisões humanas',
      description:
          'Cada decisão é anexada. Uma nova decisão substitui a anterior sem apagá-la.',
      classes: 'authoring-human-decisions',
      actions: view.isAuthor
          ? <Component>[
              StudioButton(
                label: 'Rejeitar',
                kind: StudioButtonKind.danger,
                disabled:
                    view.busy ||
                    !hasAcceptance ||
                    !validRationale ||
                    !view.allows(AuthoringOperation.decideReview),
                onPressed:
                    view.busy ||
                        !hasAcceptance ||
                        !validRationale ||
                        !view.allows(AuthoringOperation.decideReview)
                    ? null
                    : () => setState(
                        () => _confirmation = _AuthoringConfirmation.reject,
                      ),
                attributes: const <String, String>{
                  'data-authoring-action': 'reject',
                },
              ),
              StudioButton(
                label: 'Aprovar',
                disabled:
                    view.busy ||
                    !hasAcceptance ||
                    !validRationale ||
                    !view.allows(AuthoringOperation.decideReview),
                onPressed:
                    view.busy ||
                        !hasAcceptance ||
                        !validRationale ||
                        !view.allows(AuthoringOperation.decideReview)
                    ? null
                    : () => setState(
                        () => _confirmation = _AuthoringConfirmation.approve,
                      ),
                attributes: const <String, String>{
                  'data-authoring-action': 'approve',
                },
              ),
              StudioButton(
                label: 'Promover',
                kind: StudioButtonKind.primary,
                disabled:
                    view.busy ||
                    !review.promotable ||
                    !view.allows(AuthoringOperation.promote),
                onPressed:
                    view.busy ||
                        !review.promotable ||
                        !view.allows(AuthoringOperation.promote)
                    ? null
                    : () => setState(
                        () => _confirmation = _AuthoringConfirmation.promote,
                      ),
                attributes: const <String, String>{
                  'data-authoring-action': 'promote',
                },
              ),
            ]
          : const <Component>[],
      children: <Component>[
        if (view.isAuthor)
          StudioTextInput(
            id: 'authoring-decision-rationale',
            label: 'Racional da próxima decisão',
            value: _decisionRationale,
            hint: 'Até 1.024 bytes em UTF-8',
            onInput: (value) => setState(() => _decisionRationale = value),
          ),
        if (review.decisions.isEmpty)
          const p(<Component>[
            Component.text('Nenhuma decisão humana registrada.'),
          ])
        else
          ol(classes: 'authoring-decision-list', <Component>[
            for (final decision in review.decisions)
              li(
                classes: decision.isHead ? 'is-head' : 'is-superseded',
                attributes: <String, String>{
                  'data-authoring-decision': decision.decision.name,
                  'data-authoring-decision-state': decision.isHead
                      ? 'head'
                      : 'superseded',
                },
                <Component>[
                  strong(<Component>[
                    Component.text(
                      '#${decision.sequence} · ${decision.decision.name}',
                    ),
                  ]),
                  StudioStatusPill(
                    label: decision.isHead ? 'Head' : 'Substituída',
                    tone: decision.isHead
                        ? PresentationTone.accent
                        : PresentationTone.neutral,
                  ),
                  p(<Component>[Component.text(decision.rationale)]),
                ],
              ),
          ]),
      ],
    );
  }

  Component _promotionHistory(ExperienceAuthoringControllerSnapshot view) {
    final visiblePromotions = view.promotions.isNotEmpty
        ? view.promotions
        : <ExperiencePromotionView>[?view.latestPromotion];
    final totalCount = view.promotionTotalCount;
    return StudioPanel(
      title: 'Histórico de promoções',
      description: totalCount == null
          ? 'Último receipt reaberto pelo subject head.'
          : view.promotionHistoryTruncated
          ? 'Mostrando ${visiblePromotions.length} promoções mais recentes de $totalCount.'
          : 'Mostrando ${visiblePromotions.length} de $totalCount promoções.',
      classes: 'authoring-promotion-history',
      children: <Component>[
        if (visiblePromotions.isEmpty)
          const p(<Component>[Component.text('Nenhuma promoção publicada.')])
        else
          ol(<Component>[
            for (final promotion in visiblePromotions)
              li(<Component>[
                strong(<Component>[
                  Component.text('Promoção ${promotion.sequence}'),
                ]),
                p(<Component>[Component.text(_time(promotion.promotedAt))]),
              ]),
          ]),
      ],
    );
  }

  Component _confirmationDialog(
    ExperienceAuthoringControllerSnapshot view,
    _AuthoringConfirmation confirmation,
  ) {
    final (title, description, confirmLabel, danger) = switch (confirmation) {
      _AuthoringConfirmation.restart => (
        'Reiniciar o draft?',
        'O draft atual será abandonado antes da abertura de um novo head.',
        'Reiniciar draft',
        true,
      ),
      _AuthoringConfirmation.reject => (
        'Registrar rejeição?',
        'A decisão será anexada ao histórico e poderá ser substituída por uma aprovação.',
        'Confirmar rejeição',
        true,
      ),
      _AuthoringConfirmation.approve => (
        'Registrar aprovação?',
        'A decisão será anexada como novo head humano do review.',
        'Confirmar aprovação',
        false,
      ),
      _AuthoringConfirmation.promote => (
        'Promover esta revisão?',
        'O Host aceitará somente automated acceptance passed e aprovação humana no head.',
        'Confirmar promoção',
        false,
      ),
    };
    return StudioDialog(
      id: 'experience-authoring-confirmation',
      title: title,
      description: description,
      onDismiss: () => setState(() => _confirmation = null),
      actions: <Component>[
        StudioButton(
          label: 'Cancelar',
          kind: StudioButtonKind.quiet,
          disabled: view.busy,
          onPressed: view.busy
              ? null
              : () => setState(() => _confirmation = null),
          attributes: const <String, String>{
            'data-authoring-confirmation': 'cancel',
          },
        ),
        StudioButton(
          label: confirmLabel,
          kind: danger ? StudioButtonKind.danger : StudioButtonKind.primary,
          autofocus: true,
          disabled: view.busy,
          onPressed: view.busy ? null : () => _confirm(confirmation),
          attributes: <String, String>{
            'data-authoring-confirmation': confirmation.name,
          },
        ),
      ],
    );
  }

  void _confirm(_AuthoringConfirmation confirmation) {
    setState(() => _confirmation = null);
    switch (confirmation) {
      case _AuthoringConfirmation.restart:
        unawaited(_controller!.restartDraft());
      case _AuthoringConfirmation.reject:
        unawaited(
          _controller!.decide(
            decision: ExperienceHumanDecision.reject,
            rationale: _decisionRationale.trim(),
          ),
        );
        setState(() => _decisionRationale = '');
      case _AuthoringConfirmation.approve:
        unawaited(
          _controller!.decide(
            decision: ExperienceHumanDecision.approve,
            rationale: _decisionRationale.trim(),
          ),
        );
        setState(() => _decisionRationale = '');
      case _AuthoringConfirmation.promote:
        unawaited(_controller!.promote());
    }
  }
}

bool _sameMethods(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _time(DateTime value) => value.toUtc().toIso8601String();

String _safeId(String value) => value.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '-');

bool _validAuthoringCoordinate(double value) =>
    value.isFinite &&
    !(value == 0 && value.isNegative) &&
    value >= -1000000 &&
    value <= 1000000;

bool _validAuthoringText(String value, int maxBytes) =>
    value.trim().isNotEmpty && utf8.encode(value).length <= maxBytes;
