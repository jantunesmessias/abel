import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';

import 'app_adapter.dart';

typedef BooleanControlReader = FutureOr<bool> Function();
typedef BooleanControlWriter = FutureOr<void> Function(bool value);
typedef BooleanControlResetter = FutureOr<void> Function();

/// A typed boolean control exposed through the App Adapter capability surface.
///
/// The typed [read], [write], and [reset] methods are the application-facing
/// API. [invoke] is a strict adapter for the generic capability boundary: it
/// accepts only the three declared operations and returns a canonical boolean
/// control value.
final class BooleanControlCapability implements ScenarioControlCapability {
  BooleanControlCapability({
    required String id,
    required this.readOperation,
    required this.writeOperation,
    required this.resetOperation,
    required BooleanControlReader read,
    required BooleanControlWriter write,
    required BooleanControlResetter reset,
    int version = 1,
  }) : _readCallback = read,
       _writeCallback = write,
       _resetCallback = reset,
       _descriptor = CapabilityDescriptor(
         id: id,
         version: version,
         operations: <String>{readOperation, writeOperation, resetOperation},
       ) {
    if (_descriptor.operations.length != 3) {
      throw ArgumentError(
        'Boolean control read, write, and reset operations must be distinct',
      );
    }
  }

  @override
  final String readOperation;
  @override
  final String writeOperation;
  @override
  final String resetOperation;
  final BooleanControlReader _readCallback;
  final BooleanControlWriter _writeCallback;
  final BooleanControlResetter _resetCallback;
  final CapabilityDescriptor _descriptor;

  @override
  CapabilityDescriptor get descriptor => _descriptor;

  Future<bool> read() async => _readCallback();

  Future<bool> write(bool value) async {
    await _writeCallback(value);
    return read();
  }

  @override
  Future<void> reset() async => _resetCallback();

  @override
  Future<ScenarioControlValue> readControl() async =>
      BooleanScenarioControlValue(await read());

  @override
  Future<ScenarioControlValue> writeControl(ScenarioControlValue value) async {
    if (value is! BooleanScenarioControlValue) {
      throw const FormatException('Boolean control requires a boolean value');
    }
    return BooleanScenarioControlValue(await write(value.value));
  }

  @override
  Future<ScenarioControlValue> resetControl() async {
    await reset();
    return BooleanScenarioControlValue(await read());
  }

  @override
  Future<Object?> invoke(
    String operation,
    Map<String, Object?> arguments,
  ) async {
    if (operation == readOperation) {
      _requireArguments(arguments, const <String>{}, operation);
      return _result(await read());
    }
    if (operation == writeOperation) {
      _requireArguments(arguments, const <String>{'value'}, operation);
      final value = arguments['value'];
      if (value is! bool) {
        throw const FormatException('Boolean control value must be a boolean');
      }
      return _result(await write(value));
    }
    if (operation == resetOperation) {
      _requireArguments(arguments, const <String>{}, operation);
      await reset();
      return _result(await read());
    }
    throw StateError('Unsupported operation $operation');
  }
}

Map<String, Object?> _result(bool value) => <String, Object?>{
  'kind': ScenarioControlValueKind.boolean.name,
  'value': value,
};

void _requireArguments(
  Map<String, Object?> arguments,
  Set<String> expected,
  String operation,
) {
  if (arguments.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(arguments.keys.toSet()).isNotEmpty) {
    throw FormatException(
      'Operation $operation requires exactly ${expected.toList()..sort()}',
    );
  }
}
