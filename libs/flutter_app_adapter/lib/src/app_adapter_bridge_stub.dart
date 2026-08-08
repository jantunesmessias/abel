import 'app_adapter.dart';
import 'app_adapter_bridge.dart';
import 'app_adapter_relay.dart';
import 'target_binding.dart';

AppAdapterBridge startBridge({
  required TargetBinding binding,
  required AppAdapter adapter,
  AppAdapterRelay? relay,
}) => _NoopBridge(relay);

final class _NoopBridge implements AppAdapterBridge {
  const _NoopBridge(this.relay);

  final AppAdapterRelay? relay;

  @override
  void dispose() => relay?.dispose();
}
