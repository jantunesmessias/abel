import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_flutter/app_factory.dart';
import 'package:sample_flutter/showcase_fixture_api.dart';
import 'package:sample_flutter/showcase_models.dart';

void main() {
  testWidgets(
    'consumer factory renders dashboard data without a platform type',
    (tester) async {
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
    },
  );

  testWidgets('live ready control changes capture pixels and resets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final highlighted = ValueNotifier<bool>(false);
    final control = BooleanControlCapability(
      id: 'sample.dashboard.ready-control',
      readOperation: 'read-enabled',
      writeOperation: 'write-enabled',
      resetOperation: 'reset-enabled',
      read: () => highlighted.value,
      write: (value) => highlighted.value = value,
      reset: () => highlighted.value = false,
    );
    final capture = WidgetCaptureController();
    final adapter = AppAdapter(
      capabilities: <AppCapability>[control],
      captureHandler: (_) => capture.capturePng(),
    );
    await tester.pumpWidget(
      capture.wrap(
        createSampleApp(
          const SampleAppConfig(
            apiBaseUrl: 'http://127.0.0.1:8181',
            environment: 'test',
          ),
          api: SyntheticShowcaseApi(),
          readyHighlight: highlighted,
        ),
      ),
    );
    await tester.pumpAndSettle();

    const disabledKey = ValueKey<String>(
      'showcase.control.dashboard-ready-highlight.disabled',
    );
    const enabledKey = ValueKey<String>(
      'showcase.control.dashboard-ready-highlight.enabled',
    );
    expect(find.byKey(disabledKey), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier(
              'showcase.control.dashboard-ready-highlight',
            ),
          )
          .value,
      'disabled',
    );
    final disabledCapture = await tester.runAsync(adapter.capture);

    expect(
      await adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.writeOperation,
        arguments: const <String, Object?>{'value': true},
      ),
      <String, Object?>{'kind': 'boolean', 'value': true},
    );
    await tester.pump();
    expect(find.byKey(enabledKey), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier(
              'showcase.control.dashboard-ready-highlight',
            ),
          )
          .value,
      'enabled',
    );
    final enabledCapture = await tester.runAsync(adapter.capture);
    expect(enabledCapture, isNot(equals(disabledCapture)));

    await adapter.invoke(
      capabilityId: control.descriptor.id,
      operation: control.resetOperation,
    );
    await tester.pump();
    expect(find.byKey(disabledKey), findsOneWidget);
    highlighted.dispose();
    semantics.dispose();
  });

  const expectedCopy = <ShowcaseDashboardState, String>{
    ShowcaseDashboardState.ready: 'Mobile foundation',
    ShowcaseDashboardState.loading: 'Loading delivery workspace…',
    ShowcaseDashboardState.empty: 'No delivery projects yet',
    ShowcaseDashboardState.stale: 'Showing a stale snapshot',
    ShowcaseDashboardState.unavailable: 'The workspace API is unavailable',
    ShowcaseDashboardState.failure: 'The dashboard could not be loaded',
  };
  for (final entry in expectedCopy.entries) {
    testWidgets('consumer renders typed ${entry.key.name} state', (
      tester,
    ) async {
      await tester.pumpWidget(
        createSampleApp(
          const SampleAppConfig(
            apiBaseUrl: 'http://127.0.0.1:8181',
            environment: 'test',
          ),
          api: SyntheticShowcaseApi(
            result: syntheticDashboardResult(entry.key),
          ),
        ),
      );
      if (entry.key == ShowcaseDashboardState.loading) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }

      expect(
        find.bySemanticsIdentifier('showcase.state.${entry.key.name}'),
        findsOneWidget,
      );
      expect(find.textContaining(entry.value), findsWidgets);
    });
  }

  testWidgets('unavailable and failure remain visibly distinct', (
    tester,
  ) async {
    await tester.pumpWidget(
      createSampleApp(
        const SampleAppConfig(
          apiBaseUrl: 'http://127.0.0.1:8181',
          environment: 'test',
        ),
        api: SyntheticShowcaseApi(
          result: syntheticDashboardResult(ShowcaseDashboardState.unavailable),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The workspace API is unavailable'), findsOneWidget);
    expect(find.text('The dashboard could not be loaded'), findsNothing);
    expect(
      find.text('Diagnostic · SAMPLE_DEPENDENCY_UNAVAILABLE'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      createSampleApp(
        const SampleAppConfig(
          apiBaseUrl: 'http://127.0.0.1:8181',
          environment: 'test',
        ),
        api: SyntheticShowcaseApi(
          result: syntheticDashboardResult(ShowcaseDashboardState.failure),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The dashboard could not be loaded'), findsOneWidget);
    expect(find.text('The workspace API is unavailable'), findsNothing);
    expect(find.text('Diagnostic · SAMPLE_API_FAILURE'), findsOneWidget);
  });

  test('production entrypoint does not import platform packages', () {
    final workspacePath = File('examples/sample_flutter/lib/main.dart');
    final packagePath = File('lib/main.dart');
    final entrypoint = workspacePath.existsSync() ? workspacePath : packagePath;
    final source = entrypoint.readAsStringSync();

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
    expect(source, contains('package:sample_flutter/app_factory.dart'));
  });
}
