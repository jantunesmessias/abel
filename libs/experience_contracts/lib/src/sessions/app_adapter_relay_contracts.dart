import '../catalog/catalog_contracts.dart';
import '../catalog/scenario_lab_contracts.dart';
import '../composition/kit_composition_contracts.dart';
import '../digest.dart';
import '../lab/scenario_lab_execution_contracts.dart';

final class AppAdapterRelayNonce {
  factory AppAdapterRelayNonce(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(value)) {
      throw FormatException('App Adapter relay nonce is invalid');
    }
    return AppAdapterRelayNonce._(value);
  }

  const AppAdapterRelayNonce._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AppAdapterRelayNonce && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

enum AppAdapterRelayOperation { read, write, reset, capture }

enum AppAdapterRelayResultState { succeeded, failed, cancelled }

enum AppAdapterRelayFailureCause {
  unsupported,
  policyDenied,
  rejected,
  invalidValue,
  timedOut,
  disconnected,
  internalError,
}

final class AppAdapterRelayFailure {
  const AppAdapterRelayFailure({required this.cause, this.diagnosticDigest});

  final AppAdapterRelayFailureCause cause;
  final Digest? diagnosticDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'cause': cause.name,
    if (diagnosticDigest != null) 'diagnosticDigest': diagnosticDigest!.value,
  };

  factory AppAdapterRelayFailure.fromJson(Object? value) {
    final json = _relayObject(value, 'AppAdapterRelayFailure');
    _relayOnly(json, const <String>{
      'cause',
      'diagnosticDigest',
    }, 'AppAdapterRelayFailure');
    return AppAdapterRelayFailure(
      cause: _relayEnum(
        AppAdapterRelayFailureCause.values,
        _relayString(json, 'cause', 'AppAdapterRelayFailure'),
        'AppAdapterRelayFailure.cause',
      ),
      diagnosticDigest: _relayOptionalDigest(
        json,
        'diagnosticDigest',
        'AppAdapterRelayFailure',
      ),
    );
  }
}

/// Short-lived PUT grant for the existing App Adapter capture upload path.
///
/// The URI contains a bearer token and is transport-only. The whole grant is
/// deliberately excluded from [CaptureAppAdapterRelayCommand.commandDigest].
final class AppAdapterRelayCaptureUploadGrant {
  AppAdapterRelayCaptureUploadGrant({
    required this.requestId,
    required this.sessionId,
    required Uri uploadUri,
    required DateTime expiresAt,
    required this.maxBytes,
  }) : uploadUri = uploadUri,
       expiresAt = expiresAt.toUtc() {
    if (!_transportIdentifier.hasMatch(requestId) ||
        !_transportIdentifier.hasMatch(sessionId) ||
        uploadUri.scheme != 'http' ||
        !_loopbackHosts.contains(uploadUri.host) ||
        uploadUri.port < 1 ||
        uploadUri.userInfo.isNotEmpty ||
        uploadUri.fragment.isNotEmpty ||
        uploadUri.path != '/capture-uploads/$requestId' ||
        uploadUri.queryParameters.length != 1 ||
        uploadUri.queryParametersAll['token']?.length != 1 ||
        !_transportIdentifier.hasMatch(
          uploadUri.queryParameters['token'] ?? '',
        ) ||
        !expiresAt.isUtc ||
        maxBytes < 1024 ||
        maxBytes > 32 * 1024 * 1024) {
      throw const FormatException('Invalid App Adapter capture upload grant');
    }
  }

  static final RegExp _transportIdentifier = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
  static const Set<String> _loopbackHosts = <String>{
    '127.0.0.1',
    '::1',
    'localhost',
  };

  static const String method = 'PUT';
  static const String expectedMediaType = 'image/png';

