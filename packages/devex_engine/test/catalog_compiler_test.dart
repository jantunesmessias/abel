import 'dart:math';

import 'package:devex_engine/devex_engine.dart';
import 'package:test/test.dart';

void main() {
  const compiler = CatalogCompiler();

  test('is deterministic across input order', () {
    final documents = _smallCatalog();
    final forward = compiler.compile(documents);
    final reverse = compiler.compile(documents.reversed);

    expect(forward.digest, reverse.digest);
    expect(forward.toJson(), reverse.toJson());
  });

  test('rejects dangling references and duplicate identities', () {
    final documents = _smallCatalog()
      ..add(
        _document(AuthoringKind.scenario, 'first', <String, Object?>{
          'applicationId': 'missing',
          'title': 'Duplicate',
        }),
      );

    expect(
      () => compiler.compile(documents),
      throwsA(
        isA<CatalogCompileException>().having(
          (error) => error.issues.join(' '),
          'issues',
          contains('duplicate document'),
        ),
      ),
    );
  });

  test('compiles 1000 scenarios and 5000 transitions within the V0 budget', () {
    final documents = <AuthoringDocument>[
      _document(AuthoringKind.workspace, 'scale', <String, Object?>{
        'displayName': 'Scale corpus',
      }),
      _document(AuthoringKind.application, 'app', <String, Object?>{
        'workspaceId': 'scale',
        'displayName': 'App',
        'root': '.',
        'target': 'local',
      }),
      _document(AuthoringKind.journey, 'journey', <String, Object?>{
        'applicationId': 'app',
        'title': 'Journey',
        'scenarioIds': <String>[
          for (var index = 0; index < 1000; index += 1) 's-$index',
        ],
      }),
      for (var index = 0; index < 1000; index += 1)
        _document(AuthoringKind.scenario, 's-$index', <String, Object?>{
          'applicationId': 'app',
          'title': 'Scenario $index',
        }),
      for (var index = 0; index < 5000; index += 1)
        _document(AuthoringKind.transition, 't-$index', <String, Object?>{
          'journeyId': 'journey',
          'from': 's-${index % 1000}',
          'to': 's-${(index + 1) % 1000}',
        }),
    ]..shuffle(Random(42));
    final stopwatch = Stopwatch()..start();
    final manifest = compiler.compile(documents);
    stopwatch.stop();

    expect(manifest.scenarios, hasLength(1000));
    expect(manifest.transitions, hasLength(5000));
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
  });
}

List<AuthoringDocument> _smallCatalog() => <AuthoringDocument>[
  _document(AuthoringKind.workspace, 'sample', <String, Object?>{
    'displayName': 'Sample',
  }),
  _document(AuthoringKind.application, 'app', <String, Object?>{
    'workspaceId': 'sample',
    'displayName': 'App',
    'root': '.',
    'target': 'local',
  }),
  _document(AuthoringKind.scenario, 'first', <String, Object?>{
    'applicationId': 'app',
    'title': 'First',
  }),
  _document(AuthoringKind.scenario, 'second', <String, Object?>{
    'applicationId': 'app',
    'title': 'Second',
  }),
  _document(AuthoringKind.journey, 'flow', <String, Object?>{
    'applicationId': 'app',
    'title': 'Flow',
    'scenarioIds': <String>['first', 'second'],
  }),
  _document(AuthoringKind.transition, 'next', <String, Object?>{
    'journeyId': 'flow',
    'from': 'first',
    'to': 'second',
  }),
];

AuthoringDocument _document(
  AuthoringKind kind,
  String id,
  Map<String, Object?> spec,
) => AuthoringDocument(
  schemaVersion: 1,
  kind: kind,
  id: id,
  spec: spec,
  sourceName: '${kind.name}/$id.yaml',
);
