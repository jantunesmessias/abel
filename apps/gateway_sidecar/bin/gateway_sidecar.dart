import 'dart:convert';
import 'dart:io';

import 'package:gateway_sidecar/gateway_sidecar.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--version') {
    stdout.writeln(jsonEncode(const BackendGatewayBuildInfo().toJson()));
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: gateway_sidecar [--version]');
    exitCode = 2;
    return;
  }
  await const GatewayStdioControlPlane().run(stdin, stdout);
}