  final String requestId;
  final String sessionId;
  final Uri uploadUri;
  final DateTime expiresAt;
  final int maxBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'requestId': requestId,
    'sessionId': sessionId,
    'expectedMediaType': expectedMediaType,
    'uploadUri': uploadUri.toString(),
    'expiresAt': expiresAt.toIso8601String(),
    'maxBytes': maxBytes,
  };

  factory AppAdapterRelayCaptureUploadGrant.fromJson(Object? value) {
    final json = _relayObject(value, 'AppAdapterRelayCaptureUploadGrant');
    _relayOnly(json, const <String>{
      'method',
      'requestId',
      'sessionId',
      'expectedMediaType',
      'uploadUri',
      'expiresAt',
      'maxBytes',
    }, 'AppAdapterRelayCaptureUploadGrant');
    if (json['method'] != method ||
        json['expectedMediaType'] != expectedMediaType) {
      throw const FormatException('Invalid capture upload method/media type');
    }
    final uploadUri = Uri.tryParse(
      _relayString(
        json,
        'uploadUri',
        'AppAdapterRelayCaptureUploadGrant',
        maxLength: 4096,
      ),
    );
    if (uploadUri == null) {
      throw const FormatException('Invalid capture upload URI');
    }
    return AppAdapterRelayCaptureUploadGrant(
      requestId: _relayString(
        json,
        'requestId',
        'AppAdapterRelayCaptureUploadGrant',
      ),
      sessionId: _relayString(
        json,
        'sessionId',
        'AppAdapterRelayCaptureUploadGrant',
      ),
      uploadUri: uploadUri,
      expiresAt: _relayTime(
        json,
        'expiresAt',
        'AppAdapterRelayCaptureUploadGrant',
      ),
      maxBytes: _relayInteger(
        json,
        'maxBytes',
        'AppAdapterRelayCaptureUploadGrant',
      ),
    );
  }
}

final class AppAdapterRelayHello {
  AppAdapterRelayHello({
    required this.runId,
    required this.adapterInstanceId,
    required this.sequence,
    required this.nonce,
    required Iterable<AppAdapterCapabilityReference> capabilities,
    Iterable<ModuleId> evidenceProviderIds = const <ModuleId>[],
  }) : capabilities = _relaySorted(
         capabilities,
         (item) => item.key,
         'AppAdapterRelayHello.capabilities',
         maxItems: 256,
       ),
       evidenceProviderIds = _relaySorted(
         evidenceProviderIds,
         (item) => item.value,
         'AppAdapterRelayHello.evidenceProviderIds',
         maxItems: 256,
       ) {
    _relayId(adapterInstanceId, 'AppAdapterInstance');
    if (sequence != 0) {
      throw ArgumentError('App Adapter hello sequence must be zero');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final String adapterInstanceId;
  final int sequence;
  final AppAdapterRelayNonce nonce;
  final List<AppAdapterCapabilityReference> capabilities;
  final List<ModuleId> evidenceProviderIds;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AppAdapterRelayHello',
    'runId': runId.value,
    'adapterInstanceId': adapterInstanceId,
    'sequence': sequence,
    'nonce': nonce.value,
    'capabilities': capabilities.map((item) => item.toJson()).toList(),
    'evidenceProviderIds': evidenceProviderIds
        .map((item) => item.value)
        .toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory AppAdapterRelayHello.fromJson(Object? value) {
    final json = _relayDocument(value, 'AppAdapterRelayHello', const <String>{
      'runId',
      'adapterInstanceId',
      'sequence',
      'nonce',
      'capabilities',
      'evidenceProviderIds',
    });
    final hello = AppAdapterRelayHello(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'AppAdapterRelayHello'),
      ),
      adapterInstanceId: _relayString(
        json,
        'adapterInstanceId',
        'AppAdapterRelayHello',
      ),
      sequence: _relayInteger(json, 'sequence', 'AppAdapterRelayHello'),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'AppAdapterRelayHello'),
      ),
      capabilities: _relayList(
        json,
        'capabilities',
        'AppAdapterRelayHello',
        maxItems: 256,
      ).map(AppAdapterCapabilityReference.fromJson),
      evidenceProviderIds: _relayStringList(
        json,
        'evidenceProviderIds',
        'AppAdapterRelayHello',
        maxItems: 256,
      ).map(ModuleId.new),
    );
    _relayVerifyDigest(json, hello.digest, 'AppAdapterRelayHello');
    return hello;
  }
}

sealed class AppAdapterRelayCommand {
  AppAdapterRelayCommand({
    required this.runId,
    required this.commandId,
    required this.sequence,
    required this.nonce,
  }) {
    if (sequence < 1 || sequence > 9007199254740991) {
      throw ArgumentError.value(sequence, 'sequence', 'must be JSON-safe');
    }
  }

  final ScenarioLabRunId runId;
  final ScenarioLabCommandId commandId;
  final int sequence;
  final AppAdapterRelayNonce nonce;

  AppAdapterRelayOperation get operation;

