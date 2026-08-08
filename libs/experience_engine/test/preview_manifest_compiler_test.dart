import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const compiler = PreviewManifestCompiler();

  test('expands and sorts declarations using the Scenario application', () {
    final catalog = _catalog();
    final manifest = compiler.compile(
      candidates: <PreviewDeclarationCandidate>[
        _candidate(
          id: 'sample.launch',
          variants: <PreviewVariantCandidate>[
            _variant('phone.light'),
            _variant('phone.dark', brightness: PreviewBrightness.dark),
          ],
        ),
      ],
      catalog: catalog,
      flutterCompatibility: '3.44.x',
    );

    expect(manifest.descriptors.map((value) => value.key), <String>[
      'sample.launch:phone.dark',
      'sample.launch:phone.light',
    ]);
    expect(
      manifest.descriptors.first.variant.applicationId,
      ApplicationId('sample'),
    );
    expect(manifest.catalogDigest, catalog.digest);
    expect(PreviewManifest.fromJson(manifest.toJson()).digest, manifest.digest);
  });

  test('is independent from source enumeration order', () {
    final catalog = _catalog();
    final left = compiler.compile(
      candidates: <PreviewDeclarationCandidate>[
        _candidate(
          id: 'sample.z',
          variants: <PreviewVariantCandidate>[_variant('z')],
        ),
        _candidate(
          id: 'sample.a',
          variants: <PreviewVariantCandidate>[_variant('a')],
        ),
      ],
      catalog: catalog,
      flutterCompatibility: '3.44.x',
    );
    final right = compiler.compile(
      candidates: <PreviewDeclarationCandidate>[
        _candidate(
          id: 'sample.a',
          variants: <PreviewVariantCandidate>[_variant('a')],
        ),
        _candidate(
          id: 'sample.z',
          variants: <PreviewVariantCandidate>[_variant('z')],
        ),
      ],
      catalog: catalog,
      flutterCompatibility: '3.44.x',
    );
    expect(left.digest, right.digest);
  });

  test('rejects missing Scenario and non-package source URI', () {
    expect(
      () => compiler.compile(
        candidates: <PreviewDeclarationCandidate>[
          _candidate(
            scenarioId: 'missing',
            sourceUri: 'file:///tmp/preview.dart',
            variants: <PreviewVariantCandidate>[_variant('phone')],
          ),
        ],
        catalog: _catalog(),
        flutterCompatibility: '3.44.x',
      ),
      throwsA(
        isA<PreviewCompileException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          allOf(contains('unknown Scenario missing'), contains('package URI')),
        ),
      ),
    );
  });

  test('rejects empty and duplicate Variants', () {
    expect(
      () => compiler.compile(
        candidates: <PreviewDeclarationCandidate>[
          _candidate(variants: const <PreviewVariantCandidate>[]),
          _candidate(
            id: 'sample.other',
            variants: <PreviewVariantCandidate>[
              _variant('phone'),
              _variant('phone'),
            ],
          ),
        ],
        catalog: _catalog(),
        flutterCompatibility: '3.44.x',
      ),
      throwsA(
        isA<PreviewCompileException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          allOf(contains('must not be empty'), contains('duplicate Variant')),
        ),
      ),
    );
  });

  test('rejects divergent canonical Variant definitions', () {
    expect(
      () => compiler.compile(
        candidates: <PreviewDeclarationCandidate>[
          _candidate(
            id: 'sample.first',
            variants: <PreviewVariantCandidate>[_variant('phone')],
          ),
          _candidate(
            id: 'sample.second',
            variants: <PreviewVariantCandidate>[_variant('phone', width: 430)],
          ),
        ],
        catalog: _catalog(),
        flutterCompatibility: '3.44.x',
      ),
      throwsA(
        isA<PreviewCompileException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          contains('divergent definitions'),
        ),
      ),
    );
  });
}

PreviewDeclarationCandidate _candidate({
  String id = 'sample.launch',
  String scenarioId = 'launch-sample',
  String sourceUri = 'package:sample_flutter/previews/launch.dart',
  List<PreviewVariantCandidate>? variants,
}) => PreviewDeclarationCandidate(
  id: id,
  scenarioId: scenarioId,
  sourceUri: sourceUri,
  declarationName: 'launchPreview',
  capturePolicyId: 'static-v1',
  variants: variants ?? <PreviewVariantCandidate>[_variant('phone')],
);

PreviewVariantCandidate _variant(
  String id, {
  double width = 390,
  PreviewBrightness brightness = PreviewBrightness.light,
}) => PreviewVariantCandidate(
  id: id,
  logicalWidth: width,
  logicalHeight: 844,
  devicePixelRatio: 3,
  brightness: brightness,
  localeTag: 'pt-BR',
  textScaleFactor: 1,
);

CatalogManifest _catalog() => CatalogManifest(
  distribution: DistributionDescriptor(
    id: 'full-local',
    displayName: 'Abel',
    coreCompatibility: '^0.1.0',
    defaultLayout: ConsumerLayout.standard,
  ),
  layout: ConsumerLayout.standard,
  workspace: Workspace(id: WorkspaceId('workspace'), displayName: 'Workspace'),
  applications: <Application>[
    Application(
      id: ApplicationId('sample'),
      workspaceId: WorkspaceId('workspace'),
      displayName: 'Sample',
      root: 'examples/sample_flutter',
      target: 'flutter',
    ),
  ],
  journeys: const <Journey>[],
  scenarios: <Scenario>[
    Scenario(
      id: ScenarioId('launch-sample'),
      applicationId: ApplicationId('sample'),
      title: 'Launch',
    ),
  ],
  transitions: const <Transition>[],
);
