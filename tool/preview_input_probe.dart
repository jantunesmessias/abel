import 'dart:convert';
import 'dart:io';

import 'package:devex_runtime/devex_runtime.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/preview_input_probe.dart <app-root>');
    exitCode = 64;
    return;
  }
  final inputs = const PreviewWorkspaceInputs().inspect(arguments.single);
  stdout.writeln(
    jsonEncode(<String, Object?>{
      for (final entry in inputs.entries) entry.key: entry.value.value,
    }),
  );
}
