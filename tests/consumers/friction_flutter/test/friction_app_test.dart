import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friction_flutter/main.dart';

void main() {
  testWidgets('starts with no Abel integration', (tester) async {
    await tester.pumpWidget(const FrictionApp());

    expect(find.text('Consumidor sem integracao Abel'), findsOneWidget);
  });

  test('consumer source has no platform import', () {
    final workspacePath = File(
      'tests/consumers/friction_flutter/lib/main.dart',
    );
    final packagePath = File('lib/main.dart');
    final source = (workspacePath.existsSync() ? workspacePath : packagePath)
        .readAsStringSync();

    for (final prefix in <String>[
      'package:execution_runtime/',
      'package:experience_',
      'package:flutter_app_adapter/',
      'package:flutter_preview/',
      'package:interaction_model/',
      'package:studio_ui/',
      'package:testing_support/',
    ]) {
      expect(source, isNot(contains(prefix)));
    }
  });
}