  Digest get commandDigest;

  Map<String, Object?> semanticJson();

  Map<String, Object?> toJson();

  factory AppAdapterRelayCommand.fromJson(Object? value) {
    final json = _relayObject(value, 'AppAdapterRelayCommand');
    final operation = _relayEnum(
      AppAdapterRelayOperation.values,
      _relayString(json, 'operation', 'AppAdapterRelayCommand'),
      'AppAdapterRelayCommand.operation',
    );
    return switch (operation) {
      AppAdapterRelayOperation.read => ReadAppAdapterRelayCommand.fromJson(
        json,
      ),
      AppAdapterRelayOperation.write => WriteAppAdapterRelayCommand.fromJson(
        json,
      ),
      AppAdapterRelayOperation.reset => ResetAppAdapterRelayCommand.fromJson(
        json,
      ),
      AppAdapterRelayOperation.capture =>
        CaptureAppAdapterRelayCommand.fromJson(json),
    };
  }

  Map<String, Object?> envelopeJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'AppAdapterRelayCommand',
    'operation': operation.name,
    'runId': runId.value,
    'commandId': commandId.value,
    'sequence': sequence,
    'nonce': nonce.value,
  };

  void validateHello(AppAdapterRelayHello hello) {
    if (hello.runId != runId ||
        hello.nonce != nonce ||
        sequence <= hello.sequence) {
      throw ArgumentError('Relay command does not bind the adapter hello');
    }
  }
}

abstract base class _ControlAppAdapterRelayCommand
    extends AppAdapterRelayCommand {
  _ControlAppAdapterRelayCommand({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required this.controlId,
    required this.capability,
    required this.operationId,
  });

  final ScenarioControlId controlId;
  final AppAdapterCapabilityReference capability;
  final CapabilityOperationId operationId;

  Map<String, Object?> controlJson() => <String, Object?>{
    ...envelopeJson(),
    'controlId': controlId.value,
    'capability': capability.toJson(),
    'operationId': operationId.value,
  };

  void validateControl({
    required AppAdapterRelayHello hello,
    required ScenarioLabManifest manifest,
    required ScenarioId scenarioId,
    ScenarioControlValue? value,
  }) {
    validateHello(hello);
    if (!hello.capabilities.any((item) => item.key == capability.key)) {
      throw ArgumentError('Relay command capability was not announced');
    }
    final matches = manifest.controls.where((item) => item.id == controlId);
    if (matches.length != 1) {
      throw ArgumentError('Relay command references an unknown control');
    }
    final control = matches.single;
    final expectedOperation = switch (operation) {
      AppAdapterRelayOperation.read => control.readOperationId,
      AppAdapterRelayOperation.write => control.writeOperationId,
      AppAdapterRelayOperation.reset => control.resetOperationId,
      AppAdapterRelayOperation.capture => null,
    };
    if (control.scenarioId != scenarioId ||
        control.capability.key != capability.key ||
        expectedOperation != operationId ||
        (value != null && !control.domain.accepts(value))) {
      throw ArgumentError(
        'Relay command is not allowlisted by the Scenario Lab manifest',
      );
    }
  }
}

final class ReadAppAdapterRelayCommand extends _ControlAppAdapterRelayCommand {
  ReadAppAdapterRelayCommand({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.controlId,
    required super.capability,
    required super.operationId,
  });

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.read;

  @override
  Map<String, Object?> semanticJson() => controlJson();

  @override
  late final Digest commandDigest = Digest.semantic(semanticJson());

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...semanticJson(),
    'commandDigest': commandDigest.value,
  };

  factory ReadAppAdapterRelayCommand.fromJson(Object? value) {
    final json = _relayObject(value, 'ReadAppAdapterRelayCommand');
    _relayCommandOnly(json, const <String>{
      'controlId',
      'capability',
      'operationId',
    }, 'ReadAppAdapterRelayCommand');
    _relayOperation(json, AppAdapterRelayOperation.read);
    final command = ReadAppAdapterRelayCommand(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'ReadAppAdapterRelayCommand'),
      ),
      commandId: ScenarioLabCommandId(
        _relayString(json, 'commandId', 'ReadAppAdapterRelayCommand'),
      ),
      sequence: _relayInteger(json, 'sequence', 'ReadAppAdapterRelayCommand'),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'ReadAppAdapterRelayCommand'),
      ),
      controlId: ScenarioControlId(
        _relayString(json, 'controlId', 'ReadAppAdapterRelayCommand'),
      ),
      capability: AppAdapterCapabilityReference.fromJson(json['capability']),
      operationId: CapabilityOperationId(
        _relayString(json, 'operationId', 'ReadAppAdapterRelayCommand'),
      ),
    );
    _relayCommandDigest(
      json,
      command.commandDigest,
      'ReadAppAdapterRelayCommand',
    );
    return command;
  }
}

