import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:path/path.dart' as p;

import '../evidence/deterministic_devex_bundle.dart';
import '../io/bounded_utf8_line_decoder.dart';
import '../source/local_source_adapters.dart';

final class ReadOnlyMcpServer {
  ReadOnlyMcpServer({required String workspaceRoot})
    : workspaceRoot = _mcpSafeRoot(workspaceRoot);

  static const String protocolVersion = '2026-07-28';
  static const int maxMessageBytes = 1024 * 1024;

  final Directory workspaceRoot;

  Future<void> serve(Stream<List<int>> input, IOSink output) async {
    try {
      await for (final line in const BoundedUtf8LineDecoder(
        maxLineBytes: maxMessageBytes,
      ).bind(input)) {
        if (line.trim().isEmpty) continue;
        Map<String, Object?> response;
        try {
          final value = jsonDecode(line);
          if (value is! Map<String, Object?>) {
            throw const FormatException('Request must be an object');
          }
          response = await handle(value);
        } on FormatException catch (error) {
          response = _error(null, -32700, 'Parse error', <String, Object?>{
            'reason': error.message,
          });
        } on Object {
          response = _error(null, -32603, 'Internal error');
        }
        output.writeln(jsonEncode(response));
        await output.flush();
      }
    } on FormatException catch (error) {
      output.writeln(
        jsonEncode(
          _error(null, -32700, 'Parse error', <String, Object?>{
            'reason': error.message,
          }),
        ),
      );
      await output.flush();
    }
  }

  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    final id = request['id'];
    if (request['jsonrpc'] != '2.0' || (id is! String && id is! int)) {
      return _error(id, -32600, 'Invalid Request');
    }
    final Object responseId = id!;
    final method = request['method'];
    if (method is! String) return _error(responseId, -32600, 'Invalid Request');
    if (method == 'server/discover') {
      return _result(responseId, <String, Object?>{
        'resultType': 'complete',
        'supportedVersions': const <String>[protocolVersion],
        'capabilities': const <String, Object?>{'tools': <String, Object?>{}},
        'serverInfo': const <String, Object?>{
          'name': 'devex-kit',
          'version': '0.1.0-dev',
        },
        'instructions':
            'Read-only local source, impact, and bundle verification tools. No mutation is exposed.',
      });
    }
    final metaFailure = _validateMeta(request['_meta']);
    if (metaFailure != null) return _error(responseId, -32602, metaFailure);
    switch (method) {
      case 'tools/list':
        return _result(responseId, <String, Object?>{
          'resultType': 'complete',
          'tools': _tools,
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      case 'tools/call':
        return _call(responseId, request['params']);
      default:
        return _error(responseId, -32601, 'Method not found');
    }
  }

  Future<Map<String, Object?>> _call(Object id, Object? value) async {
    if (value is! Map<String, Object?> ||
        value['name'] is! String ||
        value['arguments'] is! Map<String, Object?>) {
      return _error(id, -32602, 'Invalid tools/call params');
    }
    final name = value['name']! as String;
    final arguments = value['arguments']! as Map<String, Object?>;
    try {
      final Object? structured;
      switch (name) {
        case 'devex.source.inspect':
          _exactKeys(arguments, const <String>{'adapter', 'revision'});
          final adapter = _requiredString(arguments, 'adapter');
          final revision = arguments['revision'];
          if (revision != null && revision is! String) {
            throw const FormatException('revision must be a string');
          }
          structured = switch (adapter) {
            'filesystem' =>
              const FilesystemSourceAdapter()
                  .inspect(root: workspaceRoot.path)
                  .toJson(),
            'git' => (await const GitSourceAdapter().inspect(
              root: workspaceRoot.path,
              revision: revision as String?,
            )).toJson(),
            _ => throw const FormatException(
              'adapter must be filesystem or git',
            ),
          };
        case 'devex.source.diff':
          _exactKeys(arguments, const <String>{'base', 'current'});
          structured = const SourceImpactEngine()
              .diff(
                SourceSnapshot.fromJson(arguments['base']),
                SourceSnapshot.fromJson(arguments['current']),
              )
              .toJson();
        case 'devex.impact.plan':
          _exactKeys(arguments, const <String>{'changeSet', 'bindings'});
          final bindings = arguments['bindings'];
          if (bindings is! List<Object?>) {
            throw const FormatException('bindings must be an array');
          }
          structured = const SourceImpactEngine()
              .plan(
                ChangeSet.fromJson(arguments['changeSet']),
                bindings.map(SourceBinding.fromJson).toList(growable: false),
              )
              .toJson();
        case 'devex.bundle.verify':
          _exactKeys(arguments, const <String>{'path'});
          final file = _workspaceFile(_requiredString(arguments, 'path'));
          final verified = const DeterministicDevExBundleRepository().verify(
            file.path,
          );
          structured = <String, Object?>{
            'path': p
                .relative(verified.path, from: workspaceRoot.path)
                .replaceAll(p.separator, '/'),
            'archiveDigest': verified.archiveDigest.value,
            'size': verified.size,
            'manifest': verified.manifest.toJson(),
          };
        default:
          return _error(id, -32602, 'Unknown tool: $name');
      }
      final encoded = const JcsCanonicalizer().canonicalize(structured);
      return _result(id, <String, Object?>{
        'resultType': 'complete',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': encoded},
        ],
        'structuredContent': structured,
        'isError': false,
      });
    } on FormatException catch (error) {
      return _toolError(id, error.message);
    } on FileSystemException catch (error) {
      return _toolError(id, error.message);
    } on ArgumentError catch (error) {
      return _toolError(id, '${error.message}');
    }
  }

