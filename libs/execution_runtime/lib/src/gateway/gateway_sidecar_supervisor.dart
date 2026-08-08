import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../io/bounded_utf8_line_decoder.dart';
import '../storage/filesystem_workspace_store.dart';

final class GatewaySidecarHandle {
  const GatewaySidecarHandle({
    required this.id,
    required this.ownerSessionId,
    required this.dataOrigin,
    required this.planDigest,
    required this.routingTableDigest,
  });

  final String id;
  final String ownerSessionId;
  final Uri dataOrigin;
  final Digest planDigest;
  final Digest routingTableDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'ownerSessionId': ownerSessionId,
    'dataOrigin': dataOrigin.toString(),
    'planDigest': planDigest.value,
    'routingTableDigest': routingTableDigest.value,
  };
}

final class GatewaySidecarSupervisor {
  GatewaySidecarSupervisor({
    required this.workspaceRoot,
    required this.command,
    required List<String> arguments,
    required this.workingDirectory,
    required this.ids,
    this.operationTimeout = const Duration(seconds: 30),
    this.maxControlMessageBytes = 1024 * 1024,
    this.maxStderrBytes = 64 * 1024,
  }) : arguments = List<String>.unmodifiable(arguments) {
    if (!Directory(workspaceRoot).existsSync()) {
      throw FileSystemException('Workspace does not exist', workspaceRoot);
    }
    if (!Directory(workingDirectory).existsSync()) {
      throw FileSystemException(
        'Sidecar working directory does not exist',
        workingDirectory,
      );
    }
    if (command.isEmpty || operationTimeout <= Duration.zero) {
      throw ArgumentError('Invalid sidecar command or timeout');
    }
  }

  final String workspaceRoot;
  final String command;
  final List<String> arguments;
  final String workingDirectory;
  final IdGenerator ids;
  final Duration operationTimeout;
  final int maxControlMessageBytes;
  final int maxStderrBytes;
  final Map<String, _ManagedGatewaySidecar> _children =
      <String, _ManagedGatewaySidecar>{};

  int get activeCount => _children.length;

  List<GatewaySidecarHandle> get handles =>
      List<GatewaySidecarHandle>.unmodifiable(
        _children.values
            .where((child) => child.handle != null)
            .map((child) => child.handle!),
      );

  Future<GatewaySidecarHandle> start({
    required String ownerSessionId,
    required Uri targetOrigin,
    required CompiledGatewayPlan plan,
  }) async {
    if (ownerSessionId.isEmpty) {
      throw ArgumentError.value(ownerSessionId, 'ownerSessionId');
    }
    if (!targetOrigin.isAbsolute ||
        !const <String>{'http', 'https'}.contains(targetOrigin.scheme) ||
        (targetOrigin.host != 'localhost' &&
            InternetAddress.tryParse(targetOrigin.host)?.isLoopback != true) ||
        targetOrigin.userInfo.isNotEmpty ||
        targetOrigin.hasQuery ||
        targetOrigin.hasFragment ||
        (targetOrigin.path.isNotEmpty && targetOrigin.path != '/')) {
      throw ArgumentError.value(targetOrigin, 'targetOrigin');
    }
    _verifyFixtureBlobs(plan);
    final id = 'gateway-${ids.nextId()}';
    final process = await Process.start(
      command,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    final child = _ManagedGatewaySidecar(
      id: id,
      ownerSessionId: ownerSessionId,
      process: process,
      timeout: operationTimeout,
      maxMessageBytes: maxControlMessageBytes,
      maxStderrBytes: maxStderrBytes,
      onExit: () => _children.remove(id),
    );
    _children[id] = child;
    try {
      final initialized = await child.call(
        'gateway.initialize',
        <String, Object?>{
          'protocolVersion': 1,
          'gatewaySessionId': id,
          'workspaceRoot': workspaceRoot,
          'allowedOrigins': <String>[targetOrigin.origin],
          'plan': plan.toJson(),
        },
      );
      final result = _object(initialized, 'initialize result');
      final dataOrigin = canonicalScenarioLabGatewayDataOrigin(
        Uri.parse(_string(result, 'dataOrigin')),
      );
      final handle = GatewaySidecarHandle(
        id: id,
        ownerSessionId: ownerSessionId,
        dataOrigin: dataOrigin,
        planDigest: Digest(_string(result, 'planDigest')),
        routingTableDigest: Digest(_string(result, 'routingTableDigest')),
      );
      if (handle.planDigest != plan.digest) {
        throw const FormatException('Sidecar initialized another plan digest');
      }
      child.handle = handle;
      return handle;
    } on Object {
      await child.terminate();
      _children.remove(id);
      rethrow;
    }
  }

  Future<Object?> call(
    String gatewaySessionId,
    String method,
    Map<String, Object?> params,
  ) {
    final child = _children[gatewaySessionId];
    if (child == null) {
      throw StateError('Unknown GatewaySession $gatewaySessionId');
    }
    return child.call(method, params);
  }

  Future<void> stop(String gatewaySessionId) async {
    final child = _children.remove(gatewaySessionId);
    if (child == null) return;
    await child.stop();
  }

  Future<void> stopOwner(String ownerSessionId) async {
    final ids = _children.values
        .where((child) => child.ownerSessionId == ownerSessionId)
        .map((child) => child.id)
        .toList(growable: false);
    for (final id in ids) {
      await stop(id);
    }
  }

  Future<void> close() async {
    final ids = _children.keys.toList(growable: false);
    for (final id in ids) {
      await stop(id);
    }
  }

  void _verifyFixtureBlobs(CompiledGatewayPlan plan) {
    final store = FileSystemWorkspaceStore(workspaceRoot: workspaceRoot);
    for (final fixture in plan.fixtures) {
      final bytes = store.readBlob(fixture.bodyDigest);
      if (bytes == null ||
          bytes.length != fixture.bodySize ||
          Digest.bytes(bytes) != fixture.bodyDigest) {
        throw StateError('Fixture ${fixture.id} is absent or invalid in CAS');
      }
    }
  }

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  String _string(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return result;
  }
}

final class _ManagedGatewaySidecar {
  _ManagedGatewaySidecar({
    required this.id,
    required this.ownerSessionId,
    required this.process,
    required this.timeout,
    required this.maxMessageBytes,
    required int maxStderrBytes,
    required this.onExit,
  }) : _lines = StreamIterator<String>(
         process.stdout.transform(
           BoundedUtf8LineDecoder(maxLineBytes: maxMessageBytes),
         ),
       ),
       _stderr = _BoundedText(maxStderrBytes) {
    process.stderr.listen(_stderr.add);
    unawaited(
      process.exitCode.then((_) {
        _exited = true;
        onExit();
      }),
    );
  }

