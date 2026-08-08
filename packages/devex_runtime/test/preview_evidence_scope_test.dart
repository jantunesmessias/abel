import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/src/host/preview_evidence_scope.dart';
import 'package:test/test.dart';

void main() {
  test('preserves a filtered collection scope for freshness comparison', () {
    final catalogDigest = _digest('catalog');
    final dark = _descriptor('phone.dark', PreviewBrightness.dark);
    final light = _descriptor('phone.light', PreviewBrightness.light);
    final fullManifest = PreviewManifest(
      catalogDigest: catalogDigest,
      flutterCompatibility: '3.44.x',
      descriptors: <PreviewDescriptor>[dark, light],
    );
    final filteredManifest = PreviewManifest(
      catalogDigest: catalogDigest,
      flutterCompatibility: '3.44.x',
      descriptors: <PreviewDescriptor>[dark],
    );
    final capture = PreviewCaptureManifest(
      previewManifestDigest: filteredManifest.digest,
      renderer: 'flutter-test',
      toolchainDigest: _digest('toolchain'),
      executionFingerprintDigest: _digest('fingerprint'),
      items: <PreviewCaptureItem>[_captureItem(dark)],
    );

    final scope = PreviewEvidenceScope.bind(
      capture: capture,
      currentDescriptors: <PreviewDescriptor>[dark, light],
      catalogDigest: catalogDigest,
      flutterCompatibility: '3.44.x',
    );

    expect(scope.hasUnboundItems, isFalse);
    expect(scope.descriptorFor(capture.items.single), same(dark));
    expect(
      scope.manifestsByApplication[ApplicationId('sample')]!.digest,
      filteredManifest.digest,
    );
    expect(
      scope.manifestsByApplication[ApplicationId('sample')]!.digest,
      isNot(fullManifest.digest),
    );
  });

  test('reports capture items missing from the current manifest', () {
    final descriptor = _descriptor('phone.dark', PreviewBrightness.dark);
    final capture = PreviewCaptureManifest(
      previewManifestDigest: _digest('manifest'),
      renderer: 'flutter-test',
      toolchainDigest: _digest('toolchain'),
      executionFingerprintDigest: _digest('fingerprint'),
      items: <PreviewCaptureItem>[_captureItem(descriptor)],
    );

    final scope = PreviewEvidenceScope.bind(
      capture: capture,
      currentDescriptors: const <PreviewDescriptor>[],
      catalogDigest: _digest('catalog'),
      flutterCompatibility: '3.44.x',
    );

    expect(scope.hasUnboundItems, isTrue);
    expect(scope.descriptorFor(capture.items.single), isNull);
    expect(scope.manifestsByApplication, isEmpty);
  });
}

PreviewDescriptor _descriptor(String variantId, PreviewBrightness brightness) =>
    PreviewDescriptor(
      id: AutoPreviewId('sample.launch'),
      scenarioId: ScenarioId('launch-sample'),
      variant: Variant(
        id: VariantId(variantId),
        applicationId: ApplicationId('sample'),
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 3,
        brightness: brightness,
        localeTag: 'pt-BR',
      ),
      sourceUri: 'package:sample/launch_preview.dart',
      declarationName: 'launchPreview',
      capturePolicyId: 'static-v1',
    );

PreviewCaptureItem _captureItem(PreviewDescriptor descriptor) =>
    PreviewCaptureItem(
      previewId: descriptor.id,
      scenarioId: descriptor.scenarioId,
      variantId: descriptor.variant.id,
      descriptorDigest: descriptor.digest,
      captureKey: _digest('capture-${descriptor.variant.id.value}'),
      status: PreviewCaptureStatus.failed,
    );

Digest _digest(String value) =>
    Digest.semantic(<String, Object?>{'value': value});