final class WriteAppAdapterRelayCommand extends _ControlAppAdapterRelayCommand {
  WriteAppAdapterRelayCommand({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.controlId,
    required super.capability,
    required super.operationId,
    required this.value,
  });

  final ScenarioControlValue value;

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.write;

  @override
  Map<String, Object?> semanticJson() => <String, Object?>{
    ...controlJson(),
    'value': value.toJson(),
  };

  @override
  late final Digest commandDigest = Digest.semantic(semanticJson());

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...semanticJson(),
    'commandDigest': commandDigest.value,
  };

  factory WriteAppAdapterRelayCommand.fromJson(Object? value) {
    final json = _relayObject(value, 'WriteAppAdapterRelayCommand');
    _relayCommandOnly(json, const <String>{
      'controlId',
      'capability',
      'operationId',
      'value',
    }, 'WriteAppAdapterRelayCommand');
    _relayOperation(json, AppAdapterRelayOperation.write);
    final command = WriteAppAdapterRelayCommand(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'WriteAppAdapterRelayCommand'),
      ),
      commandId: ScenarioLabCommandId(
        _relayString(json, 'commandId', 'WriteAppAdapterRelayCommand'),
      ),
      sequence: _relayInteger(json, 'sequence', 'WriteAppAdapterRelayCommand'),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'WriteAppAdapterRelayCommand'),
      ),
      controlId: ScenarioControlId(
        _relayString(json, 'controlId', 'WriteAppAdapterRelayCommand'),
      ),
      capability: AppAdapterCapabilityReference.fromJson(json['capability']),
      operationId: CapabilityOperationId(
        _relayString(json, 'operationId', 'WriteAppAdapterRelayCommand'),
      ),
      value: ScenarioControlValue.fromJson(json['value']),
    );
    _relayCommandDigest(
      json,
      command.commandDigest,
      'WriteAppAdapterRelayCommand',
    );
    return command;
  }
}

final class ResetAppAdapterRelayCommand extends _ControlAppAdapterRelayCommand {
  ResetAppAdapterRelayCommand({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.controlId,
    required super.capability,
    required super.operationId,
  });

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.reset;

  @override
  Map<String, Object?> semanticJson() => controlJson();

  @override
  late final Digest commandDigest = Digest.semantic(semanticJson());

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...semanticJson(),
    'commandDigest': commandDigest.value,
  };

  factory ResetAppAdapterRelayCommand.fromJson(Object? value) {
    final json = _relayObject(value, 'ResetAppAdapterRelayCommand');
    _relayCommandOnly(json, const <String>{
      'controlId',
      'capability',
      'operationId',
    }, 'ResetAppAdapterRelayCommand');
    _relayOperation(json, AppAdapterRelayOperation.reset);
    final command = ResetAppAdapterRelayCommand(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'ResetAppAdapterRelayCommand'),
      ),
      commandId: ScenarioLabCommandId(
        _relayString(json, 'commandId', 'ResetAppAdapterRelayCommand'),
      ),
      sequence: _relayInteger(json, 'sequence', 'ResetAppAdapterRelayCommand'),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'ResetAppAdapterRelayCommand'),
      ),
      controlId: ScenarioControlId(
        _relayString(json, 'controlId', 'ResetAppAdapterRelayCommand'),
      ),
      capability: AppAdapterCapabilityReference.fromJson(json['capability']),
      operationId: CapabilityOperationId(
        _relayString(json, 'operationId', 'ResetAppAdapterRelayCommand'),
      ),
    );
    _relayCommandDigest(
      json,
      command.commandDigest,
      'ResetAppAdapterRelayCommand',
    );
    return command;
  }
}

final class CaptureAppAdapterRelayCommand extends AppAdapterRelayCommand {
  CaptureAppAdapterRelayCommand({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required this.requiredEvidenceId,
    required this.providerId,
    required this.uploadGrant,
  });

