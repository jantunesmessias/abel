import 'devex_app_adapter.dart';
import 'devex_app_adapter_bridge.dart';
import 'devex_flutter_binding.dart';

DevExAppAdapterBridge startBridge({
  required DevExFlutterBinding binding,
  required DevExAppAdapter adapter,
}) => const _NoopBridge();

final class _NoopBridge implements DevExAppAdapterBridge {
  const _NoopBridge();

  @override
  void dispose() {}
}
