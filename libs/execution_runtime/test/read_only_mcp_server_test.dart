import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ReadOnlyMcpServer server;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('workspace-mcp-test.');
    File(p.join(temp.path, 'source.txt')).writeAsStringSync('safe');
    server = ReadOnlyMcpServer(workspaceRoot: temp.path);
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Map<String, Object?> request(
    String method, {
    Object? params,
    String clientName = 'test',
  }) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': 1,
    'method': method,
    'params': ?params,
    '_meta': <String, Object?>{
      'io.modelcontextprotocol/protocolVersion':
          ReadOnlyMcpServer.protocolVersion,
      'io.modelcontextprotocol/clientInfo': <String, Object?>{
        'name': clientName,
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
          'evidence.bundle.verify',
          'source.diff',
          'source.impact.plan',
          'source.inspect',
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
            'name': 'source.inspect',
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
            'name': 'distribution.release.seal',
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

  test(
    'pins client attribution for the lifetime of one stdio session',
    () async {
      final first = await server.handle(request('tools/list'));
      expect(first['error'], isNull);

      final changed = await server.handle(
        request('tools/list', clientName: 'different-client'),
      );
      final error = changed['error']! as Map<String, Object?>;
      expect(error['code'], -32602);
      expect(error['message'], 'MCP client identity changed');
    },
  );

  test('bundle verification rejects a linked ancestor', () async {
    if (Platform.isWindows) return;
    final outside = Directory.systemTemp.createTempSync(
      'workspace-mcp-outside.',
    );
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync(recursive: true);
    });
    File(
      p.join(outside.path, 'outside.evidence.zip'),
    ).writeAsStringSync('outside');
    Link(p.join(temp.path, 'linked')).createSync(outside.path);
    final response = await server.handle(
      request(
        'tools/call',
        params: <String, Object?>{
          'name': 'evidence.bundle.verify',
          'arguments': <String, Object?>{'path': 'linked/outside.evidence.zip'},
        },
      ),
    );
    final result = response['result']! as Map<String, Object?>;
    expect(result['isError'], isTrue);
    expect(
      ((result['content']! as List<Object?>).single!
          as Map<String, Object?>)['text'],
      'invalidRequest',
    );
  });

  test(
    'merges typed Experience tools and resources without exposing client identity',
    () async {
      final backend = _FakeExperienceBackend();
      server = ReadOnlyMcpServer(
        workspaceRoot: temp.path,
        experienceBackend: backend,
        connectionEpoch: 'epoch-a',
      );
      final listed = await server.handle(request('tools/list'));
      final tools =
          ((listed['result']! as Map<String, Object?>)['tools']!
                  as List<Map<String, Object?>>)
              .map((tool) => tool['name'])
              .toList();
      expect(tools, contains('catalog.list'));
      expect(tools, orderedEquals(tools.toList()..sort()));

      final resources = await server.handle(request('resources/list'));
      expect(
        (resources['result']! as Map<String, Object?>)['resources'],
        backend.resources,
      );
      final read = await server.handle(
        request(
          'resources/read',
          params: <String, Object?>{'uri': 'experience://catalog'},
        ),
      );
      expect(read['error'], isNull);

      final called = await server.handle(
        request(
          'tools/call',
          params: <String, Object?>{
            'name': 'catalog.list',
            'arguments': <String, Object?>{},
          },
        ),
      );
      expect((called['result']! as Map<String, Object?>)['isError'], isFalse);
      expect(backend.connectionEpoch, 'epoch-a');
      expect(backend.principalId, startsWith('sha256:'));
      expect(backend.principalId, isNot(contains('test')));
    },
  );

  test(
    'bounds backend results and closes its connection epoch when input ends',
    () async {
      final backend = _FakeExperienceBackend(oversize: true);
      final outputFile = File(p.join(temp.path, 'mcp-output.jsonl'));
      final sink = outputFile.openWrite();
      server = ReadOnlyMcpServer(
        workspaceRoot: temp.path,
        experienceBackend: backend,
        connectionEpoch: 'epoch-close',
      );
      final encodedRequest = jsonEncode(
        request(
          'tools/call',
          params: <String, Object?>{
            'name': 'catalog.list',
            'arguments': <String, Object?>{},
          },
        ),
      );
      await server.serve(
        Stream<List<int>>.value(utf8.encode('$encodedRequest\n')),
        sink,
      );
      await sink.close();

      final response =
          jsonDecode(outputFile.readAsLinesSync().single)
              as Map<String, Object?>;
      final result = response['result']! as Map<String, Object?>;
      expect(result['isError'], isTrue);
      expect(
        ((result['content']! as List<Object?>).single!
            as Map<String, Object?>)['text'],
        'resultQuotaExceeded',
      );
      expect(backend.closedEpochs, <String>['epoch-close']);
    },
  );

  test('preserves request id when a backend fails unexpectedly', () async {
    final backend = _FakeExperienceBackend(throwUnexpected: true);
    final outputFile = File(p.join(temp.path, 'mcp-error-output.jsonl'));
    final sink = outputFile.openWrite();
    server = ReadOnlyMcpServer(
      workspaceRoot: temp.path,
      experienceBackend: backend,
      connectionEpoch: 'epoch-error',
    );
    final encodedRequest = jsonEncode(
      request(
        'tools/call',
        params: <String, Object?>{
          'name': 'catalog.list',
          'arguments': <String, Object?>{},
        },
      ),
    );
    await server.serve(
      Stream<List<int>>.value(utf8.encode('$encodedRequest\n')),
      sink,
    );
    await sink.close();

    final response =
        jsonDecode(outputFile.readAsLinesSync().single) as Map<String, Object?>;
    expect(response['id'], 1);
    final error = response['error']! as Map<String, Object?>;
    expect(error['code'], -32603);
    expect(error['message'], 'Internal error');
    expect(backend.closedEpochs, <String>['epoch-error']);
  });

  test('bounds the complete encoded response line', () async {
    final backend = _FakeExperienceBackend(payloadBytes: 600 * 1024);
    final outputFile = File(p.join(temp.path, 'mcp-bounded-output.jsonl'));
    final sink = outputFile.openWrite();
    server = ReadOnlyMcpServer(
      workspaceRoot: temp.path,
      experienceBackend: backend,
      connectionEpoch: 'epoch-bounded',
    );
    final encodedRequest = jsonEncode(
      request(
        'tools/call',
        params: <String, Object?>{
          'name': 'catalog.list',
          'arguments': <String, Object?>{},
        },
      ),
    );
    await server.serve(
      Stream<List<int>>.value(utf8.encode('$encodedRequest\n')),
      sink,
    );
    await sink.close();

    final line = outputFile.readAsLinesSync().single;
    expect(utf8.encode(line).length, lessThanOrEqualTo(1024 * 1024));
    final response = jsonDecode(line) as Map<String, Object?>;
    expect(response['id'], 1);
    final error = response['error']! as Map<String, Object?>;
    expect(error['code'], -32603);
    expect(error['message'], 'Response exceeds 1 MiB limit');
  });
}

