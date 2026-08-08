import 'dart:io';

import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ReadOnlyMcpServer server;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('devex-mcp-test.');
    File(p.join(temp.path, 'source.txt')).writeAsStringSync('safe');
    server = ReadOnlyMcpServer(workspaceRoot: temp.path);
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Map<String, Object?> request(String method, {Object? params}) =>
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': ?params,
        '_meta': <String, Object?>{
          'io.modelcontextprotocol/protocolVersion':
              ReadOnlyMcpServer.protocolVersion,
          'io.modelcontextprotocol/clientInfo': <String, Object?>{
            'name': 'test',
            'version': '1',
          },
          'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
        },
      };

  test(
    'implements stateless discovery and deterministic read-only tools list',
    () async {
      final discovery = await server.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'discover',
        'method': 'server/discover',
      });
      final result = discovery['result']! as Map<String, Object?>;
      expect(result['supportedVersions'], <String>[
        ReadOnlyMcpServer.protocolVersion,
      ]);

      final listed = await server.handle(request('tools/list'));
      final listResult = listed['result']! as Map<String, Object?>;
      final tools = listResult['tools']! as List<Map<String, Object?>>;
      expect(
        tools.map((tool) => tool['name']),
        orderedEquals(<String>[
          'devex.bundle.verify',
          'devex.impact.plan',
          'devex.source.diff',
          'devex.source.inspect',
        ]),
      );
      expect(
        tools.every(
          (tool) =>
              (tool['annotations']! as Map<String, Object?>)['readOnlyHint'] ==
              true,
        ),
        isTrue,
      );
      expect(listResult['ttlMs'], 300000);
    },
  );

  test(
    'source inspect is bounded to configured workspace and has no mutation tool',
    () async {
      final called = await server.handle(
        request(
          'tools/call',
          params: <String, Object?>{
            'name': 'devex.source.inspect',
            'arguments': <String, Object?>{'adapter': 'filesystem'},
          },
        ),
      );
      final result = called['result']! as Map<String, Object?>;
      expect(result['isError'], isFalse);
      final structured = result['structuredContent']! as Map<String, Object?>;
      expect(structured['kind'], 'SourceSnapshot');

      final unknown = await server.handle(
        request(
          'tools/call',
          params: <String, Object?>{
            'name': 'devex.release.seal',
            'arguments': <String, Object?>{},
          },
        ),
      );
      expect((unknown['error']! as Map<String, Object?>)['code'], -32602);
    },
  );

  test('rejects missing per-request metadata', () async {
    final response = await server.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    expect((response['error']! as Map<String, Object?>)['code'], -32602);
  });
}
