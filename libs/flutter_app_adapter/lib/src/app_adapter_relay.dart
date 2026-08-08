import 'dart:async';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';

import 'app_adapter.dart';
import 'app_adapter_capture_uploader.dart';

/// Immutable inputs used to bind one App Adapter process instance to a Lab run.
final class AppAdapterRelayConfiguration {
  AppAdapterRelayConfiguration({
    required this.runId,
    required this.adapterInstanceId,
    required this.nonce,
    Iterable<ModuleId> evidenceProviderIds = const <ModuleId>[],
    this.maxCommands = 256,
    this.maxCaptureUploadAttemptsPerCommand = 16,
    this.maxCachedCaptureBytes = 64 * 1024 * 1024,
  }) : evidenceProviderIds = List<ModuleId>.unmodifiable(evidenceProviderIds) {
    if (maxCommands < 1 || maxCommands > 4096) {
      throw ArgumentError.value(maxCommands, 'maxCommands');
    }
    if (maxCaptureUploadAttemptsPerCommand < 1 ||
        maxCaptureUploadAttemptsPerCommand > 64) {
      throw ArgumentError.value(
        maxCaptureUploadAttemptsPerCommand,
        'maxCaptureUploadAttemptsPerCommand',
      );
    }
    if (maxCachedCaptureBytes < 1024 ||
        maxCachedCaptureBytes > 512 * 1024 * 1024) {
      throw ArgumentError.value(maxCachedCaptureBytes, 'maxCachedCaptureBytes');
    }
  }

  final ScenarioLabRunId runId;
  final String adapterInstanceId;
  final AppAdapterRelayNonce nonce;
  final List<ModuleId> evidenceProviderIds;
  final int maxCommands;
  final int maxCaptureUploadAttemptsPerCommand;
  final int maxCachedCaptureBytes;
}

/// Executes the sealed App Adapter relay protocol for one adapter instance.
///
/// The relay owns sequence validation and a bounded, non-evicting dedupe cache.
/// A command ID can never be reused with another semantic digest. Capture bytes
/// are observed once per command and may be uploaded again only through a new
/// short-lived grant.
final class AppAdapterRelay {
  AppAdapterRelay({
    required AppAdapter adapter,
    required this.sessionId,
    required AppAdapterRelayConfiguration configuration,
    AppAdapterCaptureUploader? captureUploader,
  }) : _adapter = adapter,
       _captureUploader = captureUploader ?? AppAdapterCaptureUploader(),
       maxCommands = configuration.maxCommands,
       maxCaptureUploadAttemptsPerCommand =
           configuration.maxCaptureUploadAttemptsPerCommand,
       maxCachedCaptureBytes = configuration.maxCachedCaptureBytes,
       hello = AppAdapterRelayHello(
         runId: configuration.runId,
         adapterInstanceId: configuration.adapterInstanceId,
         sequence: 0,
         nonce: configuration.nonce,
         capabilities: adapter.scenarioControlCapabilities.map(
           (capability) => AppAdapterCapabilityReference(
             id: AppAdapterCapabilityId(capability.descriptor.id),
             version: capability.descriptor.version,
           ),
         ),
         evidenceProviderIds: configuration.evidenceProviderIds,
       ),
       _capabilities = <String, ScenarioControlCapability>{
         for (final capability in adapter.scenarioControlCapabilities)
           '${capability.descriptor.id}@${capability.descriptor.version}':
               capability,
       } {
    if (!_transportIdentifier.hasMatch(sessionId)) {
      throw FormatException('App Adapter relay session ID is invalid');
    }
  }

  static final RegExp _transportIdentifier = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  final AppAdapter _adapter;
  final AppAdapterCaptureUploader _captureUploader;
  final Map<String, ScenarioControlCapability> _capabilities;
  final Map<String, _RelayEntry> _entries = <String, _RelayEntry>{};
  final int maxCommands;
  final int maxCaptureUploadAttemptsPerCommand;
  final int maxCachedCaptureBytes;
  final String sessionId;
  final AppAdapterRelayHello hello;

  Future<void> _tail = Future<void>.value();
  var _lastSequence = 0;
  var _cachedCaptureBytes = 0;
  var _disposed = false;

  AppAdapter get adapter => _adapter;

  int get cachedCommandCount => _entries.length;

  /// Strictly decodes a public command before considering any side effect.
  Future<AppAdapterRelayResult> handle(Object? wire) async =>
      execute(AppAdapterRelayCommand.fromJson(wire));

