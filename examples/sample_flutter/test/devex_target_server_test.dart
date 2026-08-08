import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'serves built assets and rejects unsafe or unsupported requests',
    () async {
      final sampleRoot = _sampleRoot();
      final fixture = Directory(
        '${sampleRoot.path}/.dart_tool/'
        'devex_target_server_test_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      File(
        '${fixture.path}/index.html',
      ).writeAsStringSync('<main>Target</main>');
      File('${fixture.path}/app.js').writeAsStringSync('const ready = true;');

      final process = await Process.start('dart', <String>[
        'run',
        '${sampleRoot.path}/tool/devex_target_server.dart',
        '--root=${fixture.path}',
        '--port=0',
        '--frame-ancestor=http://127.0.0.1:7368',
      ], workingDirectory: sampleRoot.path);
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final ready = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .first
            .timeout(const Duration(seconds: 15));
        final origin = Uri.parse(ready['origin']! as String);

        Future<HttpClientResponse> request(String method, String path) async {
          final request = await client.openUrl(method, origin.resolve(path));
          return request.close();
        }

        final health = await request('GET', '/health');
        expect(health.statusCode, HttpStatus.ok);
        expect(await utf8.decodeStream(health), '{"status":"ready"}');

        final index = await request('GET', '/');
        expect(index.statusCode, HttpStatus.ok);
        expect(await utf8.decodeStream(index), '<main>Target</main>');
        expect(index.headers.value('cache-control'), 'no-store');
        expect(index.headers.value('x-content-type-options'), 'nosniff');
        expect(index.headers.value('x-frame-options'), isNull);
        expect(
          index.headers.value('content-security-policy'),
          "frame-ancestors 'self' http://127.0.0.1:7368",
        );

        final spa = await request('GET', '/dashboard');
        expect(spa.statusCode, HttpStatus.ok);
        expect(await utf8.decodeStream(spa), '<main>Target</main>');

        final traversal = await request('GET', '/%2e%2e/pubspec.yaml');
        expect(traversal.statusCode, isNot(HttpStatus.ok));
        await traversal.drain<void>();

        final post = await request('POST', '/');
        expect(post.statusCode, HttpStatus.methodNotAllowed);
        expect(post.headers.value('allow'), 'GET, HEAD');
        await post.drain<void>();
      } finally {
        client.close(force: true);
        process.kill(ProcessSignal.sigint);
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return process.exitCode;
          },
        );
        expect(exitCode, 0, reason: stderrBuffer.toString());
        fixture.deleteSync(recursive: true);
      }
    },
  );
}

Directory _sampleRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final direct = File('${current.path}/tool/devex_target_server.dart');
    if (direct.existsSync() &&
        File('${current.path}/lib/main.dart').existsSync()) {
      return current;
    }
    final nested = Directory('${current.path}/examples/sample_flutter');
    if (File('${nested.path}/tool/devex_target_server.dart').existsSync()) {
      return nested;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate examples/sample_flutter');
    }
    current = parent;
  }
}
