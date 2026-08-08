import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/remote/remote_session_transport.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr/jaspr.dart';

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
  Component build(BuildContext context) => const DevExEmptyState(
    title: 'Sessão remota indisponível',
    message: 'A superfície remota exige execução no browser.',
    tone: DevExTone.warning,
  );
}