  final String id;
  final String ownerSessionId;
  final Process process;
  final Duration timeout;
  final int maxMessageBytes;
  final void Function() onExit;
  final StreamIterator<String> _lines;
  final _BoundedText _stderr;
  Future<void> _serial = Future<void>.value();
  var _nextId = 1;
  var _exited = false;
  GatewaySidecarHandle? handle;

  Future<Object?> call(String method, Map<String, Object?> params) {
    final completer = Completer<Object?>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await _callNow(method, params));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<Object?> _callNow(String method, Map<String, Object?> params) async {
    if (_exited) {
      throw StateError('Gateway sidecar exited: ${_stderr.text}');
    }
    final requestId = 'host-${_nextId++}';
    final encoded = JsonRpcRequest(
      method: method,
      id: requestId,
      params: params,
    ).encode();
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const FormatException('Gateway control request exceeds limit');
    }
    process.stdin.writeln(encoded);
    await process.stdin.flush();
    final hasLine = await _lines.moveNext().timeout(timeout);
    if (!hasLine) {
      throw StateError(
        'Gateway sidecar closed before responding: ${_stderr.text}',
      );
    }
    final line = _lines.current;
    if (utf8.encode(line).length > maxMessageBytes) {
      throw const FormatException('Gateway control response exceeds limit');
    }
    final decoded = const JsonRpcCodec().decode(line);
    if (decoded is! JsonRpcResponse || decoded.id != requestId) {
      throw const FormatException('Gateway returned an unexpected response');
    }
    if (!decoded.isSuccess) {
      throw StateError('${decoded.error!.code}: ${decoded.error!.message}');
    }
    return decoded.result;
  }

  Future<void> stop() async {
    if (_exited) return;
    try {
      await call('gateway.stop', const <String, Object?>{});
      await process.stdin.close();
      await process.exitCode.timeout(timeout);
    } on Object {
      await terminate();
    }
    await _lines.cancel();
  }

  Future<void> terminate() async {
    if (_exited) return;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await _lines.cancel();
  }
}

final class _BoundedText {
  _BoundedText(this.limit);

  final int limit;
  final List<int> _bytes = <int>[];

  String get text => utf8.decode(_bytes, allowMalformed: true);

  void add(List<int> chunk) {
    _bytes.addAll(chunk);
    if (_bytes.length > limit) {
      _bytes.removeRange(0, _bytes.length - limit);
    }
  }
}
