import 'package:devex_contracts/devex_contracts.dart';
import 'package:test/test.dart';

void main() {
  const canonicalizer = JcsCanonicalizer();

  test('sorts object keys and emits deterministic JCS', () {
    final value = <String, Object?>{'b': 2, 'a': 1};

    expect(canonicalizer.canonicalize(value), '{"a":1,"b":2}');
    expect(
      Digest.semantic(value).value,
      'sha256:43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777',
    );
  });

  test('uses ECMAScript number thresholds and shortest representation', () {
    expect(
      canonicalizer.canonicalize(<Object?>[
        333333333.33333329,
        1e30,
        4.50,
        2e-3,
        1e-27,
        1e-6,
      ]),
      '[333333333.3333333,1e+30,4.5,0.002,1e-27,0.000001]',
    );
  });

  test('escapes control characters but preserves Unicode', () {
    expect(
      canonicalizer.canonicalize(<String, Object?>{'text': 'Euro: €\nTab:\t'}),
      '{"text":"Euro: €\\nTab:\\t"}',
    );
  });

  test('rejects values outside the DevExKit I-JSON profile', () {
    expect(
      () => canonicalizer.canonicalize(-0.0),
      throwsA(isA<CanonicalJsonException>()),
    );
    expect(
      () => canonicalizer.canonicalize(double.nan),
      throwsA(isA<CanonicalJsonException>()),
    );
    expect(
      () => canonicalizer.canonicalize(9007199254740992),
      throwsA(isA<CanonicalJsonException>()),
    );
    expect(
      () => canonicalizer.canonicalize(<Object?, Object?>{1: 'invalid'}),
      throwsA(isA<CanonicalJsonException>()),
    );
  });

  test('rejects cyclic values', () {
    final value = <Object?>[];
    value.add(value);

    expect(
      () => canonicalizer.canonicalize(value),
      throwsA(isA<CanonicalJsonException>()),
    );
  });
}
