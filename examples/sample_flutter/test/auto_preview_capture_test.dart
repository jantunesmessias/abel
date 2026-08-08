import 'package:flutter_test/flutter_test.dart';
import 'package:sample_flutter/previews/launch_previews.dart';

void main() {
  testWidgets('AutoPreview mounts the real consumer factory', (tester) async {
    await tester.pumpWidget(dashboardReadyPreviews());
    await tester.pumpAndSettle();

    expect(find.text('Delivery Lab'), findsOneWidget);
    expect(find.text('Mobile foundation'), findsOneWidget);
  });
}