  final RequiredEvidenceId requiredEvidenceId;
  final ModuleId providerId;

  /// Ephemeral credential-bearing PUT grant. Excluded from [commandDigest].
  final AppAdapterRelayCaptureUploadGrant uploadGrant;

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.capture;

  @override
  Map<String, Object?> semanticJson() => <String, Object?>{
    ...envelopeJson(),
    'requiredEvidenceId': requiredEvidenceId.value,
    'providerId': providerId.value,
  };

  @override
  late final Digest commandDigest = Digest.semantic(semanticJson());

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...semanticJson(),
    'uploadGrant': uploadGrant.toJson(),
    'commandDigest': commandDigest.value,
  };

  factory CaptureAppAdapterRelayCommand.fromJson(Object? value) {
    final json = _relayObject(value, 'CaptureAppAdapterRelayCommand');
    _relayCommandOnly(json, const <String>{
      'requiredEvidenceId',
      'providerId',
      'uploadGrant',
    }, 'CaptureAppAdapterRelayCommand');
    _relayOperation(json, AppAdapterRelayOperation.capture);
    final command = CaptureAppAdapterRelayCommand(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'CaptureAppAdapterRelayCommand'),
      ),
      commandId: ScenarioLabCommandId(
        _relayString(json, 'commandId', 'CaptureAppAdapterRelayCommand'),
      ),
      sequence: _relayInteger(
        json,
        'sequence',
        'CaptureAppAdapterRelayCommand',
      ),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'CaptureAppAdapterRelayCommand'),
      ),
      requiredEvidenceId: RequiredEvidenceId(
        _relayString(
          json,
          'requiredEvidenceId',
          'CaptureAppAdapterRelayCommand',
        ),
      ),
      providerId: ModuleId(
        _relayString(json, 'providerId', 'CaptureAppAdapterRelayCommand'),
      ),
      uploadGrant: AppAdapterRelayCaptureUploadGrant.fromJson(
        json['uploadGrant'],
      ),
    );
    _relayCommandDigest(
      json,
      command.commandDigest,
      'CaptureAppAdapterRelayCommand',
    );
    return command;
  }

  void validateManifest({
    required AppAdapterRelayHello hello,
    required ScenarioLabManifest manifest,
    required ScenarioId scenarioId,
  }) {
    validateHello(hello);
    if (!hello.evidenceProviderIds.contains(providerId)) {
      throw ArgumentError('Capture provider was not announced');
    }
    final matches = manifest.requiredEvidence.where(
      (item) => item.id == requiredEvidenceId,
    );
    if (matches.length != 1 ||
        matches.single.scenarioId != scenarioId ||
        matches.single.providerId != providerId) {
      throw ArgumentError(
        'Capture command is not allowlisted by the Scenario Lab manifest',
      );
    }
  }
}

sealed class AppAdapterRelayResult {
  AppAdapterRelayResult({
    required this.runId,
    required this.commandId,
    required this.sequence,
    required this.nonce,
    required this.state,
    this.failure,
  }) {
    if (sequence < 1 || sequence > 9007199254740991) {
      throw ArgumentError.value(sequence, 'sequence', 'must be JSON-safe');
    }
    if ((state == AppAdapterRelayResultState.failed) != (failure != null)) {
      throw ArgumentError('Relay failure is present exactly for failed state');
    }
  }

  final ScenarioLabRunId runId;
  final ScenarioLabCommandId commandId;
  final int sequence;
  final AppAdapterRelayNonce nonce;
  final AppAdapterRelayResultState state;
  final AppAdapterRelayFailure? failure;

  AppAdapterRelayOperation get operation;

  Digest get resultDigest;

  Map<String, Object?> toJson({bool includeDigest = true});

  factory AppAdapterRelayResult.fromJson(Object? value) {
    final json = _relayObject(value, 'AppAdapterRelayResult');
    final operation = _relayEnum(
      AppAdapterRelayOperation.values,
      _relayString(json, 'operation', 'AppAdapterRelayResult'),
      'AppAdapterRelayResult.operation',
    );
    return switch (operation) {
      AppAdapterRelayOperation.read => ReadAppAdapterRelayResult.fromJson(json),
      AppAdapterRelayOperation.write => WriteAppAdapterRelayResult.fromJson(
        json,
      ),
      AppAdapterRelayOperation.reset => ResetAppAdapterRelayResult.fromJson(
        json,
      ),
      AppAdapterRelayOperation.capture => CaptureAppAdapterRelayResult.fromJson(
        json,
      ),
    };
  }