  Future<AppAdapterRelayResult> execute(AppAdapterRelayCommand command) {
    _ensureOpen();
    final key = '${command.runId.value}\u0000${command.commandId.value}';
    final existing = _entries[key];
    if (existing != null) {
      if (existing.commandDigest != command.commandDigest) {
        return Future<AppAdapterRelayResult>.value(
          _failure(command, AppAdapterRelayFailureCause.rejected),
        );
      }
      if (existing case final _ControlRelayEntry entry) {
        return entry.result;
      }
      return _captureUpload(existing as _CaptureRelayEntry, command);
    }

    try {
      command.validateHello(hello);
    } on ArgumentError {
      return Future<AppAdapterRelayResult>.value(
        _failure(command, AppAdapterRelayFailureCause.rejected),
      );
    }
    if (command.sequence != _lastSequence + 1 ||
        _entries.length >= maxCommands) {
      return Future<AppAdapterRelayResult>.value(
        _failure(
          command,
          _entries.length >= maxCommands
              ? AppAdapterRelayFailureCause.policyDenied
              : AppAdapterRelayFailureCause.rejected,
        ),
      );
    }

    _lastSequence = command.sequence;
    if (command is CaptureAppAdapterRelayCommand) {
      final entry = _CaptureRelayEntry(command.commandDigest);
      _entries[key] = entry;
      return _captureUpload(entry, command);
    }

    final future = _enqueue(() => _executeControl(command));
    _entries[key] = _ControlRelayEntry(command.commandDigest, future);
    return future;
  }

  Future<AppAdapterRelayResult> _executeControl(
    AppAdapterRelayCommand command,
  ) async {
    try {
      _ensureOpen();
      final (capability, operationId) = switch (command) {
        ReadAppAdapterRelayCommand(:final capability, :final operationId) ||
        WriteAppAdapterRelayCommand(:final capability, :final operationId) ||
        ResetAppAdapterRelayCommand(
          :final capability,
          :final operationId,
        ) => (capability, operationId),
        CaptureAppAdapterRelayCommand() => throw StateError(
          'Capture command reached the control executor',
        ),
        _ => throw StateError('Unknown control relay command'),
      };
      final local = _capabilities[capability.key];
      final expectedOperation = switch (command) {
        ReadAppAdapterRelayCommand() => local?.readOperation,
        WriteAppAdapterRelayCommand() => local?.writeOperation,
        ResetAppAdapterRelayCommand() => local?.resetOperation,
        _ => null,
      };
      if (local == null || expectedOperation != operationId.value) {
        return _failure(command, AppAdapterRelayFailureCause.unsupported);
      }
      final value = switch (command) {
        ReadAppAdapterRelayCommand() => await local.readControl(),
        WriteAppAdapterRelayCommand(:final value) => await local.writeControl(
          value,
        ),
        ResetAppAdapterRelayCommand() => await local.resetControl(),
        _ => throw StateError('Unknown control relay command'),
      };
      if (command is WriteAppAdapterRelayCommand &&
          value.kind != command.value.kind) {
        return _failure(command, AppAdapterRelayFailureCause.invalidValue);
      }
      return _success(command, value);
    } on FormatException {
      return _failure(command, AppAdapterRelayFailureCause.invalidValue);
    } on TimeoutException {
      return _failure(command, AppAdapterRelayFailureCause.timedOut);
    } on Object {
      return _failure(command, AppAdapterRelayFailureCause.internalError);
    }
  }

  Future<AppAdapterRelayResult> _captureUpload(
    _CaptureRelayEntry entry,
    AppAdapterRelayCommand source,
  ) {
    if (source is! CaptureAppAdapterRelayCommand) {
      return Future<AppAdapterRelayResult>.value(
        _failure(source, AppAdapterRelayFailureCause.rejected),
      );
    }
    final grantKey = _CaptureGrantKey(source.uploadGrant);
    final cached = entry.uploads[grantKey];
    if (cached != null) return cached;
    if (entry.uploads.length >= maxCaptureUploadAttemptsPerCommand) {
      return Future<AppAdapterRelayResult>.value(
        _failure(source, AppAdapterRelayFailureCause.policyDenied),
      );
    }

    late final Future<AppAdapterRelayResult> result;
    if (!hello.evidenceProviderIds.contains(source.providerId)) {
      result = Future<AppAdapterRelayResult>.value(
        _failure(source, AppAdapterRelayFailureCause.unsupported),
      );
    } else if (source.uploadGrant.sessionId != sessionId) {
      result = Future<AppAdapterRelayResult>.value(
        _failure(source, AppAdapterRelayFailureCause.rejected),
      );
    } else if (_captureUploader.isExpired(source.uploadGrant.expiresAt)) {
      result = Future<AppAdapterRelayResult>.value(
        _failure(source, AppAdapterRelayFailureCause.timedOut),
      );
    } else {
      result = _enqueue(() => _performCaptureUpload(entry, source));
    }
    entry.uploads[grantKey] = result;
    return result;
  }

