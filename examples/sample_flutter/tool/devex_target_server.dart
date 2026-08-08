import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final rootOption = _option(arguments, '--root=') ?? 'build/web';
  final port = int.parse(_option(arguments, '--port=') ?? '8080');
  final frameAncestorOption = _option(arguments, '--frame-ancestor=');
  if (arguments.any(
    (argument) =>
        !argument.startsWith('--root=') &&
        !argument.startsWith('--port=') &&
        !argument.startsWith('--frame-ancestor='),
  )) {
    throw const FormatException(
      'Usage: dart run tool/devex_target_server.dart '
      '[--root=build/web] [--port=8080] '
      '[--frame-ancestor=http://127.0.0.1:7368]',
    );
  }
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port');
  }
  final workspace = Directory.current.resolveSymbolicLinksSync();
  final candidate = p.normalize(
    p.isAbsolute(rootOption) ? rootOption : p.join(workspace, rootOption),
  );
  final rootDirectory = Directory(candidate);
  if (!rootDirectory.existsSync()) {
    throw FileSystemException('Built Target assets are missing', candidate);
  }
  final root = rootDirectory.resolveSymbolicLinksSync();
  if (root != workspace && !p.isWithin(workspace, root)) {
    throw FileSystemException('Target assets escape the workspace', candidate);
  }
  if (!File(p.join(root, 'index.html')).existsSync()) {
    throw FileSystemException('Target index.html is missing', root);
  }
  final frameAncestor = frameAncestorOption == null
      ? null
      : _validateFrameAncestor(frameAncestorOption);

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.defaultResponseHeaders.removeAll('x-frame-options');
  final stopping = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) {
      if (!stopping.isCompleted) stopping.complete();
    }),
    ProcessSignal.sigterm.watch().listen((_) {
      if (!stopping.isCompleted) stopping.complete();
    }),
  ];
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'status': 'ready',
      'service': 'sample-flutter-target',
      'origin': 'http://${server.address.address}:${server.port}',
      'pid': pid,
    }),
  );
  final serving = server.forEach(
    (request) => _serve(request, root, frameAncestor),
  );
  try {
    await stopping.future;
  } finally {
    await server.close(force: true);
    await serving;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

String? _option(List<String> arguments, String prefix) => arguments
    .where((argument) => argument.startsWith(prefix))
    .map((argument) => argument.substring(prefix.length))
    .firstOrNull;

Future<void> _serve(
  HttpRequest request,
  String root,
  String? frameAncestor,
) async {
  try {
    request.response.headers
      ..removeAll('x-frame-options')
      ..set(
        'content-security-policy',
        "frame-ancestors 'self'${frameAncestor == null ? '' : ' $frameAncestor'}",
      );
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set('allow', 'GET, HEAD');
      return;
    }
    if (request.uri.path == '/health') {
      request.response.headers.contentType = ContentType.json;
      if (request.method != 'HEAD') {
        request.response.write('{"status":"ready"}');
      }
      return;
    }
    final decodedPath = Uri.decodeComponent(request.uri.path);
    if (decodedPath.contains('\u0000') || decodedPath.contains('\\')) {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }
    final relative = decodedPath == '/'
        ? 'index.html'
        : decodedPath.replaceFirst(RegExp(r'^/+'), '');
    var file = _confinedFile(root, relative);
    if (!file.existsSync() && p.extension(relative).isEmpty) {
      file = File(p.join(root, 'index.html'));
    }
    if (!file.existsSync() ||
        FileSystemEntity.typeSync(file.path, followLinks: false) ==
            FileSystemEntityType.link) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers
      ..contentType = _contentType(file.path)
      ..set('cache-control', 'no-store')
      ..set('x-content-type-options', 'nosniff')
      ..set('referrer-policy', 'no-referrer');
    request.response.contentLength = file.lengthSync();
    if (request.method != 'HEAD') {
      await request.response.addStream(file.openRead());
    }
  } on FormatException {
    request.response.statusCode = HttpStatus.badRequest;
  } on FileSystemException {
    request.response.statusCode = HttpStatus.notFound;
  } finally {
    await request.response.close();
  }
}

String _validateFrameAncestor(String value) {
  final uri = Uri.parse(value);
  final address = InternetAddress.tryParse(uri.host);
  final isLoopback = uri.host == 'localhost' || address?.isLoopback == true;
  if ((uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      !isLoopback ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw FormatException('Frame ancestor must be a loopback HTTP(S) origin');
  }
  return uri.origin;
}

File _confinedFile(String root, String relative) {
  final candidate = p.normalize(p.join(root, relative));
  if (!p.isWithin(root, candidate)) {
    throw const FormatException('Target path escapes the asset root');
  }
  var cursor = root;
  for (final segment in p.split(p.relative(candidate, from: root))) {
    cursor = p.join(cursor, segment);
    if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Target path contains a symbolic link');
    }
  }
  return File(candidate);
}

ContentType _contentType(String path) => switch (p.extension(path)) {
  '.html' => ContentType.html,
  '.js' => ContentType('text', 'javascript', charset: 'utf-8'),
  '.json' => ContentType.json,
  '.css' => ContentType('text', 'css', charset: 'utf-8'),
  '.wasm' => ContentType('application', 'wasm'),
  '.png' => ContentType('image', 'png'),
  '.svg' => ContentType('image', 'svg+xml'),
  '.ico' => ContentType('image', 'x-icon'),
  '.woff' => ContentType('font', 'woff'),
  '.woff2' => ContentType('font', 'woff2'),
  _ => ContentType.binary,
};
