import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friction_flutter/main.dart';

void main() {
  testWidgets('starts with no DevExKit integration', (tester) async {
    await tester.pumpWidget(const FrictionApp());

    expect(find.text('Consumidor sem integracao DevExKit'), findsOneWidget);
  });

  test('consumer source has no devex import', () {
    final workspacePath = File('test/consumers/friction_flutter/lib/main.dart');
    final packagePath = File('lib/main.dart');
    final source = (workspacePath.existsSync() ? workspacePath : packagePath)
        .readAsStringSync();

    expect(source, isNot(contains('package:devex_')));
  });
}
