import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio_ui/studio_ui.dart';

final class MotionPage extends StatefulComponent {
  const MotionPage({
    required this.enabled,
    required this.projectionId,
    required this.bundle,
    required this.motion,
    this.scenarioId,
    super.key,
  });

  final bool enabled;
  final ExperienceProjectionId projectionId;
  final ExperienceTopologyBundle? bundle;
  final MotionManifest? motion;
  final ScenarioId? scenarioId;

  @override
  State<MotionPage> createState() => _MotionPageState();
}

final class _MotionPageState extends State<MotionPage> {
  MotionMode _mode = MotionMode.full;
  String? _lastPlayback;

  @override
  Component build(BuildContext context) {
    final bundle = component.bundle;
    final motion = component.motion;
    final sequence = motion?.sequences
        .where((item) => item.projectionId == component.projectionId)
        .firstOrNull;
    if (!component.enabled ||
        bundle == null ||
        motion == null ||
        sequence == null) {
      return const StudioEmptyState(
        title: 'Motion indisponível',
        message:
            'O plano atual não publicou uma sequência Motion cercada ao conteúdo Experience.',
        tone: PresentationTone.warning,
      );
    }
    final selectedScenario = component.scenarioId;
    final contextUrl = Uri(
      path: '/context/${component.projectionId.value}',
      queryParameters: selectedScenario == null
          ? null
          : <String, String>{'scenarioId': selectedScenario.value},
    ).toString();
    return section(
      classes: 'motion-page page-stack',
      attributes: <String, String>{
        'data-motion-mode': _mode.name,
        'data-motion-digest': motion.digest.value,
      },
      <Component>[
        const StudioPageHeader(
          eyebrow: 'MOTION',
          title: 'Sequências temporais',
          description:
              'Inspecione scripts e observações em full, reduced ou none sem esconder o equivalente estático.',
        ),
        div(classes: 'motion-toolbar studio-ui-panel', <Component>[
          div(classes: 'studio-ui-panel__body motion-mode-group', <Component>[
            for (final mode in MotionMode.values)
              StudioButton(
                label: switch (mode) {
                  MotionMode.full => 'Full',
                  MotionMode.reduced => 'Reduced',
                  MotionMode.none => 'None',
                },
                kind: _mode == mode
                    ? StudioButtonKind.primary
                    : StudioButtonKind.secondary,
                attributes: <String, String>{
                  'data-motion-action': 'mode-${mode.name}',
                },
                onPressed: () => setState(() {
                  _mode = mode;
                  _lastPlayback = null;
                }),
              ),
            StudioButton(
              label: 'Executar sequência',
              kind: StudioButtonKind.primary,
              attributes: const <String, String>{'data-motion-action': 'play'},
              onPressed: () => setState(() {
                _lastPlayback =
                    '${sequence.steps.length} etapas · ${sequence.totalDurationFor(_mode)} ms';
              }),
            ),
            Link(
              to: contextUrl,
              classes: 'studio-ui-button studio-ui-button--secondary',
              child: const Component.text('Usar seleção no Context Builder'),
            ),
          ]),
        ]),
        article(classes: 'studio-ui-panel motion-static-equivalent', <
          Component
        >[
          div(classes: 'studio-ui-panel__body', <Component>[
            h2(<Component>[Component.text(sequence.title)]),
            p(<Component>[Component.text(sequence.staticSummary)]),
            p(classes: 'motion-comprehension-proof', <Component>[
              const Component.text(
                'Compreensão preservada: o movimento não contém informação exclusiva.',
              ),
            ]),
            if (_lastPlayback case final playback?)
              p(
                attributes: const <String, String>{'role': 'status'},
                <Component>[Component.text('Execução observada: $playback')],
              ),
          ]),
        ]),
        ol(classes: 'motion-script', <Component>[
          for (final step in sequence.steps)
            li(classes: 'studio-ui-panel motion-step', <Component>[
              div(classes: 'studio-ui-panel__body', <Component>[
                h3(<Component>[Component.text(step.id)]),
                p(<Component>[
                  Component.text(
                    '${step.fromNodeId.value} → ${step.toNodeId.value} · '
                    '${step.durationFor(_mode)} ms · ${step.easing.name}',
                  ),
                ]),
                ul(classes: 'motion-observations', <Component>[
                  for (final observation in step.observations)
                    li(<Component>[
                      strong(<Component>[
                        Component.text(observation.kind.name),
                      ]),
                      Component.text(' — ${observation.label}'),
                    ]),
                ]),
              ]),
            ]),
        ]),
      ],
    );
  }
}

