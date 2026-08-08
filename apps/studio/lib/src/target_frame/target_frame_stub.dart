import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:studio_ui/studio_ui.dart';

final class TargetFrameController {
  bool get isAttached => false;

  void send(Map<String, Object?> payload) {
    throw UnsupportedError('TargetFrame requires a browser runtime');
  }
}

final class TargetFrame extends StatelessComponent {
  TargetFrame({
    required this.targetUri,
    required this.sessionId,
    required this.nonce,
    required this.controller,
    required this.onAuthorizedMessage,
    this.gatewayOrigin,
    Uri? gatewayDataOrigin,
    this.scenarioLabRunId,
    super.key,
  }) : _gatewayData = gatewayDataOrigin == null
           ? null
           : (value: gatewayDataOrigin) {
    final runId = scenarioLabRunId;
    if (runId == null && _gatewayData != null) {
      throw ArgumentError(
        'Gateway data origin is reserved for a Scenario Lab relay',
      );
    }
    if (runId != null) {
      ScenarioLabRunId(runId);
      if (runId != sessionId) {
        throw ArgumentError(
          'Scenario Lab TargetFrame run must equal its session ID',
        );
      }
      if (gatewayOrigin != null) {
        throw ArgumentError(
          'Scenario Lab relay requires gatewayDataOrigin instead of gatewayOrigin',
        );
      }
      final origin = _gatewayData?.value;
      if (origin != null) canonicalScenarioLabGatewayDataOrigin(origin);
    }
  }

  final Uri targetUri;
  final String sessionId;
  final String nonce;
  final TargetFrameController controller;
  final void Function(PostMessageEnvelope envelope) onAuthorizedMessage;
  final Uri? gatewayOrigin;
  final ({Uri value})? _gatewayData;
  final String? scenarioLabRunId;

  bool get gatewayBound => _gatewayData != null;

  @override
  Component build(BuildContext context) => const StudioEmptyState(
    title: 'Target indisponível',
    message: 'O iframe isolado do target exige execução no browser.',
    tone: PresentationTone.warning,
  );
}
