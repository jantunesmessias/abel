import 'package:devex_contracts/devex_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('owns source bytes, rejects mutation, and reuses immutable values', () {
    final source = <int>[1, 2, 3];
    final immutable = ImmutableBytes.copyOf(source);
    source[0] = 9;

    expect(immutable, <int>[1, 2, 3]);
    expect(() => immutable[0] = 9, throwsUnsupportedError);
    expect(identical(ImmutableBytes.copyOf(immutable), immutable), isTrue);
  });

  test('rejects values outside the byte range', () {
    expect(() => ImmutableBytes.copyOf(<int>[256]), throwsFormatException);
  });
}
