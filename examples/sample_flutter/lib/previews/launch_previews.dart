import 'package:devex_preview/devex_preview.dart';
import 'package:flutter/material.dart';
import 'package:sample_flutter/app_factory.dart';
import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_fixture_api.dart';

@AutoPreview(
  id: 'sample.dashboard.loading',
  scenarioId: 'dashboard-loading',
  variantId: 'phone.light.en-us',
  name: 'Loading · phone light',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
  fixtureRef: 'sample.dashboard.pending',
)
Widget dashboardLoadingPreview() => createSampleApp(
  const SampleAppConfig(
    apiBaseUrl: 'https://example.invalid',
    environment: 'preview-loading',
  ),
  api: PendingShowcaseApi(),
);

@AutoMultiPreview(
  id: 'sample.dashboard.ready',
  scenarioId: 'dashboard-ready',
  fixtureRef: 'sample.dashboard.synthetic',
  capturePolicyId: 'static-v1',
  variants: <AutoPreviewVariant>[
    AutoPreviewVariant(
      variantId: 'phone.light.en-us',
      name: 'Phone light · en-US',
      size: Size(390, 844),
      devicePixelRatio: 3,
      localeTag: 'en-US',
      brightness: Brightness.light,
    ),
    AutoPreviewVariant(
      variantId: 'phone.dark.en-us',
      name: 'Phone dark · en-US',
      size: Size(390, 844),
      devicePixelRatio: 3,
      localeTag: 'en-US',
      brightness: Brightness.dark,
    ),
    AutoPreviewVariant(
      variantId: 'desktop.light.en-us',
      name: 'Desktop light · en-US',
      size: Size(1280, 900),
      devicePixelRatio: 1,
      localeTag: 'en-US',
      brightness: Brightness.light,
    ),
  ],
)
Widget dashboardReadyPreviews() => createSampleApp(
  const SampleAppConfig(
    apiBaseUrl: 'https://example.invalid',
    environment: 'preview-ready',
  ),
  api: SyntheticShowcaseApi(),
);

@AutoPreview(
  id: 'sample.dashboard.task-toggled',
  scenarioId: 'toggle-delivery-task',
  variantId: 'phone.light.en-us',
  name: 'Task completed · phone light',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
  fixtureRef: 'sample.dashboard.task-toggled',
)
Widget dashboardTaskToggledPreview() => createSampleApp(
  const SampleAppConfig(
    apiBaseUrl: 'https://example.invalid',
    environment: 'preview-task-toggled',
  ),
  api: SyntheticShowcaseApi(
    dashboard: syntheticDashboard(deliveryTaskCompleted: true),
  ),
);

@AutoPreview(
  id: 'sample.dashboard.gateway-traffic',
  scenarioId: 'inspect-gateway-traffic',
  variantId: 'desktop.light.en-us',
  name: 'Gateway hybrid traffic · desktop light',
  size: Size(1280, 900),
  devicePixelRatio: 1,
  localeTag: 'en-US',
  brightness: Brightness.light,
  fixtureRef: 'sample.dashboard.gateway-hybrid',
)
Widget dashboardGatewayTrafficPreview() => createSampleApp(
  const SampleAppConfig(
    apiBaseUrl: 'http://127.0.0.1:8090',
    environment: 'preview-gateway-hybrid',
  ),
  api: SyntheticShowcaseApi(
    dashboard: syntheticDashboard(gatewayTrafficObserved: true),
  ),
);

@AutoPreview(
  id: 'sample.dashboard.failed',
  scenarioId: 'dashboard-failed',
  variantId: 'phone.light.en-us',
  name: 'API failure · phone light',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
  fixtureRef: 'sample.dashboard.failure',
)
Widget dashboardFailedPreview() => createSampleApp(
  const SampleAppConfig(
    apiBaseUrl: 'https://example.invalid',
    environment: 'preview-failure',
  ),
  api: SyntheticShowcaseApi(
    failure: const ShowcaseApiException(statusCode: 503, code: 'FIXTURE_503'),
  ),
);
