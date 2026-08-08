import 'studio_host_client.dart';
import 'studio_host_client_factory_stub.dart'
    if (dart.library.js_interop) 'studio_host_client_factory_web.dart'
    as platform;

StudioHostClient createStudioHostClient() => platform.createStudioHostClient();
