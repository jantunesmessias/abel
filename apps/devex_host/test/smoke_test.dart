import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('host app exposes the runtime server boundary', () {
    expect(
      () => HostRpcServer(
        studioOrigin: Uri.parse('http://127.0.0.1:8080'),
        sessionToken: '0123456789abcdef0123456789abcdef',
      ),
      returnsNormally,
    );
  });
}
