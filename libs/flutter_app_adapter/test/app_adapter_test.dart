import 'dart:convert';

import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('boolean control exposes typed read, write, and reset', () async {
    var value = false;
    final control = BooleanControlCapability(
      id: 'sample.dashboard.ready-control',
      readOperation: 'read-enabled',
      writeOperation: 'write-enabled',
      resetOperation: 'reset-enabled',
      read: () => value,
      write: (next) => value = next,
      reset: () => value = false,
    );
    final adapter = AppAdapter(
      capabilities: <AppCapability>[control],
      captureHandler: (_) => const <int>[],
    );

    expect(control.descriptor.id, 'sample.dashboard.ready-control');
    expect(control.descriptor.operations, <String>{
      'read-enabled',
      'write-enabled',
      'reset-enabled',
    });
    expect(await control.read(), isFalse);
    expect(
      await adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.readOperation,
      ),
      <String, Object?>{'kind': 'boolean', 'value': false},
    );
    expect(await control.write(true), isTrue);
    expect(value, isTrue);
    expect(
      await adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.resetOperation,
      ),
      <String, Object?>{'kind': 'boolean', 'value': false},
    );
    expect(value, isFalse);
  });

  test('boolean control rejects ambiguous operations and arguments', () async {
    var value = false;
    var writes = 0;
    final control = BooleanControlCapability(
      id: 'sample.dashboard.ready-control',
      readOperation: 'read-enabled',
      writeOperation: 'write-enabled',
      resetOperation: 'reset-enabled',
      read: () => value,
      write: (next) {
        writes += 1;
        value = next;
      },
      reset: () => value = false,
    );
    final adapter = AppAdapter(
      capabilities: <AppCapability>[control],
      captureHandler: (_) => const <int>[],
    );

    await expectLater(
      adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.readOperation,
        arguments: const <String, Object?>{'extra': true},
      ),
      throwsFormatException,
    );
    await expectLater(
      adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.writeOperation,
        arguments: const <String, Object?>{'value': 'true'},
      ),
      throwsFormatException,
    );
    await expectLater(
      adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.writeOperation,
        arguments: const <String, Object?>{'value': true, 'unexpected': false},
      ),
      throwsFormatException,
    );
    expect(writes, 0);
    expect(value, isFalse);

    expect(
      () => BooleanControlCapability(
        id: 'sample.invalid-control',
        readOperation: 'same',
        writeOperation: 'same',
        resetOperation: 'reset',
        read: () => false,
        write: (_) {},
        reset: () {},
      ),
      throwsArgumentError,
    );
  });

  test(
    'declares, invokes and resets an injected simulated capability',
    () async {
      final locale = SimulatedStringCapability(
        id: 'sample.locale',
        initialValue: 'pt-BR',
        allowedValues: const <String>{'pt-BR', 'en-US'},
      );
      final adapter = AppAdapter(
        capabilities: <AppCapability>[locale],
        captureHandler: (_) => utf8.encode('png'),
      );

      expect(adapter.descriptors.single.id, 'sample.locale');
      await adapter.invoke(
        capabilityId: 'sample.locale',
        operation: 'set',
        arguments: const <String, Object?>{'value': 'en-US'},
      );
      expect(locale.value, 'en-US');
      await adapter.reset();
      expect(locale.value, 'pt-BR');
      expect(utf8.decode(await adapter.capture()), 'png');
    },
  );

  test(
    'fails closed for undeclared capabilities, operations, and formats',
    () async {
      final adapter = AppAdapter(
        capabilities: const <AppCapability>[],
        captureHandler: (_) => const <int>[],
      );

      await expectLater(
        adapter.invoke(capabilityId: 'missing', operation: 'set'),
        throwsStateError,
      );
      await expectLater(adapter.capture(format: 'jpeg'), throwsFormatException);
    },
  );
}
