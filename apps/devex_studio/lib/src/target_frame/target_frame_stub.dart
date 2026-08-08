import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr/jaspr.dart';

final class TargetFrameController {
  bool get isAttached => false;

  void send(Map<String, Object?> payload) {
    throw UnsupportedError('TargetFrame requires a browser runtime');
  }
}

final class TargetFrame extends StatelessComponent {
  const TargetFrame({
    required this.targetUri,
    required this.sessionId,
    required this.nonce,
    required this.controller,
    required this.onAuthorizedMessage,
    this.gatewayOrigin,
    super.key,
  });

  final Uri targetUri;
  final String sessionId;
  final String nonce;
  final TargetFrameController controller;
  final void Function(PostMessageEnvelope envelope) onAuthorizedMessage;
  final Uri? gatewayOrigin;

  @override
  Component build(BuildContext context) => const DevExEmptyState(
    title: 'Target indisponível',
    message: 'O iframe isolado do target exige execução no browser.',
    tone: DevExTone.warning,
  );
}
