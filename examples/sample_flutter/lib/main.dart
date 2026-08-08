import 'package:flutter/widgets.dart';
import 'package:sample_flutter/app_factory.dart';
import 'package:sample_flutter/showcase_models.dart';

void main() {
  const apiBaseUrl = String.fromEnvironment(
    'EXAMPLE_API_URL',
    defaultValue: 'http://127.0.0.1:8181',
  );
  const dashboardState = String.fromEnvironment(
    'EXAMPLE_DASHBOARD_STATE',
    defaultValue: 'ready',
  );
  runApp(
    createSampleApp(
      SampleAppConfig(
        apiBaseUrl: apiBaseUrl,
        environment: 'local-production',
        dashboardState: ShowcaseDashboardState.parse(dashboardState),
      ),
    ),
  );
}
