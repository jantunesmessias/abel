import 'studio_host_client.dart';

StudioHostClient createStudioHostClient() => _UnsupportedStudioHostClient();

final class _UnsupportedStudioHostClient implements StudioHostClient {
  @override
  Future<void> close() async {}

  @override
  Future<Never> openWorkspace() => Future<Never>.error(
    UnsupportedError('DevEx Host bootstrap requires a browser runtime'),
  );

  @override
  Future<Never> refreshWorkspace() => openWorkspace();
}