  Map<String, Object?> envelopeJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'AppAdapterRelayResult',
    'operation': operation.name,
    'runId': runId.value,
    'commandId': commandId.value,
    'sequence': sequence,
    'nonce': nonce.value,
    'state': state.name,
    if (failure != null) 'failure': failure!.toJson(),
  };

  void validateAgainst(AppAdapterRelayCommand command) {
    if (runId != command.runId ||
        commandId != command.commandId ||
        sequence != command.sequence ||
        nonce != command.nonce ||
        operation != command.operation) {
      throw ArgumentError('Relay result does not bind its command envelope');
    }
    final compatible = switch ((this, command)) {
      (ReadAppAdapterRelayResult _, ReadAppAdapterRelayCommand _) ||
      (WriteAppAdapterRelayResult _, WriteAppAdapterRelayCommand _) ||
      (ResetAppAdapterRelayResult _, ResetAppAdapterRelayCommand _) ||
      (CaptureAppAdapterRelayResult _, CaptureAppAdapterRelayCommand _) => true,
      _ => false,
    };
    if (!compatible) {
      throw ArgumentError('Relay result payload does not match command');
    }
    final result = this;
    if (result is CaptureAppAdapterRelayResult &&
        command is CaptureAppAdapterRelayCommand &&
        result.state == AppAdapterRelayResultState.succeeded &&
        result.uploadRequestId != command.uploadGrant.requestId) {
      throw ArgumentError(
        'Capture relay result does not bind its upload grant',
      );
    }
  }
}

abstract base class _ValueAppAdapterRelayResult extends AppAdapterRelayResult {
  _ValueAppAdapterRelayResult({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.state,
    super.failure,
    this.value,
  }) {
    if ((state == AppAdapterRelayResultState.succeeded) != (value != null)) {
      throw ArgumentError('Relay control value is present exactly on success');
    }
  }

  final ScenarioControlValue? value;

  Map<String, Object?> valueJson() => <String, Object?>{
    ...envelopeJson(),
    if (value != null) 'value': value!.toJson(),
  };
}

final class ReadAppAdapterRelayResult extends _ValueAppAdapterRelayResult {
  ReadAppAdapterRelayResult({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.state,
    super.failure,
    super.value,
  });

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.read;

  @override
  late final Digest resultDigest = Digest.semantic(
    toJson(includeDigest: false),
  );

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...valueJson(),
    if (includeDigest) 'resultDigest': resultDigest.value,
  };

  factory ReadAppAdapterRelayResult.fromJson(Object? value) =>
      _relayValueResult(
            value,
            AppAdapterRelayOperation.read,
            (fields) => ReadAppAdapterRelayResult(
              runId: fields.runId,
              commandId: fields.commandId,
              sequence: fields.sequence,
              nonce: fields.nonce,
              state: fields.state,
              failure: fields.failure,
              value: fields.value,
            ),
          )
          as ReadAppAdapterRelayResult;
}

final class WriteAppAdapterRelayResult extends _ValueAppAdapterRelayResult {
  WriteAppAdapterRelayResult({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.state,
    super.failure,
    super.value,
  });

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.write;

  @override
  late final Digest resultDigest = Digest.semantic(
    toJson(includeDigest: false),
  );

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...valueJson(),
    if (includeDigest) 'resultDigest': resultDigest.value,
  };

  factory WriteAppAdapterRelayResult.fromJson(Object? value) =>
      _relayValueResult(
            value,
            AppAdapterRelayOperation.write,
            (fields) => WriteAppAdapterRelayResult(
              runId: fields.runId,
              commandId: fields.commandId,
              sequence: fields.sequence,
              nonce: fields.nonce,
              state: fields.state,
              failure: fields.failure,
              value: fields.value,
            ),
          )
          as WriteAppAdapterRelayResult;
}

final class ResetAppAdapterRelayResult extends _ValueAppAdapterRelayResult {
  ResetAppAdapterRelayResult({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.state,
    super.failure,
    super.value,
  });

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.reset;

