import 'dart:convert';
import 'dart:io';

import 'package:backend_gateway/backend_gateway.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--version') {
    stdout.writeln(jsonEncode(const BackendGatewayBuildInfo().toJson()));
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: backend_gateway [--version]');
    exitCode = 2;
    return;
  }
  await const GatewayStdioControlPlane().run(stdin, stdout);
}
