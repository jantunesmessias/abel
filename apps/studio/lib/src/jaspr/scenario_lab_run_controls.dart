import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/lab/scenario_lab_run_controller.dart';
import 'package:studio/src/lab/scenario_lab_ui_capabilities.dart';
import 'package:studio_ui/studio_ui.dart';

final class ScenarioLabRunControls extends StatelessComponent {
  const ScenarioLabRunControls({
    required this.capabilities,
    required this.allowMutations,
    required this.invalidRunId,
    this.selectedRunId,
    this.lifecycle,
    this.runSnapshot,
    this.onStart,
    this.onCancel,
    this.onReattach,
    this.onMountRelay,
    this.relayTarget,
    super.key,
  });

  final ScenarioLabUiCapabilities capabilities;
  final bool allowMutations;
  final bool invalidRunId;
  final ScenarioLabRunId? selectedRunId;
  final ScenarioLabRunControllerSnapshot? lifecycle;
  final ScenarioLabRunSnapshot? runSnapshot;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onReattach;
  final VoidCallback? onMountRelay;
  final Component? relayTarget;

  @override
  Component build(BuildContext context) {
    final status = lifecycle?.status;
    final busy = const <ScenarioLabRunControllerStatus>{
      ScenarioLabRunControllerStatus.starting,
      ScenarioLabRunControllerStatus.polling,
      ScenarioLabRunControllerStatus.cancelling,
      ScenarioLabRunControllerStatus.reattaching,
    }.contains(status);
    final exactRun =
        selectedRunId != null &&
        lifecycle?.runId == selectedRunId &&
        runSnapshot?.runId == selectedRunId;
    final canCancel =
        allowMutations &&
        exactRun &&
        runSnapshot?.state.isTerminal == false &&
        !busy;
    final canRelay = canCancel && capabilities.relayAvailable;

    return section(
      classes: 'scenario-lab-run-controls',
      attributes: <String, String>{
        'aria-label': allowMutations
            ? 'Ações da execução Scenario Lab'
            : 'Observação da execução Scenario Lab',
        'data-lab-run-capability': capabilities.run.name,
        'data-lab-relay-capability': capabilities.relay.name,
        'data-lab-run-actions-state': invalidRunId
            ? 'invalidRunId'
            : capabilities.runAvailable
            ? 'ready'
            : 'unavailable',
        'data-lab-run-lifecycle': status?.name ?? 'detached',
        if (selectedRunId != null)
          'data-lab-selected-run-id': selectedRunId!.value,
        if (lifecycle?.failure != null)
          'data-lab-run-failure': lifecycle!.failure!.name,
      },
      <Component>[
        h2(<Component>[Component.text('Execução Host-owned')]),
        if (invalidRunId)
          const StudioFeedbackBanner(
            title: 'Run ID inválido',
            message:
                'A URL não contém uma identidade Scenario Lab canônica; nenhuma operação foi enviada.',
            tone: PresentationTone.critical,
          )
        else if (!capabilities.runAvailable)
          StudioFeedbackBanner(
            title: 'Executor indisponível',
            message: _capabilityMessage(capabilities.run),
            tone:
                const <ScenarioLabUiCapabilityState>{
                  ScenarioLabUiCapabilityState.rpcIncomplete,
                  ScenarioLabUiCapabilityState.gatewayV2Required,
                }.contains(capabilities.run)
                ? PresentationTone.critical
                : PresentationTone.warning,
          )
        else ...<Component>[
          p(
            attributes: const <String, String>{
              'role': 'status',
              'aria-live': 'polite',
            },
            <Component>[
              Component.text(_lifecycleMessage(lifecycle, selectedRunId)),
            ],
          ),
          div(classes: 'capability-actions', <Component>[
            if (allowMutations && selectedRunId == null)
              StudioButton(
                label: busy ? 'Iniciando…' : 'Iniciar execução',
                leadingIcon: StudioIconName.play,
                onPressed: busy ? null : onStart,
                disabled: busy || onStart == null,
                attributes: const <String, String>{
                  'data-lab-run-action': 'start',
                },
              ),
            if (selectedRunId != null)
              StudioButton(
                label: busy ? 'Observando…' : 'Reanexar / atualizar',
                leadingIcon: StudioIconName.refresh,
                kind: StudioButtonKind.secondary,
                onPressed: busy ? null : onReattach,
                disabled: busy || onReattach == null,
                attributes: const <String, String>{
                  'data-lab-run-action': 'reattach',
                },
              ),
            if (allowMutations && selectedRunId != null)
              StudioButton(
                label: status == ScenarioLabRunControllerStatus.cancelling
                    ? 'Cancelando…'
                    : 'Cancelar execução',
                leadingIcon: StudioIconName.stop,
                kind: StudioButtonKind.danger,
                onPressed: canCancel ? onCancel : null,
                disabled: !canCancel || onCancel == null,
                attributes: const <String, String>{
                  'data-lab-run-action': 'cancel',
                },
              ),
            if (allowMutations && selectedRunId != null)
              StudioButton(
                label: relayTarget == null
                    ? 'Conectar target'
                    : 'Relay do target montado',
                leadingIcon: StudioIconName.target,
                kind: StudioButtonKind.quiet,
                onPressed: canRelay && relayTarget == null
                    ? onMountRelay
                    : null,
                disabled:
                    !canRelay || onMountRelay == null || relayTarget != null,
                attributes: const <String, String>{
                  'data-lab-run-action': 'relay',
                },
              ),
          ]),
          if (allowMutations &&
              selectedRunId != null &&
              !capabilities.relayAvailable)
            p(
              attributes: <String, String>{
                'data-lab-relay-state': capabilities.relay.name,
              },
              <Component>[Component.text(_relayMessage(capabilities.relay))],
            ),
          ?relayTarget,
        ],
      ],
    );
  }
}

