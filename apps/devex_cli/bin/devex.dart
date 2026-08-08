import 'dart:io';

import 'package:devex_cli/devex_cli.dart';

Future<void> main(List<String> arguments) async {
  final result = await DevExCli().run(arguments);
  if (result.stdout.isNotEmpty) {
    stdout.write(result.stdout);
    await stdout.flush();
  }
  if (result.stderr.isNotEmpty) {
    stderr.write(result.stderr);
    await stderr.flush();
  }
  exitCode = result.exitCode;
}