  Future<AppAdapterRelayResult> _performCaptureUpload(
    _CaptureRelayEntry entry,
    CaptureAppAdapterRelayCommand command,
  ) async {
    try {
      _ensureOpen();
      final bytes = await entry.captureOnce(() async {
        final captured = await _adapter.capture();
        if (captured.length > 32 * 1024 * 1024) {
          throw const FormatException('Capture exceeds the relay byte limit');
        }
        if (_cachedCaptureBytes + captured.length > maxCachedCaptureBytes) {
          throw const _RelayPolicyDenied();
        }
        final immutable = Uint8List.fromList(captured);
        _cachedCaptureBytes += immutable.length;
        return immutable;
      });
      final upload = await _captureUploader.uploadRelay(
        grant: command.uploadGrant,
        pngBytes: bytes,
      );
      if (!upload.ok) {
        return _failure(command, _uploadFailure(upload.code));
      }
      return _validated(
        CaptureAppAdapterRelayResult(
          runId: command.runId,
          commandId: command.commandId,
          sequence: command.sequence,
          nonce: command.nonce,
          state: AppAdapterRelayResultState.succeeded,
          uploadRequestId: command.uploadGrant.requestId,
        ),
        command,
      );
    } on TimeoutException {
      return _failure(command, AppAdapterRelayFailureCause.timedOut);
    } on _RelayPolicyDenied {
      return _failure(command, AppAdapterRelayFailureCause.policyDenied);
    } on FormatException {
      return _failure(command, AppAdapterRelayFailureCause.invalidValue);
    } on Object {
      return _failure(command, AppAdapterRelayFailureCause.internalError);
    }
  }

  Future<AppAdapterRelayResult> _enqueue(
    Future<AppAdapterRelayResult> Function() action,
  ) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {});
    return result;
  }

  AppAdapterRelayResult _success(
    AppAdapterRelayCommand command,
    ScenarioControlValue value,
  ) {
    final result = switch (command) {
      ReadAppAdapterRelayCommand() => ReadAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.succeeded,
        value: value,
      ),
      WriteAppAdapterRelayCommand() => WriteAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.succeeded,
        value: value,
      ),
      ResetAppAdapterRelayCommand() => ResetAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.succeeded,
        value: value,
      ),
      CaptureAppAdapterRelayCommand() => throw StateError(
        'Capture success requires a PUT acknowledgement',
      ),
      _ => throw StateError('Unknown App Adapter relay command'),
    };
    return _validated(result, command);
  }

  AppAdapterRelayResult _failure(
    AppAdapterRelayCommand command,
    AppAdapterRelayFailureCause cause,
  ) {
    final failure = AppAdapterRelayFailure(cause: cause);
    final result = switch (command) {
      ReadAppAdapterRelayCommand() => ReadAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.failed,
        failure: failure,
      ),
      WriteAppAdapterRelayCommand() => WriteAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.failed,
        failure: failure,
      ),
      ResetAppAdapterRelayCommand() => ResetAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.failed,
        failure: failure,
      ),
      CaptureAppAdapterRelayCommand() => CaptureAppAdapterRelayResult(
        runId: command.runId,
        commandId: command.commandId,
        sequence: command.sequence,
        nonce: command.nonce,
        state: AppAdapterRelayResultState.failed,
        failure: failure,
      ),
      _ => throw StateError('Unknown App Adapter relay command'),
    };
    return _validated(result, command);
  }

  AppAdapterRelayResult _validated(
    AppAdapterRelayResult result,
    AppAdapterRelayCommand command,
  ) {
    result.validateAgainst(command);
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entries.clear();
    _cachedCaptureBytes = 0;
    _captureUploader.close();
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('App Adapter relay is disposed');
  }
}

AppAdapterRelayFailureCause _uploadFailure(String code) => switch (code) {
  'capture_handle_expired' => AppAdapterRelayFailureCause.timedOut,
  'capture_too_large' => AppAdapterRelayFailureCause.invalidValue,
  'capture_upload_rejected' => AppAdapterRelayFailureCause.rejected,
  _ => AppAdapterRelayFailureCause.internalError,
};

sealed class _RelayEntry {
  const _RelayEntry(this.commandDigest);

  final Digest commandDigest;
}

final class _ControlRelayEntry extends _RelayEntry {
  const _ControlRelayEntry(super.commandDigest, this.result);

  final Future<AppAdapterRelayResult> result;
}

final class _CaptureRelayEntry extends _RelayEntry {
  _CaptureRelayEntry(super.commandDigest);

  final Map<_CaptureGrantKey, Future<AppAdapterRelayResult>> uploads =
      <_CaptureGrantKey, Future<AppAdapterRelayResult>>{};
  Future<Uint8List>? _bytes;

  Future<Uint8List> captureOnce(Future<Uint8List> Function() capture) =>
      _bytes ??= capture();
}

final class _CaptureGrantKey {
  _CaptureGrantKey(AppAdapterRelayCaptureUploadGrant grant)
    : requestId = grant.requestId,
      sessionId = grant.sessionId,
      uploadUri = grant.uploadUri.toString(),
      expiresAt = grant.expiresAt,
      maxBytes = grant.maxBytes;

  final String requestId;
  final String sessionId;
  final String uploadUri;
  final DateTime expiresAt;
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is _CaptureGrantKey &&
      other.requestId == requestId &&
      other.sessionId == sessionId &&
      other.uploadUri == uploadUri &&
      other.expiresAt == expiresAt &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode =>
      Object.hash(requestId, sessionId, uploadUri, expiresAt, maxBytes);
}

final class _RelayPolicyDenied implements Exception {
  const _RelayPolicyDenied();
}
