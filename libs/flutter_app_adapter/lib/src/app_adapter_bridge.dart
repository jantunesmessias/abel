import 'app_adapter.dart';
import 'app_adapter_bridge_stub.dart'
    if (dart.library.js_interop) 'app_adapter_bridge_web.dart'
    as implementation;
import 'app_adapter_relay.dart';
import 'target_binding.dart';

abstract interface class AppAdapterBridge {
  void dispose();
}

AppAdapterBridge startAppAdapterBridge({
  required TargetBinding binding,
  required AppAdapter adapter,
  AppAdapterRelay? relay,
}) => implementation.startBridge(
  binding: binding,
  adapter: adapter,
  relay: relay,
);