String _capabilityMessage(
  ScenarioLabUiCapabilityState state,
) => switch (state) {
  ScenarioLabUiCapabilityState.moduleDisabled =>
    'O ResolvedKitPlan não publicou studio.lab.',
  ScenarioLabUiCapabilityState.contentUnavailable =>
    'O executor exige ScenarioLabManifest no mesmo content-set atômico.',
  ScenarioLabUiCapabilityState.clientUnavailable =>
    'O transporte Studio atual não implementa o lifecycle tipado.',
  ScenarioLabUiCapabilityState.rpcUnavailable =>
    'O Host não anunciou o quartet start/get/cancel/reattach.',
  ScenarioLabUiCapabilityState.rpcIncomplete =>
    'O Host anunciou um quartet lifecycle incompleto; o Studio falhou fechado.',
  ScenarioLabUiCapabilityState.gatewayV2Required =>
    'A execução Gateway-bound exige relay describe v2.',
  ScenarioLabUiCapabilityState.runUnavailable =>
    'A capability de execução anterior está indisponível.',
  ScenarioLabUiCapabilityState.available => 'Executor disponível.',
};

String _relayMessage(ScenarioLabUiCapabilityState state) => switch (state) {
  ScenarioLabUiCapabilityState.clientUnavailable =>
    'O transporte não implementa o relay tipado.',
  ScenarioLabUiCapabilityState.rpcUnavailable =>
    'O Host não anunciou o quartet relay; nenhum iframe será montado.',
  ScenarioLabUiCapabilityState.rpcIncomplete =>
    'O Host anunciou um quartet relay incompleto; nenhum iframe será montado.',
  ScenarioLabUiCapabilityState.gatewayV2Required =>
    'Este run exige relay describe v2; nenhum downgrade v1 será tentado.',
  ScenarioLabUiCapabilityState.runUnavailable =>
    'O relay depende de um lifecycle de execução disponível.',
  _ => 'Relay indisponível.',
};

String _lifecycleMessage(
  ScenarioLabRunControllerSnapshot? lifecycle,
  ScenarioLabRunId? selectedRunId,
) {
  if (selectedRunId == null) return 'Nenhuma execução foi iniciada nesta URL.';
  if (lifecycle == null || lifecycle.runId != selectedRunId) {
    return 'A execução ${selectedRunId.value} ainda não foi reanexada.';
  }
  final sequence = lifecycle.sequence;
  return 'Execução ${selectedRunId.value}: ${lifecycle.status.name}'
      '${sequence == null ? '' : ' · observação $sequence'}.';
}
