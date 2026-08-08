import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const parser = SafeAuthoringParser();

  test('parses strict YAML and JSON documents', () {
    final yaml = parser.parse('''
schemaVersion: 1
kind: Scenario
metadata:
  id: signed-out
spec:
  applicationId: catalog
  title: Signed out
''', sourceName: 'scenario.yaml');
    final json = parser.parse(
      '{"schemaVersion":1,"kind":"Workspace","metadata":{"id":"sample"},"spec":{"displayName":"Sample"}}',
      sourceName: 'workspace.json',
    );

    expect(yaml.kind, AuthoringKind.scenario);
    expect(yaml.id, 'signed-out');
    expect(json.kind, AuthoringKind.workspace);
  });

  test('fails closed for unknown fields and excessive depth', () {
    expect(
      () => parser.parse(
        'schemaVersion: 1\nkind: Workspace\nmetadata: {id: sample}\nspec: {}\nsecret: value',
        sourceName: 'unknown.yaml',
      ),
      throwsA(isA<AuthoringParseException>()),
    );
    const shallow = SafeAuthoringParser(maxDepth: 2);
    expect(
      () => shallow.parse(
        'schemaVersion: 1\nkind: Workspace\nmetadata: {id: sample}\nspec: {a: {b: 1}}',
        sourceName: 'deep.yaml',
      ),
      throwsA(isA<AuthoringParseException>()),
    );
  });

  test('rejects duplicate JSON keys including escaped-equivalent keys', () {
    for (final source in <String>[
      '{"schemaVersion":1,"schemaVersion":1,"kind":"Workspace","metadata":{"id":"sample"},"spec":{}}',
      '{"schemaVersion":1,"kind":"Workspace","metadata":{"id":"sample","\\u0069d":"other"},"spec":{}}',
    ]) {
      expect(
        () => parser.parse(source, sourceName: 'duplicate.json'),
        throwsA(
          isA<AuthoringParseException>().having(
            (error) => error.message,
            'message',
            contains('duplicate key'),
          ),
        ),
      );
    }
  });

  test('applies depth, node and interoperable-number limits to JSON', () {
    expect(
      () => const SafeAuthoringParser(
        maxDepth: 2,
      ).parseObject('{"a":{"b":{"c":1}}}', sourceName: 'deep.json'),
      throwsA(isA<AuthoringParseException>()),
    );
    expect(
      () => const SafeAuthoringParser(
        maxNodes: 3,
      ).parseObject('{"a":1,"b":2,"c":3}', sourceName: 'large.json'),
      throwsA(isA<AuthoringParseException>()),
    );
    expect(
      () => parser.parseObject(
        '{"value":9007199254740992}',
        sourceName: 'unsafe-number.json',
      ),
      throwsA(
        isA<AuthoringParseException>().having(
          (error) => error.message,
          'message',
          contains('non-interoperable number'),
        ),
      ),
    );
  });

  test('rejects removed authoring schema revisions', () {
    expect(
      () => parser.parse(
        'schemaVersion: 0\ntype: Workspace\nid: sample\nproperties: {displayName: Sample}',
        sourceName: 'removed-schema.yaml',
      ),
      throwsA(
        isA<AuthoringParseException>().having(
          (error) => error.message,
          'message',
          'schemaVersion must equal 1 or 2',
        ),
      ),
    );
  });

  test('keeps topology authoring on adjacent v2 only', () {
    final topology = parser.parse('''
schemaVersion: 2
kind: Board
metadata: {id: product-flow}
spec:
  applicationId: sample
  title: Product flow
  projectionIds: [primary-journey]
''', sourceName: 'board.yaml');

    expect(topology.schemaVersion, 2);
    expect(topology.kind, AuthoringKind.board);
    expect(
      () => parser.parse('''
schemaVersion: 1
kind: Board
metadata: {id: product-flow}
spec: {}
''', sourceName: 'board-v1.yaml'),
      throwsA(isA<AuthoringParseException>()),
    );
    expect(
      () => parser.parse('''
schemaVersion: 2
kind: Scenario
metadata: {id: ready}
spec: {}
''', sourceName: 'scenario-v2.yaml'),
      throwsA(isA<AuthoringParseException>()),
    );
  });
}