final class _FakeExperienceBackend implements ExperienceMcpBackend {
  _FakeExperienceBackend({
    this.oversize = false,
    this.throwUnexpected = false,
    this.payloadBytes,
  });

  final bool oversize;
  final bool throwUnexpected;
  final int? payloadBytes;
  String? principalId;
  String? connectionEpoch;
  final List<String> closedEpochs = <String>[];

  @override
  List<Map<String, Object?>> get resources => <Map<String, Object?>>[
    <String, Object?>{
      'uri': 'experience://catalog',
      'name': 'Catalog',
      'mimeType': 'application/json',
    },
  ];

  @override
  List<Map<String, Object?>> get tools => <Map<String, Object?>>[
    <String, Object?>{
      'name': 'catalog.list',
      'description': 'List catalog',
      'inputSchema': <String, Object?>{'type': 'object'},
      'annotations': <String, Object?>{'readOnlyHint': true},
    },
  ];

  @override
  Future<Object?> call({
    required String name,
    required Map<String, Object?> arguments,
    required String principalId,
    required String connectionEpoch,
  }) async {
    this.principalId = principalId;
    this.connectionEpoch = connectionEpoch;
    if (throwUnexpected) throw StateError('synthetic backend failure');
    return <String, Object?>{
      'items': <String>[
        if (oversize)
          'x' * (ReadOnlyMcpServer.maxMessageBytes + 1)
        else if (payloadBytes != null)
          'x' * payloadBytes!,
      ],
    };
  }

  @override
  Future<void> close({required String connectionEpoch}) async {
    closedEpochs.add(connectionEpoch);
  }

  @override
  Future<Object?> readResource({
    required String uri,
    required String principalId,
  }) async => <String, Object?>{'kind': 'CatalogManifest'};
}
