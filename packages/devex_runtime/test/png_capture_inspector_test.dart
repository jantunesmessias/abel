import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  const pixels = <int>[
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    128,
    0,
    0,
    255,
    255,
    255,
    255,
    255,
    0,
  ];
  const inspector = PngCaptureInspector();

  test('normalizes filters and compression into one pixel identity', () {
    final none = rgbaPng(
      width: 2,
      height: 2,
      pixels: pixels,
      filter: 0,
      compressionLevel: 1,
    );
    final sub = rgbaPng(
      width: 2,
      height: 2,
      pixels: pixels,
      filter: 1,
      compressionLevel: 9,
    );

    final noneInspection = inspector.inspect(none);
    final subInspection = inspector.inspect(sub);

    expect(noneInspection.width, 2);
    expect(noneInspection.height, 2);
    expect(noneInspection.pixelDigest, subInspection.pixelDigest);
    expect(Digest.bytes(none), isNot(Digest.bytes(sub)));
  });

  test('rejects invalid CRC and bytes after IEND', () {
    final valid = rgbaPng(
      width: 1,
      height: 1,
      pixels: const <int>[1, 2, 3, 255],
    );
    final corrupted = List<int>.of(valid);
    corrupted[corrupted.length - 5] ^= 1;

    expect(() => inspector.inspect(corrupted), throwsFormatException);
    expect(() => inspector.inspect(<int>[...valid, 0]), throwsFormatException);
  });

  test('rejects animation and dimensions outside the closed profile', () {
    final animated = rgbaPng(
      width: 1,
      height: 1,
      pixels: const <int>[1, 2, 3, 255],
      beforeImageData: <List<int>>[
        pngChunk('acTL', <int>[...uint32(1), ...uint32(0)]),
      ],
    );
    final oversized = rgbaPng(
      width: 8193,
      height: 1,
      pixels: List<int>.filled(8193 * 4, 0),
    );

    expect(() => inspector.inspect(animated), throwsFormatException);
    expect(() => inspector.inspect(oversized), throwsFormatException);
  });
}
