import 'package:flutter/widgets.dart';
import 'package:sample_flutter/app_factory.dart';

void main() {
  const apiBaseUrl = String.fromEnvironment(
    'EXAMPLE_API_URL',
    defaultValue: 'http://127.0.0.1:8181',
  );
  runApp(
    createSampleApp(
      const SampleAppConfig(
        apiBaseUrl: apiBaseUrl,
        environment: 'local-production',
      ),
    ),
  );
}
