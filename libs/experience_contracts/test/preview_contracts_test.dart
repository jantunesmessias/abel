import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('Variant and Preview documents round-trip with stable digests', () {
    final first = _descriptor('phone.light', width: 390);
    final second = _descriptor('tablet.dark', width: 800);
    final manifest = PreviewManifest(
      catalogDigest: Digest.semantic(const <String, Object?>{'catalog': 1}),
      flutterCompatibility: '3.44.x',
      descriptors: <PreviewDescriptor>[second, first],
    );
    final reordered = PreviewManifest(
      catalogDigest: manifest.catalogDigest,
      flutterCompatibility: '3.44.x',
      descriptors: <PreviewDescriptor>[first, second],
    );

    expect(manifest.digest, reordered.digest);
    expect(manifest.descriptors.map((item) => item.variant.id.value), <String>[
      'phone.light',
      'tablet.dark',
    ]);
    expect(
      Variant.fromJson(first.variant.toJson()).digest,
      first.variant.digest,
    );
    expect(PreviewDescriptor.fromJson(first.toJson()).digest, first.digest);
    expect(PreviewManifest.fromJson(manifest.toJson()).digest, manifest.digest);
  });

  test('rejects divergent Variant and Preview Scenario definitions', () {
    final first = _descriptor('phone.light', width: 390);

    expect(
      () => PreviewManifest(
        catalogDigest: Digest.semantic(const <String, Object?>{}),
        flutterCompatibility: '3.44.x',
        descriptors: <PreviewDescriptor>[
          first,
          _descriptor('phone.light', width: 400, previewId: 'sample.other'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => PreviewManifest(
        catalogDigest: Digest.semantic(const <String, Object?>{}),
        flutterCompatibility: '3.44.x',
        descriptors: <PreviewDescriptor>[
          first,
          _descriptor(
            'tablet.dark',
            width: 800,
            scenarioId: 'another-scenario',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('capture manifest is deterministic and enforces artifact status', () {
    final descriptor = _descriptor('phone.light', width: 390);
    final captureKey = Digest.semantic(const <String, Object?>{
      'descriptor': 'phone.light',
      'renderer': 'flutter-test',
    });
    final collected = PreviewCaptureItem(
      previewId: descriptor.id,
      scenarioId: descriptor.scenarioId,
      variantId: descriptor.variant.id,
      descriptorDigest: descriptor.digest,
      captureKey: captureKey,
      status: PreviewCaptureStatus.collected,
      artifactDigest: Digest.bytes(const <int>[1, 2, 3]),
      pixelDigest: Digest.bytes(const <int>[4, 5, 6]),
      pixelWidth: 1170,
      pixelHeight: 2532,
    );
    final failed = PreviewCaptureItem(
      previewId: AutoPreviewId('sample.launch'),
      scenarioId: ScenarioId('launch-sample'),
      variantId: VariantId('tablet.dark'),
      descriptorDigest: Digest.semantic(const <String, Object?>{'item': 2}),
      captureKey: Digest.semantic(const <String, Object?>{'capture': 2}),
      status: PreviewCaptureStatus.failed,
      diagnostics: <PreviewCaptureDiagnostic>[
        PreviewCaptureDiagnostic(
          code: 'preview.widget.failed',
          severity: PreviewDiagnosticSeverity.error,
          message: 'Widget build failed',
        ),
      ],
    );
    final manifest = PreviewCaptureManifest(
      previewManifestDigest: Digest.semantic(const <String, Object?>{
        'preview': 1,
      }),
      renderer: 'flutter-test',
      toolchainDigest: Digest.semantic(const <String, Object?>{'flutter': 1}),
      executionFingerprintDigest: Digest.semantic(const <String, Object?>{
        'fingerprint': 1,
      }),
      items: <PreviewCaptureItem>[failed, collected],
    );
    final reordered = PreviewCaptureManifest(
      previewManifestDigest: manifest.previewManifestDigest,
      renderer: manifest.renderer,
      toolchainDigest: manifest.toolchainDigest,
      executionFingerprintDigest: manifest.executionFingerprintDigest,
      items: <PreviewCaptureItem>[collected, failed],
    );

    expect(manifest.digest, reordered.digest);
    expect(
      PreviewCaptureManifest.fromJson(manifest.toJson()).digest,
      manifest.digest,
    );
    expect(
      () => PreviewCaptureItem(
        previewId: descriptor.id,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        descriptorDigest: descriptor.digest,
        captureKey: captureKey,
        status: PreviewCaptureStatus.failed,
        artifactDigest: Digest.bytes(const <int>[1]),
      ),
      throwsArgumentError,
    );
  });

  test('capture report is temporal, closed, and digest verified', () {
    final report = PreviewCaptureReport(
      captureManifestDigest: Digest.semantic(const <String, Object?>{
        'capture': 1,
      }),
      startedAt: DateTime.utc(2026, 8, 10, 12),
      completedAt: DateTime.utc(2026, 8, 10, 12, 0, 2),
      totalItems: 2,
      collectedItems: 1,
      failedItems: 1,
    );

    expect(
      PreviewCaptureReport.fromJson(report.toJson()).digest,
      report.digest,
    );
    expect(
      () => PreviewCaptureReport.fromJson(<String, Object?>{
        ...report.toJson(),
        'unexpected': true,
      }),
      throwsFormatException,
    );
    expect(
      () => PreviewCaptureReport(
        captureManifestDigest: report.captureManifestDigest,
        startedAt: report.startedAt,
        completedAt: report.completedAt,
        totalItems: 2,
        collectedItems: 2,
        failedItems: 1,
      ),
      throwsArgumentError,
    );
  });
}

PreviewDescriptor _descriptor(
  String variantId, {
  required double width,
  String previewId = 'sample.launch',
  String scenarioId = 'launch-sample',
}) => PreviewDescriptor(
  id: AutoPreviewId(previewId),
  scenarioId: ScenarioId(scenarioId),
  variant: Variant(
    id: VariantId(variantId),
    applicationId: ApplicationId('sample'),
    logicalWidth: width,
    logicalHeight: 844,
    devicePixelRatio: 3,
    brightness: variantId.endsWith('dark')
        ? PreviewBrightness.dark
        : PreviewBrightness.light,
    localeTag: 'pt-BR',
  ),
  sourceUri: 'package:sample_flutter/previews/launch_preview.dart',
  declarationName: 'launchSamplePreview',
  capturePolicyId: 'static-v1',
  fixtureRef: 'sample.launch.synthetic',
);
