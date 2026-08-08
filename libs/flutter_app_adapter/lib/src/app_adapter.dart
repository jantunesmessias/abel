import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';

abstract interface class AppCapability {
  CapabilityDescriptor get descriptor;

  FutureOr<Object?> invoke(String operation, Map<String, Object?> arguments);

  FutureOr<void> reset();
}

/// Capability whose read/write/reset meanings are explicit for the Lab relay.
///
/// Generic [AppCapability] operations remain available to existing callers,
/// but are never inferred as Scenario control operations by the relay.
abstract interface class ScenarioControlCapability implements AppCapability {
  String get readOperation;

  String get writeOperation;

  String? get resetOperation;

  FutureOr<ScenarioControlValue> readControl();

  FutureOr<ScenarioControlValue> writeControl(ScenarioControlValue value);

  FutureOr<ScenarioControlValue> resetControl();
}

typedef CaptureHandler = FutureOr<List<int>> Function(String format);

final class AppAdapter {
  AppAdapter({
    required Iterable<AppCapability> capabilities,
    required this.captureHandler,
  }) : _capabilities = <String, AppCapability>{
         for (final capability in capabilities)
           capability.descriptor.id: capability,
       } {
    if (_capabilities.length != capabilities.length) {
      throw ArgumentError('Capability IDs must be unique');
    }
  }

  final Map<String, AppCapability> _capabilities;
  final CaptureHandler captureHandler;

  List<CapabilityDescriptor> get descriptors =>
      List<CapabilityDescriptor>.unmodifiable(
        _capabilities.values.map((capability) => capability.descriptor),
      );

  List<ScenarioControlCapability> get scenarioControlCapabilities =>
      List<ScenarioControlCapability>.unmodifiable(
        _capabilities.values.whereType<ScenarioControlCapability>(),
      );

  Future<Object?> invoke({
    required String capabilityId,
    required String operation,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final capability = _capabilities[capabilityId];
    if (capability == null) {
      throw StateError('Capability $capabilityId is not available');
    }
    if (!capability.descriptor.operations.contains(operation)) {
      throw StateError('Operation $operation is not declared by $capabilityId');
    }
    return capability.invoke(
      operation,
      Map<String, Object?>.unmodifiable(arguments),
    );
  }

  Future<void> reset() async {
    for (final capability in _capabilities.values) {
      await capability.reset();
    }
  }

  Future<List<int>> capture({String format = 'png'}) async {
    if (format != 'png') {
      throw FormatException(
        'Only lossless PNG is supported by the capture protocol',
      );
    }
    final bytes = await captureHandler(format);
    return List<int>.unmodifiable(bytes);
  }
}

final class SimulatedStringCapability implements AppCapability {
  SimulatedStringCapability({
    required this.id,
    required this.initialValue,
    required Set<String> allowedValues,
  }) : allowedValues = Set<String>.unmodifiable(allowedValues),
       _value = initialValue {
    if (!this.allowedValues.contains(initialValue)) {
      throw ArgumentError('initialValue must be allowed');
    }
  }

  final String id;
  final String initialValue;
  final Set<String> allowedValues;
  String _value;

  String get value => _value;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
    id: id,
    version: 1,
    operations: const <String>{'get', 'set'},
  );

  @override
  Object? invoke(String operation, Map<String, Object?> arguments) {
    switch (operation) {
      case 'get':
        return <String, Object?>{'value': _value};
      case 'set':
        final value = arguments['value'];
        if (value is! String || !allowedValues.contains(value)) {
          throw FormatException('value is not allowed for $id');
        }
        _value = value;
        return <String, Object?>{'value': _value};
      default:
        throw StateError('Unsupported operation $operation');
    }
  }

  @override
  void reset() => _value = initialValue;
}
