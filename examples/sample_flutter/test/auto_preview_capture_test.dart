import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_flutter/previews/launch_previews.dart';
import 'package:sample_flutter/showcase_models.dart';

void main() {
  testWidgets('AutoPreview mounts the real consumer factory', (tester) async {
    await tester.pumpWidget(dashboardReadyPreviews());
    await tester.pumpAndSettle();

    expect(find.text('Delivery Lab'), findsOneWidget);
    expect(find.text('Mobile foundation'), findsOneWidget);
  });

  final matrixPreviews = <ShowcaseDashboardState, Widget Function()>{
    ShowcaseDashboardState.ready: dashboardReadyPreviews,
    ShowcaseDashboardState.loading: dashboardLoadingPreview,
    ShowcaseDashboardState.empty: dashboardEmptyPreview,
    ShowcaseDashboardState.stale: dashboardStalePreview,
    ShowcaseDashboardState.unavailable: dashboardUnavailablePreview,
    ShowcaseDashboardState.failure: dashboardFailedPreview,
  };
  for (final entry in matrixPreviews.entries) {
    testWidgets('AutoPreview proves ${entry.key.name} state semantics', (
      tester,
    ) async {
      await tester.pumpWidget(entry.value());
      if (entry.key == ShowcaseDashboardState.loading) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }

      expect(
        find.bySemanticsIdentifier('showcase.state.${entry.key.name}'),
        findsOneWidget,
      );
    });
  }
}
