import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/verified_artifact_image.dart';
import 'package:studio/src/quality/scenario_quality_panel.dart';
import 'package:studio/src/quality/studio_scenario_quality_transport.dart';
import 'package:studio_ui/studio_ui.dart';

import 'scenario_quality_decision_controller.dart';

final class ScenarioQualityDecisionExperience extends StatefulComponent {
  const ScenarioQualityDecisionExperience({
    required this.catalog,
    required this.manifest,
    required this.scenarioId,
    required this.scriptId,
    required this.rpcMethods,
    this.runSnapshot,
    this.runResult,
    this.qualitySnapshot,
    this.currentContentSetDigest,
    this.qualityClient,
    this.resourceClient,
    super.key,
  });

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final Set<String> rpcMethods;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
  final Digest? currentContentSetDigest;
  final StudioHostScenarioQualityClient? qualityClient;
  final StudioHostScenarioQualityResourceClient? resourceClient;

  @override
  State<ScenarioQualityDecisionExperience> createState() =>
      _ScenarioQualityDecisionExperienceState();
}

final class _ScenarioQualityDecisionExperienceState
    extends State<ScenarioQualityDecisionExperience> {
  late ScenarioQualityDecisionController _controller;
  late ScenarioQualityDecisionControllerSnapshot _review;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateComponent(ScenarioQualityDecisionExperience oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.catalog.digest != component.catalog.digest ||
        oldComponent.manifest.digest != component.manifest.digest ||
        oldComponent.runSnapshot?.digest != component.runSnapshot?.digest ||
        oldComponent.runResult?.digest != component.runResult?.digest ||
        oldComponent.currentContentSetDigest !=
            component.currentContentSetDigest ||
        oldComponent.qualityClient != component.qualityClient ||
        oldComponent.resourceClient != component.resourceClient ||
        !_sameMethods(oldComponent.rpcMethods, component.rpcMethods)) {
      _controller.setStateListener(null);
      _controller.close();
      _attachController();
    }
  }

  @override
  void dispose() {
    _controller.setStateListener(null);
    _controller.close();
    super.dispose();
  }

  void _attachController() {
    var protocolViolation = false;
    StudioHostScenarioQualityClient? qualityClient;
    StudioHostScenarioQualityResourceClient? resourceClient;
    try {
      final selected = selectStudioScenarioQualityTransport(
        component.rpcMethods,
      );
      if (selected == StudioScenarioQualityTransportAvailability.available) {
        qualityClient = component.qualityClient;
        resourceClient = component.resourceClient;
        if (qualityClient == null || resourceClient == null) {
          protocolViolation = true;
        }
      }
    } on FormatException {
      protocolViolation = true;
    }
    _controller = ScenarioQualityDecisionController(
      host: qualityClient,
      resourceClient: resourceClient,
      catalog: component.catalog,
      manifest: component.manifest,
      runSnapshot: component.runSnapshot,
      runResult: component.runResult,
      initialProtocolViolation: protocolViolation,
    );
    _review = _controller.snapshot;
    _controller.setStateListener((snapshot) {
      if (mounted) setState(() => _review = snapshot);
    });
    unawaited(_controller.load());
  }

  @override
  Component build(BuildContext context) => ScenarioQualityPanel(
    catalog: component.catalog,
    manifest: component.manifest,
    scenarioId: component.scenarioId,
    scriptId: component.scriptId,
    runSnapshot: component.runSnapshot,
    runResult: component.runResult,
    qualitySnapshot: _review.quality ?? component.qualitySnapshot,
    currentContentSetDigest: component.currentContentSetDigest,
    decisionControls: _reviewControls(),
  );

  Component _reviewControls() {
    final busy = const <ScenarioQualityDecisionOperationState>{
      ScenarioQualityDecisionOperationState.loading,
      ScenarioQualityDecisionOperationState.submitting,
    }.contains(_review.operation);
    final failed = const <ScenarioQualityDecisionOperationState>{
      ScenarioQualityDecisionOperationState.conflict,
      ScenarioQualityDecisionOperationState.protocolViolation,
      ScenarioQualityDecisionOperationState.transportFailure,
      ScenarioQualityDecisionOperationState.closed,
    }.contains(_review.operation);
    final confirmation = _review.pendingDecision;
    return section(
      classes: 'scenario-quality-review',
      attributes: <String, String>{
        'aria-label': 'Revisão humana autorizada pelo Host',
        'data-quality-review-availability': _review.availability.name,
        'data-quality-decision-operation': _review.operation.name,
        'data-quality-decision-count': '${_review.decisionCount}',
        if (_review.requirementId case final requirement?)
          'data-quality-decision-requirement': requirement.value,
        if (_review.headDecisionDigest case final head?)
          'data-quality-decision-head': head.value,
        if (_review.policyId case final policy?)
          'data-quality-decision-policy': policy.value,
      },
      <Component>[
        div(
          classes: 'scenario-quality-review__status',
          attributes: const <String, String>{
            'role': 'status',
            'aria-live': 'polite',
            'aria-atomic': 'true',
          },
          <Component>[Component.text(_statusLabel(_review))],
        ),
        if (_review.reviewInstruction case final instruction?)
          section(
            classes: 'scenario-quality-review__guide',
            attributes: const <String, String>{
              'aria-label': 'Review Guide fixado no Catalog',
              'data-quality-review-guide': 'pinned',
            },
            <Component>[
              h4(<Component>[
                Component.text(
                  _review.reviewGuideTitle ?? 'Orientação de revisão',
                ),
              ]),
              p(
                attributes: const <String, String>{
                  'data-quality-review-instruction': 'true',
                },
                <Component>[Component.text(instruction)],
              ),
              if (_review.reviewCriteria case final criteria?)
                p(
                  attributes: const <String, String>{
                    'data-quality-review-criteria': 'true',
                  },
                  <Component>[
                    strong(<Component>[const Component.text('Critério: ')]),
                    Component.text(criteria),
                  ],
                ),
            ],
          ),
        if (_review.resources.isNotEmpty) _resources(),
        if (_review.history.isNotEmpty) _history(),
        div(classes: 'scenario-quality-review__actions', <Component>[
          StudioButton(
            label: 'Atualizar revisão',
            kind: StudioButtonKind.quiet,
            leadingIcon: StudioIconName.refresh,
            disabled:
                busy ||
                _review.operation ==
                    ScenarioQualityDecisionOperationState.closed ||
                _review.operation ==
                    ScenarioQualityDecisionOperationState.detached,
            onPressed: () => unawaited(_controller.refresh()),
            attributes: const <String, String>{
              'data-quality-decision-action': 'refresh',
            },
          ),
          if (_review.headDecisionDigest == null) ...[
            _decisionButton(
              decision: HumanDecision.approved,
              action: 'approve',
              label: 'Aprovar',
              failed: failed,
            ),
            _decisionButton(
              decision: HumanDecision.rejected,
              action: 'reject',
              label: 'Rejeitar',
              failed: failed,
            ),
          ],
          if (_review.headDecisionDigest != null) ...[
            if (_review.quality?.humanDecision.state ==
                HumanDecisionState.rejected)
              _decisionButton(
                decision: HumanDecision.approved,
                action: 'supersede-approved',
                label: 'Substituir por aprovação',
                failed: failed,
              ),
            if (_review.quality?.humanDecision.state ==
                HumanDecisionState.approved)
              _decisionButton(
                decision: HumanDecision.rejected,
                action: 'supersede-rejected',
                label: 'Substituir por rejeição',
                failed: failed,
              ),
          ],
        ]),
        if (confirmation != null)
          StudioDialog(
            id: 'scenario-quality-decision-confirmation',
            title: 'Confirmar decisão humana?',
            description:
                'Confirme ${_decisionLabel(confirmation)} somente após revisar todos os artifacts fixados.',
            onDismiss: _controller.cancelDecision,
            children: const <Component>[
              p(<Component>[
                Component.text(
                  'O Studio solicitará autoridade efêmera ao Host apenas depois desta confirmação.',
                ),
              ]),
            ],
            actions: <Component>[
              StudioButton(
                label: 'Cancelar',
                kind: StudioButtonKind.quiet,
                disabled: busy,
                onPressed: _controller.cancelDecision,
                attributes: const <String, String>{
                  'data-quality-decision-action': 'cancel',
                },
              ),
              StudioButton(
                label: 'Confirmar decisão',
                autofocus: true,
                disabled: busy || failed,
                onPressed: () =>
                    unawaited(_controller.submitConfirmedDecision()),
                attributes: const <String, String>{
                  'data-quality-decision-action': 'confirm',
                },
              ),
            ],
          ),
      ],
    );
  }

  Component _decisionButton({
    required HumanDecision decision,
    required String action,
    required String label,
    required bool failed,
  }) => StudioButton(
    label: label,
    kind: decision == HumanDecision.rejected
        ? StudioButtonKind.danger
        : StudioButtonKind.primary,
    disabled: !_review.canDecide || failed,
    onPressed: () => _controller.requestDecision(decision),
    attributes: <String, String>{'data-quality-decision-action': action},
  );

  Component _resources() => section(
    classes: 'scenario-quality-review__resources',
    attributes: const <String, String>{
      'aria-label': 'Recursos exatos da revisão',
    },
    <Component>[
      h4(<Component>[const Component.text('Artifacts revisados')]),
      ul(<Component>[
        for (final resource in _review.resources) _resourceItem(resource),
      ]),
    ],
  );

  Component _resourceItem(ScenarioQualityReviewResourceSnapshot resource) {
    final owner = _controller;
    final generation = _review.resourceGeneration;
    return li(
      attributes: <String, String>{
        'data-quality-resource-state': resource.state.name,
        'data-quality-resource-role': resource.role.name,
        'data-quality-artifact-digest': resource.artifactDigest.value,
        'data-quality-provenance-kind': resource.provenanceKind.name,
      },
      <Component>[
        strong(<Component>[Component.text(_resourceRoleLabel(resource.role))]),
        if (resource.isImage)
          VerifiedArtifactImage.secure(
            key: ValueKey<String>(
              '$generation:${resource.descriptorDigest.value}',
            ),
            resourceIdentity: resource.artifactDigest,
            leaseLoader: () => owner.openReviewImage(
              resource.descriptorDigest,
              expectedResourceGeneration: generation,
            ),
            onStatusChanged: (status) {
              switch (status) {
                case VerifiedArtifactImageStatus.rendered:
                  owner.markReviewImageRendered(
                    resource.descriptorDigest,
                    expectedResourceGeneration: generation,
                  );
                case VerifiedArtifactImageStatus.rejected:
                  owner.rejectReviewImage(
                    resource.descriptorDigest,
                    expectedResourceGeneration: generation,
                  );
                case VerifiedArtifactImageStatus.loading ||
                    VerifiedArtifactImageStatus.validated:
                  break;
              }
            },
            alt: 'Artifact ${_resourceRoleLabel(resource.role)}',
            classes: 'scenario-quality-review__image',
            loading: MediaLoading.eager,
          )
        else
          p(<Component>[
            Component.text(
              resource.state == ScenarioQualityReviewResourceState.validated
                  ? 'Artifact não visual validado.'
                  : 'Validando artifact não visual.',
            ),
          ]),
      ],
    );
  }

  Component _history() => section(
    classes: 'scenario-quality-review__history',
    attributes: const <String, String>{
      'aria-label': 'Histórico de decisões humanas',
    },
    <Component>[
      h4(<Component>[const Component.text('Histórico de decisões')]),
      ol(<Component>[
        for (final item in _review.history)
          li(
            attributes: <String, String>{
              'data-quality-decision-record': item.recordId.value,
              'data-quality-human-decision': item.state.name,
              'data-quality-decision-policy': item.policyId.value,
              'data-quality-decision-requirement': item.requirementId.value,
              if (item.supersededByDecisionDigest case final next?)
                'data-quality-decision-superseded-by': next.value,
            },
            <Component>[
              strong(<Component>[
                Component.text(_decisionLabel(item.decision)),
              ]),
              Component.text(
                item.state == HumanDecisionState.superseded
                    ? ' · substituída por uma decisão posterior'
                    : ' · decisão atual',
              ),
            ],
          ),
      ]),
    ],
  );
}