  @override
  late final Digest resultDigest = Digest.semantic(
    toJson(includeDigest: false),
  );

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...valueJson(),
    if (includeDigest) 'resultDigest': resultDigest.value,
  };

  factory ResetAppAdapterRelayResult.fromJson(Object? value) =>
      _relayValueResult(
            value,
            AppAdapterRelayOperation.reset,
            (fields) => ResetAppAdapterRelayResult(
              runId: fields.runId,
              commandId: fields.commandId,
              sequence: fields.sequence,
              nonce: fields.nonce,
              state: fields.state,
              failure: fields.failure,
              value: fields.value,
            ),
          )
          as ResetAppAdapterRelayResult;
}

final class CaptureAppAdapterRelayResult extends AppAdapterRelayResult {
  CaptureAppAdapterRelayResult({
    required super.runId,
    required super.commandId,
    required super.sequence,
    required super.nonce,
    required super.state,
    super.failure,
    this.uploadRequestId,
  }) {
    final succeeded = state == AppAdapterRelayResultState.succeeded;
    if (succeeded != (uploadRequestId != null) ||
        (uploadRequestId != null &&
            !_uploadRequestIdentifier.hasMatch(uploadRequestId!))) {
      throw ArgumentError('Capture relay result payload is invalid');
    }
  }

  static final RegExp _uploadRequestIdentifier = RegExp(
    r'^[A-Za-z0-9_-]{8,128}$',
  );

  /// Identifies the PUT acknowledged by the target.
  ///
  /// Evidence, provenance, classification and fidelity remain Host-owned and
  /// are deliberately absent from the relay result.
  final String? uploadRequestId;

  @override
  AppAdapterRelayOperation get operation => AppAdapterRelayOperation.capture;

  @override
  late final Digest resultDigest = Digest.semantic(
    toJson(includeDigest: false),
  );

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...envelopeJson(),
    if (uploadRequestId != null) 'uploadRequestId': uploadRequestId,
    if (includeDigest) 'resultDigest': resultDigest.value,
  };

  factory CaptureAppAdapterRelayResult.fromJson(Object? value) {
    final json = _relayObject(value, 'CaptureAppAdapterRelayResult');
    _relayResultOnly(json, const <String>{
      'uploadRequestId',
    }, 'CaptureAppAdapterRelayResult');
    _relayOperation(json, AppAdapterRelayOperation.capture, result: true);
    final result = CaptureAppAdapterRelayResult(
      runId: ScenarioLabRunId(
        _relayString(json, 'runId', 'CaptureAppAdapterRelayResult'),
      ),
      commandId: ScenarioLabCommandId(
        _relayString(json, 'commandId', 'CaptureAppAdapterRelayResult'),
      ),
      sequence: _relayInteger(json, 'sequence', 'CaptureAppAdapterRelayResult'),
      nonce: AppAdapterRelayNonce(
        _relayString(json, 'nonce', 'CaptureAppAdapterRelayResult'),
      ),
      state: _relayEnum(
        AppAdapterRelayResultState.values,
        _relayString(json, 'state', 'CaptureAppAdapterRelayResult'),
        'CaptureAppAdapterRelayResult.state',
      ),
      failure: json.containsKey('failure')
          ? AppAdapterRelayFailure.fromJson(json['failure'])
          : null,
      uploadRequestId: json.containsKey('uploadRequestId')
          ? _relayString(
              json,
              'uploadRequestId',
              'CaptureAppAdapterRelayResult',
              maxLength: 128,
            )
          : null,
    );
    _relayResultDigest(
      json,
      result.resultDigest,
      'CaptureAppAdapterRelayResult',
    );
    return result;
  }
}

final class _ValueResultFields {
  const _ValueResultFields({
    required this.runId,
    required this.commandId,
    required this.sequence,
    required this.nonce,
    required this.state,
    required this.failure,
    required this.value,
  });

  final ScenarioLabRunId runId;
  final ScenarioLabCommandId commandId;
  final int sequence;
  final AppAdapterRelayNonce nonce;
  final AppAdapterRelayResultState state;
  final AppAdapterRelayFailure? failure;
  final ScenarioControlValue? value;
}

