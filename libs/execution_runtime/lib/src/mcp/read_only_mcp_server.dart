import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../evidence/deterministic_evidence_bundle.dart';
import '../io/bounded_utf8_line_decoder.dart';
import '../source/local_source_adapters.dart';
import 'experience_mcp_backend.dart';

final class ReadOnlyMcpServer {
  ReadOnlyMcpServer({
    required String workspaceRoot,
    this.experienceBackend,
    String? connectionEpoch,
  }) : workspaceRoot = _mcpSafeRoot(workspaceRoot),
       connectionEpoch =
           connectionEpoch ??
           'mcp-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';

  static const String protocolVersion = '2026-07-28';
  static const int maxMessageBytes = 1024 * 1024;

  final Directory workspaceRoot;
  final ExperienceMcpBackend? experienceBackend;
  final String connectionEpoch;
  String? _connectionPrincipalId;

  Future<void> serve(Stream<List<int>> input, IOSink output) async {
    try {
      await for (final line in const BoundedUtf8LineDecoder(
        maxLineBytes: maxMessageBytes,
      ).bind(input)) {
        if (line.trim().isEmpty) continue;
        Map<String, Object?> response;
        Object? requestId;
        try {
          final value = jsonDecode(line);
          if (value is! Map<String, Object?>) {
            throw const FormatException('Request must be an object');
          }
          requestId = value['id'];
          response = await handle(value);
        } on FormatException catch (error) {
          response = _error(requestId, -32700, 'Parse error', <String, Object?>{
            'reason': error.message,
          });
        } on Object {
          response = _error(requestId, -32603, 'Internal error');
        }
        output.writeln(_encodeResponse(response));
        await output.flush();
      }
    } on FormatException catch (error) {
      output.writeln(
        _encodeResponse(
          _error(null, -32700, 'Parse error', <String, Object?>{
            'reason': error.message,
          }),
        ),
      );
      await output.flush();
    } finally {
      await experienceBackend?.close(connectionEpoch: connectionEpoch);
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
        'capabilities': <String, Object?>{
          'tools': <String, Object?>{},
          if (experienceBackend != null) 'resources': <String, Object?>{},
        },
        'serverInfo': const <String, Object?>{
          'name': 'full-local',
          'version': '0.1.0-dev',
        },
        'instructions': experienceBackend == null
            ? 'Read-only local source, impact, and bundle verification tools. No mutation is exposed.'
            : 'Typed local Experience tools. Effects require scoped single-use capabilities.',
      });
    }
    final metaFailure = _validateMeta(request['_meta']);
    if (metaFailure != null) return _error(responseId, -32602, metaFailure);
    final principalId = _principalId(request['_meta']);
    final boundPrincipalId = _connectionPrincipalId;
    if (boundPrincipalId == null) {
      _connectionPrincipalId = principalId;
    } else if (boundPrincipalId != principalId) {
      return _error(responseId, -32602, 'MCP client identity changed');
    }
    switch (method) {
      case 'tools/list':
        return _result(responseId, <String, Object?>{
          'resultType': 'complete',
          'tools':
              <Map<String, Object?>>[..._tools, ...?experienceBackend?.tools]
                ..sort(
                  (left, right) => (left['name']! as String).compareTo(
                    right['name']! as String,
                  ),
                ),
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      case 'tools/call':
        return _call(responseId, request['params'], principalId: principalId);
      case 'resources/list':
        final backend = experienceBackend;
        if (backend == null) {
          return _error(responseId, -32601, 'Method not found');
        }
        return _result(responseId, <String, Object?>{
          'resources': backend.resources,
          'resultType': 'complete',
        });
      case 'resources/read':
        final backend = experienceBackend;
        final params = request['params'];
        if (backend == null) {
          return _error(responseId, -32601, 'Method not found');
        }
        if (params is! Map<String, Object?> ||
            params.keys.toSet().difference(const <String>{'uri'}).isNotEmpty ||
            params['uri'] is! String) {
          return _error(responseId, -32602, 'Invalid resources/read params');
        }
        try {
          final resource = await backend.readResource(
            uri: params['uri']! as String,
            principalId: principalId,
          );
          final encoded = _boundedStructured(resource);
          return _result(responseId, <String, Object?>{
            'contents': <Object?>[
              <String, Object?>{
                'uri': params['uri'],
                'mimeType': 'application/json',
                'text': encoded,
              },
            ],
          });
        } on ExperienceMcpToolException catch (error) {
          return _toolError(responseId, error.code, error.details);
        } on FormatException {
          return _toolError(responseId, 'invalidRequest');
        }
      default:
        return _error(responseId, -32601, 'Method not found');
    }
  }

  Future<Map<String, Object?>> _call(
    Object id,
    Object? value, {
    required String principalId,
  }) async {
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
        case 'source.inspect':
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
        case 'source.diff':
          _exactKeys(arguments, const <String>{'base', 'current'});
          structured = const SourceImpactEngine()
              .diff(
                SourceSnapshot.fromJson(arguments['base']),
                SourceSnapshot.fromJson(arguments['current']),
              )
              .toJson();
        case 'source.impact.plan':
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
        case 'evidence.bundle.verify':
          _exactKeys(arguments, const <String>{'path'});
          final file = _workspaceFile(_requiredString(arguments, 'path'));
          final verified = const DeterministicEvidenceBundleRepository().verify(
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
          final backend = experienceBackend;
          if (backend == null ||
              !backend.tools.any((tool) => tool['name'] == name)) {
            return _error(id, -32602, 'Unknown tool');
          }
          structured = await backend.call(
            name: name,
            arguments: arguments,
            principalId: principalId,
            connectionEpoch: connectionEpoch,
          );
      }
      final encoded = _boundedStructured(structured);
      return _result(id, <String, Object?>{
        'resultType': 'complete',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': encoded},
        ],
        'structuredContent': structured,
        'isError': false,
      });
    } on ExperienceMcpToolException catch (error) {
      return _toolError(id, error.code, error.details);
    } on FormatException {
      return _toolError(id, 'invalidRequest');
    } on FileSystemException {
      return _toolError(id, 'filesystemUnavailable');
    } on ArgumentError {
      return _toolError(id, 'invalidRequest');
    }
  }

  String _boundedStructured(Object? value) {
    final encoded = const JcsCanonicalizer().canonicalize(value);
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const ExperienceMcpToolException('resultQuotaExceeded');
    }
    return encoded;
  }

  String _encodeResponse(Map<String, Object?> response) {
    final encoded = jsonEncode(response);
    if (utf8.encode(encoded).length <= maxMessageBytes) return encoded;
    return jsonEncode(
      _error(response['id'], -32603, 'Response exceeds 1 MiB limit'),
    );
  }

  String _principalId(Object? meta) {
    final client =
        (meta! as Map<String, Object?>)['io.modelcontextprotocol/clientInfo']!
            as Map<String, Object?>;
    return Digest.semantic(<String, Object?>{
      'name': client['name'],
      'version': client['version'],
    }).value;
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
    if (!p.isWithin(workspaceRoot.path, normalized)) {
      throw const FormatException('path escapes the workspace or is linked');
    }
    final file = File(normalized);
    if (!file.existsSync()) {
      throw const FormatException('path is missing');
    }
    var current = workspaceRoot.path;
    for (final segment in p.split(p.relative(normalized, from: current))) {
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('path crosses a link');
      }
    }
    final resolved = file.resolveSymbolicLinksSync();
    if (!p.isWithin(workspaceRoot.path, resolved) ||
        File(resolved).statSync().type != FileSystemEntityType.file) {
      throw const FormatException('path escapes the workspace or is linked');
    }
    return File(resolved);
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

  Map<String, Object?> _toolError(
    Object id,
    String message, [
    Object? details,
  ]) => _result(id, <String, Object?>{
    'resultType': 'complete',
    'content': <Object?>[
      <String, Object?>{'type': 'text', 'text': message},
    ],
    'structuredContent': <String, Object?>{
      'errorCode': message,
      'details': ?details,
    },
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
      'name': 'evidence.bundle.verify',
      'title': 'Verify evidence bundle',
      'description':
          'Verify a workspace-local .evidence.zip offline without extracting it.',
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
      'name': 'source.impact.plan',
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
      'name': 'source.diff',
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
      'name': 'source.inspect',
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
