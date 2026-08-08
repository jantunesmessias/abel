import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
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
    final stored = rgbaPng(
      width: 2,
      height: 2,
      pixels: pixels,
      filter: 0,
      compressionLevel: 0,
    );
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

    final storedInspection = inspector.inspect(stored);
    final noneInspection = inspector.inspect(none);
    final subInspection = inspector.inspect(sub);

    expect(noneInspection.width, 2);
    expect(noneInspection.height, 2);
    expect(noneInspection.rgbaBytes, pixels);
    expect(
      noneInspection.pixelDigest,
      Digest.bytes(<int>[...uint32(2), ...uint32(2), ...pixels]),
    );
    expect(noneInspection.pixelDigest, storedInspection.pixelDigest);
    expect(noneInspection.pixelDigest, subInspection.pixelDigest);
    expect(Digest.bytes(none), isNot(Digest.bytes(sub)));
  });

  test('preserves the 8-bit RGB capture profile', () {
    final compressed = ZLibCodec().encode(const <int>[0, 1, 2, 3]);

    final inspection = inspector.inspect(
      _pngWithIdat(compressed, colorType: 2),
    );

    expect(inspection.rgbaBytes, const <int>[1, 2, 3, 255]);
  });

  test('rejects trailing decoded bytes and a compressed inflate bomb', () {
    final trailingScanline = ZLibCodec().encode(const <int>[
      0,
      1,
      2,
      3,
      255,
      0,
    ]);
    const bombDecodedLength = 1024 * 1024;
    final compressedBomb = ZLibCodec(
      level: 9,
    ).encode(List<int>.filled(bombDecodedLength, 0));
    expect(compressedBomb.length, lessThan(bombDecodedLength ~/ 100));

    final decodedOverflow = throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        'PNG scanline size does not match IHDR',
      ),
    );
    expect(
      () => inspector.inspect(_pngWithIdat(trailingScanline)),
      decodedOverflow,
    );
    expect(
      () => inspector.inspect(_pngWithIdat(compressedBomb)),
      decodedOverflow,
    );
  });

  test('rejects a truncated IDAT deflate body', () {
    final compressed = ZLibCodec().encode(const <int>[0, 1, 2, 3, 255]);
    final truncated = compressed.sublist(0, 2);

    expect(
      () => inspector.inspect(_pngWithIdat(truncated)),
      throwsFormatException,
    );
  });

  test('rejects missing or corrupt zlib trailers', () {
    final compressed = ZLibCodec().encode(const <int>[0, 1, 2, 3, 255]);
    for (var removedBytes = 1; removedBytes <= 4; removedBytes += 1) {
      expect(
        () => inspector.inspect(
          _pngWithIdat(compressed.sublist(0, compressed.length - removedBytes)),
        ),
        throwsFormatException,
        reason: 'removed $removedBytes trailer byte(s)',
      );
    }
    final corruptTrailer = List<int>.of(compressed)..last ^= 1;
    expect(
      () => inspector.inspect(_pngWithIdat(corruptTrailer)),
      throwsFormatException,
    );
  });

  test('rejects residual and concatenated zlib streams', () {
    final compressed = ZLibCodec().encode(const <int>[0, 1, 2, 3, 255]);
    final adler = compressed.sublist(compressed.length - 4);

    expect(
      () => inspector.inspect(_pngWithIdat(<int>[...compressed, ...adler])),
      throwsFormatException,
    );
    expect(
      () =>
          inspector.inspect(_pngWithIdat(<int>[...compressed, ...compressed])),
      throwsFormatException,
    );
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

List<int> _pngWithIdat(List<int> compressed, {int colorType = 6}) => <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  ...pngChunk('IHDR', <int>[...uint32(1), ...uint32(1), 8, colorType, 0, 0, 0]),
  ...pngChunk('IDAT', compressed),
  ...pngChunk('IEND', const <int>[]),
];
