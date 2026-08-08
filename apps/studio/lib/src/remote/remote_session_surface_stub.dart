import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/remote/remote_session_transport.dart';
import 'package:studio_ui/studio_ui.dart';

Future<bool> remoteH264WebCodecsSupported({
  String codec = 'avc1.42E01E',
  int width = 16,
  int height = 16,
}) async => false;

final class RemoteSessionSurface extends StatelessComponent {
  const RemoteSessionSurface({
    required this.grant,
    this.onClosed,
    this.connectionFactory,
    this.webBootstrapper,
    super.key,
  });

  final RemoteSessionGrant grant;
  final VoidCallback? onClosed;
  final RemoteSessionConnectionFactory? connectionFactory;
  final RemoteWebSessionBootstrapper? webBootstrapper;

  @override
  Component build(BuildContext context) => const StudioEmptyState(
    title: 'Sessão remota indisponível',
    message: 'A superfície remota exige execução no browser.',
    tone: PresentationTone.warning,
  );
}