bool _sameMethods(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _statusLabel(
  ScenarioQualityDecisionControllerSnapshot snapshot,
) => switch (snapshot.operation) {
  ScenarioQualityDecisionOperationState.detached =>
    'Selecione e reanexe uma execução terminal exata para revisar.',
  ScenarioQualityDecisionOperationState.loading =>
    'Validando revisão, proveniência e histórico publicados pelo Host.',
  ScenarioQualityDecisionOperationState.submitting =>
    'Publicando a decisão humana no Host.',
  ScenarioQualityDecisionOperationState.conflict =>
    'A revisão mudou no Host. Atualize antes de decidir novamente.',
  ScenarioQualityDecisionOperationState.protocolViolation =>
    'O Studio recusou uma resposta que não respeita os fences da revisão.',
  ScenarioQualityDecisionOperationState.transportFailure =>
    'Não foi possível concluir a comunicação com o Host.',
  ScenarioQualityDecisionOperationState.closed => 'Revisão encerrada.',
  ScenarioQualityDecisionOperationState.ready => switch (snapshot
      .availability) {
    ScenarioQualityReviewAvailability.available =>
      snapshot.resourcesReady
          ? 'Todos os artifacts foram validados e renderizados.'
          : 'A decisão ficará disponível após validar e renderizar todos os artifacts.',
    ScenarioQualityReviewAvailability.unavailable =>
      'Esta execução não publicou uma revisão humana disponível.',
    ScenarioQualityReviewAvailability.unsupported =>
      'O Host não oferece o quinteto de revisão humana.',
    ScenarioQualityReviewAvailability.policyDenied =>
      'A política do Host não autoriza revisão humana neste contexto.',
  },
};

String _decisionLabel(HumanDecision decision) => switch (decision) {
  HumanDecision.approved => 'aprovação',
  HumanDecision.rejected => 'rejeição',
};

String _resourceRoleLabel(ScenarioQualityReviewArtifactRole role) =>
    switch (role) {
      ScenarioQualityReviewArtifactRole.requiredEvidence => 'Required Evidence',
      ScenarioQualityReviewArtifactRole.comparisonBaseline =>
        'Baseline da comparison',
      ScenarioQualityReviewArtifactRole.comparisonCandidate =>
        'Candidate da comparison',
    };
