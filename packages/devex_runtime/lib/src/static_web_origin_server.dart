import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

final class StaticWebOriginServer {
  StaticWebOriginServer({
    required this.rootDirectory,
    this.defaultDocument = 'index.html',
  });

  final String rootDirectory;
  final String defaultDocument;
  HttpServer? _server;

  Uri get origin {
    final server = _server;
    if (server == null) throw StateError('Static origin is not running');
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Future<void> start({InternetAddress? address, int port = 0}) async {
    if (_server != null) throw StateError('Static origin already running');
    if (!Directory(rootDirectory).existsSync()) {
      throw FileSystemException('Static root does not exist', rootDirectory);
    }
    final staticHandler = createStaticHandler(
      rootDirectory,
      defaultDocument: defaultDocument,
    );
    final handler = const Pipeline()
        .addMiddleware(
          (inner) => (request) async {
            final response = await inner(request);
            return response.change(
              headers: <String, String>{
                ...response.headers,
                'cache-control': 'no-store',
                'x-content-type-options': 'nosniff',
                'referrer-policy': 'no-referrer',
              },
            );
          },
        )
        .addHandler(staticHandler);
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    _server = await shelf_io.serve(
      handler,
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