AppAdapterRelayResult _relayValueResult(
  Object? source,
  AppAdapterRelayOperation operation,
  AppAdapterRelayResult Function(_ValueResultFields) build,
) {
  final path = '${operation.name}AppAdapterRelayResult';
  final json = _relayObject(source, path);
  _relayResultOnly(json, const <String>{'value'}, path);
  _relayOperation(json, operation, result: true);
  final result = build(
    _ValueResultFields(
      runId: ScenarioLabRunId(_relayString(json, 'runId', path)),
      commandId: ScenarioLabCommandId(_relayString(json, 'commandId', path)),
      sequence: _relayInteger(json, 'sequence', path),
      nonce: AppAdapterRelayNonce(_relayString(json, 'nonce', path)),
      state: _relayEnum(
        AppAdapterRelayResultState.values,
        _relayString(json, 'state', path),
        '$path.state',
      ),
      failure: json.containsKey('failure')
          ? AppAdapterRelayFailure.fromJson(json['failure'])
          : null,
      value: json.containsKey('value')
          ? ScenarioControlValue.fromJson(json['value'])
          : null,
    ),
  );
  _relayResultDigest(json, result.resultDigest, path);
  return result;
}

Map<String, Object?> _relayDocument(
  Object? value,
  String kind,
  Set<String> fields,
) {
  final json = _relayObject(value, kind);
  _relayOnly(json, <String>{
    'schemaVersion',
    'kind',
    ...fields,
    'digest',
  }, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has invalid schemaVersion or kind');
  }
  return json;
}

void _relayCommandOnly(
  Map<String, Object?> json,
  Set<String> fields,
  String path,
) => _relayOnly(json, <String>{
  'schemaVersion',
  'kind',
  'operation',
  'runId',
  'commandId',
  'sequence',
  'nonce',
  ...fields,
  'commandDigest',
}, path);

void _relayResultOnly(
  Map<String, Object?> json,
  Set<String> fields,
  String path,
) => _relayOnly(json, <String>{
  'schemaVersion',
  'kind',
  'operation',
  'runId',
  'commandId',
  'sequence',
  'nonce',
  'state',
  'failure',
  ...fields,
  'resultDigest',
}, path);

void _relayOperation(
  Map<String, Object?> json,
  AppAdapterRelayOperation operation, {
  bool result = false,
}) {
  final expectedKind = result
      ? 'AppAdapterRelayResult'
      : 'AppAdapterRelayCommand';
  if (json['schemaVersion'] != 1 ||
      json['kind'] != expectedKind ||
      json['operation'] != operation.name) {
    throw const FormatException('Invalid App Adapter relay discriminator');
  }
}

void _relayCommandDigest(
  Map<String, Object?> json,
  Digest digest,
  String path,
) {
  if (Digest(_relayString(json, 'commandDigest', path)) != digest) {
    throw FormatException('$path.commandDigest mismatch');
  }
}

void _relayResultDigest(Map<String, Object?> json, Digest digest, String path) {
  if (Digest(_relayString(json, 'resultDigest', path)) != digest) {
    throw FormatException('$path.resultDigest mismatch');
  }
}

Map<String, Object?> _relayObject(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$path must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

void _relayOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _relayString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 256,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

int _relayInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

DateTime _relayTime(Map<String, Object?> json, String key, String path) {
  final source = _relayString(json, key, path, maxLength: 64);
  final parsed = DateTime.tryParse(source);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != source) {
    throw FormatException('$path.$key must be a canonical UTC date-time');
  }
  return parsed;
}

List<Object?> _relayList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?> || value.length > maxItems) {
    throw FormatException('$path.$key must be a bounded list');
  }
  return value;
}

List<String> _relayStringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final values = _relayList(json, key, path, maxItems: maxItems);
  if (values.any((value) => value is! String)) {
    throw FormatException('$path.$key must contain strings');
  }
  return values.cast<String>();
}

Digest? _relayOptionalDigest(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return Digest(_relayString(json, key, path));
}

T _relayEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has unknown value $name');
}

List<T> _relaySorted<T>(
  Iterable<T> values,
  String Function(T) keyOf,
  String path, {
  required int maxItems,
}) {
  final result = List<T>.of(values)
    ..sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  if (result.length > maxItems ||
      result.map(keyOf).toSet().length != result.length) {
    throw ArgumentError('$path must be unique and bounded');
  }
  return List<T>.unmodifiable(result);
}

void _relayVerifyDigest(Map<String, Object?> json, Digest digest, String path) {
  if (Digest(_relayString(json, 'digest', path)) != digest) {
    throw FormatException('$path.digest mismatch');
  }
}

void _relayId(String value, String path) {
  if (value.length > 256) throw FormatException('$path ID is too long');
  OpaqueId.validate(value, path);
}
