import 'package:backend_gateway/backend_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('advertises the implemented V0.2 Gateway capabilities', () {
    final buildInfo = const BackendGatewayBuildInfo().toJson();

    expect(buildInfo['version'], '0.1.0-dev');
    expect(
      buildInfo['implementedCapabilities'],
      containsAll(<String>[
        'gateway.isolated',
        'gateway.hybrid',
        'gateway.verify',
        'gateway.upstream.allowlist',
        'gateway.upstream.dnsPinned',
      ]),
    );
  });
}
