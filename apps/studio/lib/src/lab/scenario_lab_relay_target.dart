import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../target_frame/target_frame.dart';
import 'scenario_lab_relay_controller.dart';

final class TargetFrameRelayCommandTarget
    implements ScenarioLabRelayCommandTarget {
  const TargetFrameRelayCommandTarget(this.controller);

  final TargetFrameController controller;

  @override
  bool get isAttached => controller.isAttached;

  @override
  void sendCommand(AppAdapterRelayCommand command) {
    controller.send(command.toJson());
  }
}

final class ScenarioLabRelayTarget extends StatefulComponent {
  ScenarioLabRelayTarget({
    required this.controller,
    required this.frameController,
    this.onStateChanged,
    this.onDisposed,
    super.key,
  }) {
    final target = controller.target;
    if (target is! TargetFrameRelayCommandTarget ||
        !identical(target.controller, frameController)) {
      throw ArgumentError(
        'ScenarioLabRelayTarget requires its single TargetFrameController',
      );
    }
  }

  final ScenarioLabRelayController controller;
  final TargetFrameController frameController;
  final ScenarioLabRelayStateListener? onStateChanged;
  final VoidCallback? onDisposed;

  @override
  State<ScenarioLabRelayTarget> createState() => _ScenarioLabRelayTargetState();
}

final class _ScenarioLabRelayTargetState extends State<ScenarioLabRelayTarget> {
  @override
  void initState() {
    super.initState();
    component.controller.setStateListener(_onStateChanged);
    unawaited(component.controller.open());
  }

  void _onStateChanged(ScenarioLabRelayControllerSnapshot snapshot) {
    component.onStateChanged?.call(snapshot);
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final controller = component.controller;
    final snapshot = controller.snapshot;
    final descriptor = controller.descriptor;
    final gatewayDataOrigin = controller.gatewayDataOriginFor(
      controller.target,
    );
    return section(
      classes: 'scenario-lab-relay-target',
      attributes: <String, String>{
        'aria-label': 'Target do Scenario Lab',
        'data-lab-relay-run-id': snapshot.runId.value,
        'data-lab-relay-state': snapshot.status.name,
        'data-lab-relay-gateway-bound': '${snapshot.gatewayBound}',
        'data-lab-relay-last-sequence': '${snapshot.lastAcceptedSequence}',
        if (snapshot.descriptorDigest != null)
          'data-lab-relay-descriptor-digest': snapshot.descriptorDigest!.value,
        if (snapshot.failure != null)
          'data-lab-relay-failure': snapshot.failure!.name,
      },
      <Component>[
        if (descriptor == null)
          p(
            attributes: const <String, String>{
              'role': 'status',
              'aria-live': 'polite',
            },
            <Component>[Component.text(_statusLabel(snapshot.status))],
          )
        else ...<Component>[
          dl(<Component>[
            dt(<Component>[Component.text('Target')]),
            dd(<Component>[Component.text(descriptor.targetId)]),
            dt(<Component>[Component.text('Launch profile')]),
            dd(<Component>[Component.text(descriptor.launchProfileId)]),
            dt(<Component>[Component.text('Launch attempt')]),
            dd(<Component>[Component.text(descriptor.launchAttemptId.value)]),
          ]),
          div(
            attributes: <String, String>{
              'data-lab-relay-target-id': descriptor.targetId,
              'data-lab-relay-launch-profile-id': descriptor.launchProfileId,
              'data-lab-relay-launch-attempt-id':
                  descriptor.launchAttemptId.value,
            },
            <Component>[
              TargetFrame(
                targetUri: descriptor.origin,
                sessionId: descriptor.runId.value,
                nonce: descriptor.nonce.value,
                scenarioLabRunId: descriptor.runId.value,
                gatewayDataOrigin: gatewayDataOrigin,
                controller: component.frameController,
                onAuthorizedMessage: controller.acceptFrameEnvelope,
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    component.controller.setStateListener(null);
    component.controller.close();
    component.onDisposed?.call();
    super.dispose();
  }
}

String _statusLabel(ScenarioLabRelayControllerStatus status) =>
    switch (status) {
      ScenarioLabRelayControllerStatus.idle => 'Relay ainda não iniciado.',
      ScenarioLabRelayControllerStatus.unavailable =>
        'Relay indisponível neste Host.',
      ScenarioLabRelayControllerStatus.describing ||
      ScenarioLabRelayControllerStatus.pendingTarget =>
        'Aguardando o target autorizado pelo Host.',
      ScenarioLabRelayControllerStatus.awaitingHello ||
      ScenarioLabRelayControllerStatus.authorizingHello =>
        'Aguardando identificação autorizada do App Adapter.',
      ScenarioLabRelayControllerStatus.polling =>
        'Target autorizado; aguardando próximo comando.',
      ScenarioLabRelayControllerStatus.awaitingResult ||
      ScenarioLabRelayControllerStatus.submittingResult =>
        'Target autorizado; aguardando resultado.',
      ScenarioLabRelayControllerStatus.closed => 'Relay encerrado pelo Host.',
      ScenarioLabRelayControllerStatus.cancelled =>
        'Relay cancelado localmente.',
      ScenarioLabRelayControllerStatus.failed =>
        'Relay encerrado por falha de autorização ou transporte.',
    };
