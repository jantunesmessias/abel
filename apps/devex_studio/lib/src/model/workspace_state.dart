import 'package:devex_contracts/devex_contracts.dart';

final class WorkspaceConnectionState {
  const WorkspaceConnectionState({
    required this.connected,
    this.isStale = false,
    this.message,
  });

  const WorkspaceConnectionState.unavailable()
    : connected = false,
      isStale = false,
      message = null;

  final bool connected;
  final bool isStale;
  final String? message;
}

/// Renderer-independent state of the Studio-to-Host workspace session.
final class StudioWorkspaceState {
  const StudioWorkspaceState({
    required this.connection,
    this.snapshot,
    this.failureMessage,
    this.isConnecting = false,
  });

  const StudioWorkspaceState.initial()
    : connection = const WorkspaceConnectionState.unavailable(),
      snapshot = null,
      failureMessage = null,
      isConnecting = false;

  final WorkspaceConnectionState connection;
  final WorkspaceSnapshot? snapshot;
  final String? failureMessage;
  final bool isConnecting;

  bool get hasSnapshot => snapshot != null;
}
