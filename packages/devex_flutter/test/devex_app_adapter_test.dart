import 'dart:convert';

import 'package:devex_flutter/devex_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'declares, invokes and resets an injected simulated capability',
    () async {
      final locale = SimulatedStringCapability(
        id: 'sample.locale',
        initialValue: 'pt-BR',
        allowedValues: const <String>{'pt-BR', 'en-US'},
      );
      final adapter = DevExAppAdapter(
        capabilities: <DevExCapability>[locale],
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
      final adapter = DevExAppAdapter(
        capabilities: const <DevExCapability>[],
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
