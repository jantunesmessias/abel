import 'dart:async';
import 'dart:io';

import 'package:devex_runtime/devex_runtime.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: devex_static <directory>');
    exitCode = 2;
    return;
  }
  final server = StaticWebOriginServer(
    rootDirectory: Directory(arguments.single).absolute.path,
  );
  try {
    await server.start();
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path}');
    exitCode = 2;
    return;
  }
  stdout.writeln(server.origin);

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigint;
  late final StreamSubscription<ProcessSignal> sigterm;
  void requestStop(ProcessSignal _) {
    if (!stopping.isCompleted) stopping.complete();
  }

  sigint = ProcessSignal.sigint.watch().listen(requestStop);
  sigterm = ProcessSignal.sigterm.watch().listen(requestStop);
  await stopping.future;
  await server.close();
  await sigint.cancel();
  await sigterm.cancel();
}
