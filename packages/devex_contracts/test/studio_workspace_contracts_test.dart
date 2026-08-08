import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Studio workspace contracts', () {
    test('round-trips one Host-authoritative workspace snapshot', () {
      final snapshot = _snapshot();

      final decoded = WorkspaceSnapshot.fromJson(snapshot.toJson());

      expect(decoded.digest, snapshot.digest);
      expect(decoded.toJson(), snapshot.toJson());
      expect(decoded.catalog.workspace.displayName, 'Workspace');
      expect(decoded.variantManifest.variants.single.id, VariantId('phone'));
      expect(
        decoded.visualProjections.single.fidelity,
        RuntimeFidelity.structural,
      );
      expect(
        decoded.visualProjections.single.executionFingerprintDigest,
        _digest('execution-fingerprint'),
      );
      expect(decoded.visualProjections.single.capturePolicyId, 'static-v1');
      expect(
        decoded.visualProjections.single.artifactHandle!.uri.pathSegments.first,
        'resources',
      );
    });

    test('public Studio documents conform to the workspace schema', () {
      final validator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(
                  _root(),
                  'schemas',
                  'v1',
                  'studio-workspace.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object,
      );
      final snapshot = _snapshot();
      final documents = <Object>[
        snapshot.variantManifest.toJson(),
        snapshot.visualProjections.single.toJson(),
        snapshot.visualProjections.single.artifactHandle!.toJson(),
        snapshot.toJson(),
      ];

      for (final document in documents) {
        final result = validator.validate(document);
        expect(
          result.isValid,
          isTrue,
          reason: '${result.issues.join('\n')}\n$document',
        );
      }
    });

    test('canonicalizes variants, sources, providers and projections', () {
      final catalog = _catalog();
      final dark = _variant('phone.dark', PreviewBrightness.dark);
      final light = _variant('phone.light', PreviewBrightness.light);
      final manifest = VariantManifest(
        catalogDigest: catalog.digest,
        variants: <Variant>[light, dark],
        sources: <VariantDefinitionSource>[_source(light), _source(dark)],
      );

      expect(manifest.variants.map((item) => item.id.value), <String>[
        'phone.dark',
        'phone.light',
      ]);
      expect(manifest.sources.map((item) => item.variantId.value), <String>[
        'phone.dark',
        'phone.light',
      ]);
    });

    test('keeps legacy visual Evidence explicitly unbound', () {
      final evidenceDigest = _digest('legacy-evidence');
      final projection = VisualEvidenceProjection(
        providerId: ModuleId('capture.app-adapter'),
        status: VisualEvidenceStatus.unbound,
        freshness: EvidenceFreshness.fresh,
        evidenceDigest: evidenceDigest,
        artifactDigest: _digest('legacy-png'),
        fidelity: RuntimeFidelity.simulated,
        observedAt: DateTime.utc(2026, 8, 10),
      );

      expect(projection.scenarioId, isNull);
      expect(projection.variantId, isNull);
      expect(projection.key, contains(':unbound:${evidenceDigest.value}'));
      expect(
        VisualEvidenceProjection.fromJson(projection.toJson()).status,
        VisualEvidenceStatus.unbound,
      );
    });

    test('rejects predictable or query-bearing resource URLs', () {
      for (final uri in <Uri>[
        Uri.parse('http://127.0.0.1:8080/resources/short'),
        Uri.parse('http://127.0.0.1:8080/resources/${'.' * 64}'),
        Uri.parse('http://127.0.0.1:8080/resources/${'a' * 64}?token=secret'),
        Uri.parse('file:///resources/${'a' * 64}'),
      ]) {
        expect(
          () => _resource(uri: uri),
          throwsA(isA<ArgumentError>()),
          reason: '$uri must not be accepted as a scoped HTTP resource',
        );
      }
    });

    test('rejects non-PNG or wrong-purpose visual artifact handles', () {
      final digest = _digest('png');
      for (final handle in <ResourceHandle>[
        ResourceHandle(
          uri: Uri.parse('http://127.0.0.1:8080/resources/${'b' * 64}'),
          digest: digest,
          mediaType: 'application/json',
          size: 1024,
          purpose: 'visual-artifact',
          expiresAt: DateTime.utc(2026, 8, 10, 12),
        ),
        ResourceHandle(
          uri: Uri.parse('http://127.0.0.1:8080/resources/${'c' * 64}'),
          digest: digest,
          mediaType: 'image/png',
          size: 1024,
          purpose: 'workspace-snapshot',
          expiresAt: DateTime.utc(2026, 8, 10, 12),
        ),
      ]) {
        expect(
          () => VisualEvidenceProjection(
            providerId: ModuleId('evidence.auto-preview'),
            scenarioId: ScenarioId('ready'),
            variantId: VariantId('phone'),
            evidenceDigest: _digest('evidence'),
            artifactDigest: digest,
            status: VisualEvidenceStatus.collected,
            freshness: EvidenceFreshness.fresh,
            fidelity: RuntimeFidelity.structural,
            observedAt: DateTime.utc(2026, 8, 10, 11),
            artifactHandle: handle,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test('rejects host-native fidelity for AutoPreview', () {
      expect(
        () => VisualEvidenceProviderState(
          providerId: ModuleId('evidence.auto-preview'),
          displayName: 'AutoPreview',
          health: ModuleHealth.healthy,
          supportedFidelities: const <RuntimeFidelity>{
            RuntimeFidelity.structural,
            RuntimeFidelity.hostNative,
          },
          supportsCollection: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _projection(fidelity: RuntimeFidelity.hostNative),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects forged snapshots and projections for unknown providers', () {
      final forged = _snapshot().toJson()..['digest'] = _digest('forged').value;
      expect(
        () => WorkspaceSnapshot.fromJson(forged),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('digest mismatch'),
          ),
        ),
      );

      final source = _snapshot();
      expect(
        () => WorkspaceSnapshot(
          revision: 1,
          catalog: source.catalog,
          variantManifest: source.variantManifest,
          effectiveKitManifest: source.effectiveKitManifest,
          providers: source.providers,
          visualProjections: <VisualEvidenceProjection>[
            _projection(providerId: ModuleId('evidence.android')),
          ],
          generatedAt: DateTime.utc(2026, 8, 10),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('unknown provider'),
          ),
        ),
      );
    });

    test('rejects a VariantManifest from another catalog', () {
      final source = _snapshot();
      final foreignManifest = VariantManifest(
        catalogDigest: _digest('foreign-catalog'),
        variants: source.variantManifest.variants,
        sources: source.variantManifest.sources,
      );

      expect(
        () => WorkspaceSnapshot(
          revision: 1,
          catalog: source.catalog,
          variantManifest: foreignManifest,
          effectiveKitManifest: source.effectiveKitManifest,
          providers: source.providers,
          visualProjections: source.visualProjections,
          generatedAt: DateTime.utc(2026, 8, 10),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a Variant from an unknown catalog Application', () {
      final source = _snapshot();
      final foreign = Variant(
        id: VariantId('foreign'),
        applicationId: ApplicationId('missing'),
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 3,
        brightness: PreviewBrightness.light,
        localeTag: 'pt-BR',
      );

      expect(
        () => WorkspaceSnapshot(
          revision: 1,
          catalog: source.catalog,
          variantManifest: VariantManifest(
            catalogDigest: source.catalog.digest,
            variants: <Variant>[foreign],
            sources: <VariantDefinitionSource>[_source(foreign)],
          ),
          effectiveKitManifest: source.effectiveKitManifest,
          providers: source.providers,
          visualProjections: const <VisualEvidenceProjection>[],
          generatedAt: DateTime.utc(2026, 8, 10),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

WorkspaceSnapshot _snapshot() {
  final catalog = _catalog();
  final variant = _variant('phone', PreviewBrightness.light);
  final providerId = ModuleId('evidence.auto-preview');
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: <Variant>[variant],
      sources: <VariantDefinitionSource>[_source(variant)],
    ),
    effectiveKitManifest: _effectiveManifest(providerId),
    providers: <VisualEvidenceProviderState>[
      VisualEvidenceProviderState(
        providerId: providerId,
        displayName: 'AutoPreview',
        health: ModuleHealth.healthy,
        supportedFidelities: const <RuntimeFidelity>{
          RuntimeFidelity.structural,
        },
        supportsCollection: true,
      ),
    ],
    visualProjections: <VisualEvidenceProjection>[
      _projection(providerId: providerId),
    ],
    generatedAt: DateTime.utc(2026, 8, 10, 12),
  );
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.devexDefault;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('sample');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'devex-kit',
      displayName: 'DevExKit',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Sample',
        root: 'examples/sample_flutter',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('launch'),
        applicationId: applicationId,
        title: 'Launch',
        scenarioIds: <ScenarioId>[ScenarioId('ready')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('ready'),
        applicationId: applicationId,
        title: 'Ready',
      ),
    ],
    transitions: const <Transition>[],
  );
}

Variant _variant(String id, PreviewBrightness brightness) => Variant(
  id: VariantId(id),
  applicationId: ApplicationId('sample'),
  logicalWidth: 390,
  logicalHeight: 844,
  devicePixelRatio: 3,
  brightness: brightness,
  localeTag: 'pt-BR',
);

VariantDefinitionSource _source(Variant variant) => VariantDefinitionSource(
  variantId: variant.id,
  sourceId: 'auto-preview.sample',
  sourceDigest: _digest('source-${variant.id.value}'),
);

EffectiveKitManifest _effectiveManifest(ModuleId providerId) =>
    EffectiveKitManifest(
      resolvedPlanDigest: _digest('plan'),
      modules: <EffectiveModuleState>[
        EffectiveModuleState(
          moduleId: providerId,
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities: <ModuleCapabilityRef>[
            ModuleCapabilityRef(id: 'evidence.visual', version: 1),
          ],
        ),
      ],
      commands: const <String>['evidence.collect-previews'],
      rpcMethods: const <String>['devex.preview.collect'],
      studioContributions: const <String>['studio.journey-map'],
      generatedAt: DateTime.utc(2026, 8, 10, 12),
    );

VisualEvidenceProjection _projection({
  ModuleId? providerId,
  RuntimeFidelity fidelity = RuntimeFidelity.structural,
}) {
  final artifactDigest = _digest('png');
  return VisualEvidenceProjection(
    providerId: providerId ?? ModuleId('evidence.auto-preview'),
    scenarioId: ScenarioId('ready'),
    variantId: VariantId('phone'),
    evidenceDigest: _digest('evidence'),
    artifactDigest: artifactDigest,
    captureKey: _digest('capture-key'),
    executionFingerprintDigest: _digest('execution-fingerprint'),
    capturePolicyId: 'static-v1',
    status: VisualEvidenceStatus.collected,
    freshness: EvidenceFreshness.fresh,
    fidelity: fidelity,
    observedAt: DateTime.utc(2026, 8, 10, 11),
    artifactHandle: _resource(digest: artifactDigest),
  );
}

ResourceHandle _resource({Uri? uri, Digest? digest}) => ResourceHandle(
  uri: uri ?? Uri.parse('http://127.0.0.1:8080/resources/${'a' * 64}'),
  digest: digest ?? _digest('png'),
  mediaType: 'image/png',
  size: 1024,
  purpose: 'visual-artifact',
  expiresAt: DateTime.utc(2026, 8, 10, 12),
);

Digest _digest(String value) =>
    Digest.semantic(<String, Object?>{'value': value});

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