final class ContextBuilderPage extends StatefulComponent {
  const ContextBuilderPage({
    required this.enabled,
    required this.contentSetDigest,
    required this.selection,
    required this.client,
    super.key,
  });

  final bool enabled;
  final Digest? contentSetDigest;
  final ContextSelection? selection;
  final StudioHostContextBuilderClient? client;

  @override
  State<ContextBuilderPage> createState() => _ContextBuilderPageState();
}

final class _ContextBuilderPageState extends State<ContextBuilderPage> {
  ContextBuilderDescription? _description;
  ExperienceContextBundle? _bundle;
  String? _failure;
  var _busy = false;
  var _includeSources = true;
  var _includeImages = true;
  var _includeEvidence = true;
  var _includeHistory = true;
  var _includeChanges = true;

  @override
  void initState() {
    super.initState();
    unawaited(_describe());
  }

  @override
  void didUpdateComponent(ContextBuilderPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.client != component.client ||
        oldComponent.contentSetDigest != component.contentSetDigest ||
        oldComponent.selection?.toJson().toString() !=
            component.selection?.toJson().toString()) {
      _description = null;
      _bundle = null;
      _failure = null;
      unawaited(_describe());
    }
  }

  Future<void> _describe() async {
    final client = component.client;
    if (!component.enabled || client == null) return;
    try {
      final description = await client.describeContextBuilder();
      if (!mounted ||
          description.contentSetDigest != component.contentSetDigest) {
        return;
      }
      setState(() => _description = description);
    } on Object {
      if (mounted) setState(() => _failure = 'Context Builder indisponível.');
    }
  }

  Future<void> _build() async {
    final client = component.client;
    final contentSetDigest = component.contentSetDigest;
    final selection = component.selection;
    final description = _description;
    if (client == null ||
        contentSetDigest == null ||
        selection == null ||
        description == null ||
        _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final result = await client.buildContext(
        ContextBuildRequest(
          expectedContentSetDigest: contentSetDigest,
          selection: selection,
          inclusion: ContextInclusion(
            sources: _includeSources,
            images: _includeImages,
            evidence: _includeEvidence,
            history: _includeHistory,
            changes: _includeChanges,
          ),
          budgets: _requestedBudgets(description.maximumBudgets),
        ),
      );
      if (!mounted || result.bundle.contentSetDigest != contentSetDigest) {
        return;
      }
      setState(() => _bundle = result.bundle);
    } on Object {
      if (mounted) {
        setState(() => _failure = 'O export foi rejeitado pelo Host.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.enabled ||
        component.client == null ||
        component.selection == null ||
        component.contentSetDigest == null) {
      return const StudioEmptyState(
        title: 'Context Builder indisponível',
        message:
            'O plano atual não publicou o facade tipado e uma seleção Experience atômica.',
        tone: PresentationTone.warning,
      );
    }
    final description = _description;
    final bundle = _bundle;
    return section(
      classes: 'context-page page-stack',
      attributes: <String, String>{
        'data-context-state': _failure != null
            ? 'failed'
            : bundle != null
            ? 'ready'
            : _busy
            ? 'building'
            : 'idle',
        if (bundle != null) 'data-context-digest': bundle.digest.value,
      },
      <Component>[
        const StudioPageHeader(
          eyebrow: 'CONTEXT BUILDER',
          title: 'Contexto determinístico',
          description:
              'Selecione categorias sem informar paths e veja budget, uso e omissões separadamente.',
        ),
        if (description == null && _failure == null)
          const StudioProgress(label: 'Descrevendo Context Builder'),
        if (_failure case final failure?)
          StudioEmptyState(
            title: 'Export rejeitado',
            message: failure,
            tone: PresentationTone.critical,
          ),
        if (description != null) ...<Component>[
          div(classes: 'studio-ui-panel', <Component>[
            div(classes: 'studio-ui-panel__body context-selection', <Component>[
              p(<Component>[
                strong(<Component>[const Component.text('Seleção: ')]),
                Component.text(_selectionLabel(component.selection!)),
              ]),
              div(classes: 'context-inclusions', <Component>[
                _toggle(
                  ContextCategory.sources,
                  'Fontes',
                  _includeSources,
                  (value) => _includeSources = value,
                ),
                _toggle(
                  ContextCategory.images,
                  'Imagens',
                  _includeImages,
                  (value) => _includeImages = value,
                ),
                _toggle(
                  ContextCategory.evidence,
                  'Evidências',
                  _includeEvidence,
                  (value) => _includeEvidence = value,
                ),
                _toggle(
                  ContextCategory.history,
                  'História',
                  _includeHistory,
                  (value) => _includeHistory = value,
                ),
                _toggle(
                  ContextCategory.changes,
                  'Mudanças',
                  _includeChanges,
                  (value) => _includeChanges = value,
                ),
              ]),
              StudioButton(
                label: _busy ? 'Exportando…' : 'Exportar contexto',
                kind: StudioButtonKind.primary,
                disabled: _busy,
                attributes: const <String, String>{
                  'data-context-action': 'export',
                },
                onPressed: _busy ? null : _build,
              ),
            ]),
          ]),
          div(classes: 'context-budget-grid', <Component>[
            for (final category in ContextCategory.values)
              article(classes: 'studio-ui-panel context-budget', <Component>[
                div(classes: 'studio-ui-panel__body', <Component>[
                  h3(<Component>[Component.text(category.name)]),
                  p(<Component>[
                    Component.text(
                      'budget ${description.maximumBudgets[category].maxItems} itens / '
                      '${description.maximumBudgets[category].maxBytes} bytes',
                    ),
                  ]),
                  if (bundle != null)
                    p(<Component>[
                      Component.text(
                        'uso ${bundle.usage[category]!.items} itens / '
                        '${bundle.usage[category]!.bytes} bytes',
                      ),
                    ]),
                ]),
              ]),
          ]),
        ],
        if (bundle != null) ...<Component>[
          article(classes: 'studio-ui-panel context-result', <Component>[
            div(classes: 'studio-ui-panel__body', <Component>[
              h2(<Component>[const Component.text('Export sanitizado')]),
              p(<Component>[Component.text('Digest ${bundle.digest.value}')]),
              p(<Component>[
                Component.text(
                  '${bundle.items.length} itens · ${bundle.omissions.length} omissões declaradas',
                ),
              ]),
              ul(classes: 'context-items', <Component>[
                for (final item in bundle.items)
                  li(<Component>[
                    strong(<Component>[Component.text(item.category.name)]),
                    Component.text(' · ${item.id} · ${item.byteLength} bytes'),
                  ]),
              ]),
              ul(classes: 'context-omissions', <Component>[
                for (final omission in bundle.omissions)
                  li(<Component>[
                    Component.text(
                      '${omission.category.name} · ${omission.subject} · ${omission.reason.name}',
                    ),
                  ]),
              ]),
            ]),
          ]),
        ],
      ],
    );
  }

  Component _toggle(
    ContextCategory category,
    String labelText,
    bool value,
    void Function(bool) update,
  ) => label(classes: 'context-toggle', <Component>[
    input<bool>(
      type: InputType.checkbox,
      checked: value,
      attributes: <String, String>{'data-context-category': category.name},
      onChange: (checked) => setState(() => update(checked)),
    ),
    Component.text(labelText),
  ]);
}

ContextBudgets _requestedBudgets(ContextBudgets maximum) => ContextBudgets(
  categories: <ContextCategory, ContextCategoryBudget>{
    for (final category in ContextCategory.values)
      category: ContextCategoryBudget(
        maxItems: maximum[category].maxItems < 16
            ? maximum[category].maxItems
            : 16,
        maxBytes: maximum[category].maxBytes < 64 * 1024
            ? maximum[category].maxBytes
            : 64 * 1024,
      ),
  },
);

String _selectionLabel(ContextSelection selection) => <String>[
  'board=${selection.boardId.value}',
  'projection=${selection.projectionId.value}',
  if (selection.journeyId != null) 'journey=${selection.journeyId!.value}',
  if (selection.scenarioId != null) 'scenario=${selection.scenarioId!.value}',
  if (selection.changeSetDigest != null) 'changeset=selected',
].join(' · ');
