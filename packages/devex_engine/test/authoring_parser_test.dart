import 'package:devex_engine/devex_engine.dart';
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

  test('migrates the adjacent legacy shape explicitly', () {
    final result = parser.parse(
      'schemaVersion: 0\ntype: Workspace\nid: sample\nproperties: {displayName: Sample}',
      sourceName: 'legacy.yaml',
    );

    expect(result.schemaVersion, 1);
    expect(result.wasMigrated, isTrue);
  });
}
