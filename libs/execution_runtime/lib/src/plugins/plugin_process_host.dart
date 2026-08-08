import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../io/bounded_utf8_line_decoder.dart';

final class PluginInvocationException implements Exception {
  const PluginInvocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class PluginInvocationResult {
  const PluginInvocationResult({
    required this.pluginId,
    required this.capability,
    required this.protocolVersion,
    required this.result,
  });
  final String pluginId;
  final String capability;
  final int protocolVersion;
  final Object? result;
}

/// Runs untrusted plugins as one-shot, capability-scoped child processes.
///
/// The current process host supports Linux/bubblewrap only. The sandbox has no network namespace,
/// inherited environment, workspace mount, home directory or credential store.
final class PluginProcessHost {
  PluginProcessHost({
    required String pluginRoot,
    this.timeout = const Duration(seconds: 10),
  }) : pluginRoot = _safePluginRoot(pluginRoot);

  static const int protocolVersion = 1;
  static const int maxMessageBytes = 1024 * 1024;

  final Directory pluginRoot;
  final Duration timeout;

  Future<PluginInvocationResult> invoke({
    required PluginManifest manifest,
    required String capability,
    required Map<String, Object?> arguments,
    Set<String> grants = const <String>{},
    Digest? previewDigest,
  }) async {
    final declared = manifest.capabilities
        .where((item) => item.name == capability)
        .firstOrNull;
    if (declared == null) {
      throw const PluginInvocationException(
        'Plugin capability is not declared',
      );
    }
    if (!manifest.protocolVersions.contains(protocolVersion)) {
      throw const PluginInvocationException(
        'Plugin protocol version is incompatible',
      );
    }
    if (declared.mutating &&
        (!grants.contains(capability) || previewDigest == null)) {
      throw const PluginInvocationException(
        'Mutating plugin capability requires preview digest and explicit grant',
      );
    }
    final executable = _resolveExecutable(manifest.executable);
    final bwrap = File('/usr/bin/bwrap');
    if (!Platform.isLinux || !bwrap.existsSync()) {
      throw const PluginInvocationException(
        'A Linux bubblewrap sandbox is required for dynamic plugins',
      );
    }
    final sandboxArguments = <String>[
      '--unshare-all',
      '--die-with-parent',
      '--new-session',
      '--clearenv',
      '--ro-bind',
      '/usr',
      '/usr',
      if (Directory('/lib').existsSync()) ...<String>[
        '--ro-bind',
        '/lib',
        '/lib',
      ],
      if (Directory('/lib64').existsSync()) ...<String>[
        '--ro-bind',
        '/lib64',
        '/lib64',
      ],
      if (File('/etc/ld.so.cache').existsSync()) ...<String>[
        '--ro-bind',
        '/etc/ld.so.cache',
        '/etc/ld.so.cache',
      ],
      '--ro-bind',
      executable.path,
      '/plugin',
      '--proc',
      '/proc',
      '--dev',
      '/dev',
      '--tmpfs',
      '/tmp',
      '--dir',
      '/home',
      '--chdir',
      '/tmp',
      '--setenv',
      'PATH',
      '/usr/bin:/bin',
      '/plugin',
    ];
    final process = await Process.start(
      bwrap.path,
      sandboxArguments,
      environment: const <String, String>{},
      includeParentEnvironment: false,
    );
    final lines = StreamIterator<String>(
      const BoundedUtf8LineDecoder(
        maxLineBytes: maxMessageBytes,
      ).bind(process.stdout),
    );
    final stderr = _boundedStderr(process.stderr);
    var closed = false;
    try {
      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'plugin.initialize',
          'params': <String, Object?>{
            'protocolVersion': protocolVersion,
            'pluginId': manifest.id,
            'capability': capability,
            'effect': declared.effect.name,
          },
        }),
      );
      await process.stdin.flush();
      final initialized = await _next(lines, process, stderr);
      final initResult = _response(initialized, 1);
      if (initResult is! Map<String, Object?> ||
          initResult['protocolVersion'] != protocolVersion ||
          initResult['pluginId'] != manifest.id) {
        throw const PluginInvocationException(
          'Plugin negotiation response is invalid',
        );
      }
      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'plugin.invoke',
          'params': <String, Object?>{
            'capability': capability,
            'arguments': arguments,
            if (previewDigest != null) 'previewDigest': previewDigest.value,
          },
        }),
      );
      await process.stdin.flush();
      final invoked = await _next(lines, process, stderr);
      final result = _response(invoked, 2);
      await process.stdin.close();
      closed = true;
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          throw const PluginInvocationException(
            'Plugin did not terminate after its one-shot result',
          );
        },
      );
      if (await lines.moveNext()) {
        throw const PluginInvocationException(
          'Plugin emitted more than one terminal result',
        );
      }
      if (exitCode != 0) {
        throw PluginInvocationException(
          'Plugin exited with $exitCode: ${await stderr}',
        );
      }
      return PluginInvocationResult(
        pluginId: manifest.id,
        capability: capability,
        protocolVersion: protocolVersion,
        result: result,
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw const PluginInvocationException('Plugin invocation timed out');
    } finally {
      if (!closed) {
        await process.stdin.close().catchError((_) {});
        process.kill(ProcessSignal.sigkill);
      }
      await lines.cancel();
    }
  }

  Future<String> _next(
    StreamIterator<String> lines,
    Process process,
    Future<String> stderr,
  ) async {
    final hasLine = await lines.moveNext().timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw const PluginInvocationException('Plugin response timed out');
      },
    );
    if (!hasLine) {
      final exitCode = await process.exitCode;
      throw PluginInvocationException(
        'Plugin closed before responding ($exitCode): ${await stderr}',
      );
    }
    return lines.current;
  }

  Object? _response(String source, int expectedId) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?> ||
        value['jsonrpc'] != '2.0' ||
        value['id'] != expectedId) {
      throw const PluginInvocationException(
        'Plugin returned an invalid JSON-RPC response',
      );
    }
    final unknown = value.keys.toSet().difference(const <String>{
      'jsonrpc',
      'id',
      'result',
      'error',
    });
    if (unknown.isNotEmpty ||
        value.containsKey('result') == value.containsKey('error')) {
      throw const PluginInvocationException(
        'Plugin returned an ambiguous JSON-RPC response',
      );
    }
    if (value.containsKey('error')) {
      throw PluginInvocationException('Plugin error: ${value['error']}');
    }
    return value['result'];
  }

  File _resolveExecutable(String value) {
    if (p.isAbsolute(value)) {
      throw const PluginInvocationException(
        'Plugin executable must be plugin-root-relative',
      );
    }
    final normalized = p.normalize(p.join(pluginRoot.path, value));
    if (!p.isWithin(pluginRoot.path, normalized) ||
        Link(normalized).existsSync()) {
      throw const PluginInvocationException(
        'Plugin executable escapes its configured root',
      );
    }
    final file = File(normalized);
    if (!file.existsSync() ||
        file.statSync().type != FileSystemEntityType.file) {
      throw const PluginInvocationException('Plugin executable is missing');
    }
    final resolved = File(file.resolveSymbolicLinksSync());
    if (!p.isWithin(pluginRoot.path, resolved.path)) {
      throw const PluginInvocationException(
        'Plugin executable resolves outside its configured root',
      );
    }
    return resolved;
  }

  Future<String> _boundedStderr(Stream<List<int>> stream) async {
    const limit = 64 * 1024;
    final bytes = <int>[];
    await for (final chunk in stream) {
      final remaining = limit - bytes.length;
      if (remaining > 0) bytes.addAll(chunk.take(remaining));
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}

Directory _safePluginRoot(String value) {
  final root = Directory(value).absolute;
  if (Link(root.path).existsSync() || !root.existsSync()) {
    throw FileSystemException('Plugin root is missing or linked', root.path);
  }
  return Directory(root.resolveSymbolicLinksSync());
}
