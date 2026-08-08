import 'package:gateway_sidecar/gateway_sidecar.dart';
import 'package:test/test.dart';

void main() {
  test('advertises the implemented Gateway containment capabilities', () {
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