  String? _validateMeta(Object? value) {
    if (value is! Map<String, Object?>) return 'Request _meta is required';
    if (value['io.modelcontextprotocol/protocolVersion'] != protocolVersion) {
      return 'Unsupported MCP protocol version';
    }
    final client = value['io.modelcontextprotocol/clientInfo'];
    final capabilities = value['io.modelcontextprotocol/clientCapabilities'];
    if (client is! Map<String, Object?> ||
        client['name'] is! String ||
        client['version'] is! String ||
        capabilities is! Map<String, Object?>) {
      return 'MCP client metadata is incomplete';
    }
    return null;
  }

  File _workspaceFile(String relative) {
    if (p.isAbsolute(relative) || relative.contains('\u0000')) {
      throw const FormatException('path must be workspace-relative');
    }
    final normalized = p.normalize(p.join(workspaceRoot.path, relative));
    if (!p.isWithin(workspaceRoot.path, normalized) ||
        Link(normalized).existsSync()) {
      throw const FormatException('path escapes the workspace or is linked');
    }
    return File(normalized);
  }

  void _exactKeys(Map<String, Object?> value, Set<String> allowed) {
    final unknown = value.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown arguments: ${unknown.join(', ')}');
    }
  }

  String _requiredString(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return result;
  }

  Map<String, Object?> _toolError(Object id, String message) =>
      _result(id, <String, Object?>{
        'resultType': 'complete',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': message},
        ],
        'isError': true,
      });

  Map<String, Object?> _result(Object id, Object? result) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, Object?> _error(
    Object? id,
    int code,
    String message, [
    Object? data,
  ]) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message, 'data': ?data},
  };

  static const List<Map<String, Object?>> _tools = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'devex.bundle.verify',
      'title': 'Verify DevEx bundle',
      'description':
          'Verify a workspace-local .devexbundle offline without extracting it.',
      'inputSchema': <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{'type': 'string'},
        },
        'required': <String>['path'],
        'additionalProperties': false,
      },
      'annotations': <String, Object?>{
        'readOnlyHint': true,
        'destructiveHint': false,
        'idempotentHint': true,
      },
    },
    <String, Object?>{
      'name': 'devex.impact.plan',
      'title': 'Plan source impact',
      'description':
          'Compute conservative direct and transitive impact from an inline ChangeSet and bindings.',
      'inputSchema': <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': <String, Object?>{
          'changeSet': <String, Object?>{'type': 'object'},
          'bindings': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'object'},
          },
        },
        'required': <String>['changeSet', 'bindings'],
        'additionalProperties': false,
      },
      'annotations': <String, Object?>{
        'readOnlyHint': true,
        'destructiveHint': false,
        'idempotentHint': true,
      },
    },
    <String, Object?>{
      'name': 'devex.source.diff',
      'title': 'Diff source snapshots',
      'description':
          'Diff two inline SourceSnapshot documents without reading or writing files.',
      'inputSchema': <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': <String, Object?>{
          'base': <String, Object?>{'type': 'object'},
          'current': <String, Object?>{'type': 'object'},
        },
        'required': <String>['base', 'current'],
        'additionalProperties': false,
      },
      'annotations': <String, Object?>{
        'readOnlyHint': true,
        'destructiveHint': false,
        'idempotentHint': true,
      },
    },
    <String, Object?>{
      'name': 'devex.source.inspect',
      'title': 'Inspect workspace source',
      'description':
          'Create an in-memory filesystem or Git SourceSnapshot of the configured workspace root.',
      'inputSchema': <String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': <String, Object?>{
          'adapter': <String, Object?>{
            'enum': <String>['filesystem', 'git'],
          },
          'revision': <String, Object?>{'type': 'string'},
        },
        'required': <String>['adapter'],
        'additionalProperties': false,
      },
      'annotations': <String, Object?>{
        'readOnlyHint': true,
        'destructiveHint': false,
        'idempotentHint': true,
      },
    },
  ];
}

Directory _mcpSafeRoot(String value) {
  final root = Directory(value).absolute;
  if (Link(root.path).existsSync() || !root.existsSync()) {
    throw FileSystemException(
      'MCP workspace root is missing or linked',
      root.path,
    );
  }
  return Directory(root.resolveSymbolicLinksSync());
}
