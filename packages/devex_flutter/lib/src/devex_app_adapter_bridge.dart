import 'devex_app_adapter.dart';
import 'devex_app_adapter_bridge_stub.dart'
    if (dart.library.js_interop) 'devex_app_adapter_bridge_web.dart'
    as implementation;
import 'devex_flutter_binding.dart';

abstract interface class DevExAppAdapterBridge {
  void dispose();
}

DevExAppAdapterBridge startDevExAppAdapterBridge({
  required DevExFlutterBinding binding,
  required DevExAppAdapter adapter,
}) => implementation.startBridge(binding: binding, adapter: adapter);
