import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_flutter/app_factory.dart';
import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_fixture_api.dart';

void main() {
  testWidgets('consumer factory renders dashboard data without a DevEx type', (
    tester,
  ) async {
    await tester.pumpWidget(
      createSampleApp(
        const SampleAppConfig(
          apiBaseUrl: 'http://127.0.0.1:8181',
          environment: 'test',
        ),
        api: SyntheticShowcaseApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delivery Lab'), findsOneWidget);
    expect(find.text('Mobile foundation'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('consumer renders a recoverable API failure state', (
    tester,
  ) async {
    await tester.pumpWidget(
      createSampleApp(
        const SampleAppConfig(
          apiBaseUrl: 'http://127.0.0.1:8181',
          environment: 'test',
        ),
        api: SyntheticShowcaseApi(
          failure: const ShowcaseApiException(
            statusCode: 503,
            code: 'TEST_FAILURE',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The workspace API is unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  test('production entrypoint does not import a devex package', () {
    final workspacePath = File('examples/sample_flutter/lib/main.dart');
    final packagePath = File('lib/main.dart');
    final entrypoint = workspacePath.existsSync() ? workspacePath : packagePath;
    final source = entrypoint.readAsStringSync();

    expect(source, isNot(contains('package:devex_')));
    expect(source, contains('package:sample_flutter/app_factory.dart'));
  });
}
