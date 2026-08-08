import 'dart:io';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';

final class PngCaptureInspection {
  const PngCaptureInspection({
    required this.width,
    required this.height,
    required this.pixelDigest,
    required this.rgbaBytes,
  });

  final int width;
  final int height;
  final Digest pixelDigest;
  final ImmutableBytes rgbaBytes;
}

/// Validates the closed PNG profile used for V0 screen captures.
///
/// The profile accepts non-interlaced, 8-bit RGB and RGBA images. Every chunk
/// CRC is checked before IDAT is decompressed. The pixel digest is calculated
/// over dimensions plus normalized RGBA8 pixels, so compression and filter
/// choices do not affect visual identity.
final class PngCaptureInspector {
  const PngCaptureInspector({
    this.maxBytes = 32 * 1024 * 1024,
    this.maxWidth = 8192,
    this.maxHeight = 8192,
    this.maxPixels = 16 * 1024 * 1024,
    this.maxChunks = 10000,
  });

  static const List<int> _signature = <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];

  final int maxBytes;
  final int maxWidth;
  final int maxHeight;
  final int maxPixels;
  final int maxChunks;

  PngCaptureInspection inspect(List<int> input) {
    if (input.length > maxBytes) {
      throw const FormatException('PNG exceeds the capture size budget');
    }
    if (input.length < _signature.length || !_matches(input, 0, _signature)) {
      throw const FormatException('Invalid PNG signature');
    }
    final bytes = input is Uint8List ? input : Uint8List.fromList(input);
    var offset = _signature.length;
    var chunks = 0;
    var width = 0;
    var height = 0;
    var bytesPerPixel = 0;
    var rowBytes = 0;
    var sawHeader = false;
    var sawImageData = false;
    var endedImageData = false;
    var sawEnd = false;
    final compressed = BytesBuilder(copy: false);

    while (offset < bytes.length) {
      chunks += 1;
      if (chunks > maxChunks) {
        throw const FormatException('PNG exceeds the chunk count budget');
      }
      if (bytes.length - offset < 12) {
        throw const FormatException('Truncated PNG chunk');
      }
      final length = _uint32(bytes, offset);
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      final chunkEnd = dataEnd + 4;
      if (dataEnd < dataStart || chunkEnd > bytes.length) {
        throw const FormatException('PNG chunk length exceeds the input');
      }
      final typeBytes = bytes.sublist(offset + 4, offset + 8);
      if (typeBytes.any(
        (value) =>
            !((value >= 65 && value <= 90) || (value >= 97 && value <= 122)),
      )) {
        throw const FormatException('Invalid PNG chunk type');
      }
      final type = String.fromCharCodes(typeBytes);
      final declaredCrc = _uint32(bytes, dataEnd);
      final calculatedCrc = _crc32(bytes, offset + 4, dataEnd);
      if (declaredCrc != calculatedCrc) {
        throw FormatException('PNG chunk $type has an invalid CRC');
      }
      if (!sawHeader && type != 'IHDR') {
        throw const FormatException('IHDR must be the first PNG chunk');
      }

      switch (type) {
        case 'IHDR':
          if (sawHeader || length != 13) {
            throw const FormatException('PNG must contain one 13-byte IHDR');
          }
          sawHeader = true;
          width = _uint32(bytes, dataStart);
          height = _uint32(bytes, dataStart + 4);
          final bitDepth = bytes[dataStart + 8];
          final colorType = bytes[dataStart + 9];
          final compression = bytes[dataStart + 10];
          final filter = bytes[dataStart + 11];
          final interlace = bytes[dataStart + 12];
          if (width <= 0 ||
              height <= 0 ||
              width > maxWidth ||
              height > maxHeight ||
              width * height > maxPixels) {
            throw const FormatException(
              'PNG dimensions exceed the capture budget',
            );
          }
          if (bitDepth != 8 || (colorType != 2 && colorType != 6)) {
            throw const FormatException(
              'Capture PNG must use 8-bit RGB or RGBA pixels',
            );
          }
          if (compression != 0 || filter != 0 || interlace != 0) {
            throw const FormatException(
              'Capture PNG must use standard compression/filtering without interlace',
            );
          }
          bytesPerPixel = colorType == 2 ? 3 : 4;
          rowBytes = width * bytesPerPixel;
        case 'IDAT':
          if (!sawHeader || sawEnd || endedImageData) {
            throw const FormatException('IDAT chunks must be consecutive');
          }
          sawImageData = true;
          compressed.add(bytes.sublist(dataStart, dataEnd));
        case 'IEND':
          if (!sawImageData || sawEnd || length != 0) {
            throw const FormatException('Invalid PNG IEND chunk');
          }
          sawEnd = true;
          if (chunkEnd != bytes.length) {
            throw const FormatException('PNG contains data after IEND');
          }
        case 'acTL' || 'fcTL' || 'fdAT':
          throw const FormatException('Animated PNG is not a capture master');
        default:
          if (sawImageData) endedImageData = true;
          final critical = (typeBytes.first & 0x20) == 0;
          if (critical) {
            throw FormatException('Unsupported critical PNG chunk $type');
          }
      }
      offset = chunkEnd;
    }
    if (!sawHeader || !sawImageData || !sawEnd) {
      throw const FormatException('PNG is missing required chunks');
    }

    final expectedDecodedLength = height * (rowBytes + 1);
    final List<int> decoded;
    try {
      decoded = ZLibCodec().decode(compressed.takeBytes());
    } on Object {
      throw const FormatException('PNG IDAT stream is invalid');
    }
    if (decoded.length != expectedDecodedLength) {
      throw const FormatException('PNG scanline size does not match IHDR');
    }
    final rgba = _normalizeRgba(
      decoded,
      width: width,
      height: height,
      bytesPerPixel: bytesPerPixel,
    );
    final identity = BytesBuilder(copy: false)
      ..add(_uint32Bytes(width))
      ..add(_uint32Bytes(height))
      ..add(rgba);
    return PngCaptureInspection(
      width: width,
      height: height,
      pixelDigest: Digest.bytes(identity.takeBytes()),
      rgbaBytes: ImmutableBytes.copyOf(rgba),
    );
  }

  Uint8List _normalizeRgba(
    List<int> encoded, {
    required int width,
    required int height,
    required int bytesPerPixel,
  }) {
    final rowBytes = width * bytesPerPixel;
    var inputOffset = 0;
    var outputOffset = 0;
    var previous = Uint8List(rowBytes);
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      final filter = encoded[inputOffset];
      inputOffset += 1;
      if (filter > 4) throw FormatException('Unsupported PNG filter $filter');
      final current = Uint8List(rowBytes);
      for (var x = 0; x < rowBytes; x += 1) {
        final raw = encoded[inputOffset + x];
        final left = x >= bytesPerPixel ? current[x - bytesPerPixel] : 0;
        final up = previous[x];
        final upperLeft = x >= bytesPerPixel ? previous[x - bytesPerPixel] : 0;
        final predictor = switch (filter) {
          0 => 0,
          1 => left,
          2 => up,
          3 => (left + up) ~/ 2,
          4 => _paeth(left, up, upperLeft),
          _ => throw StateError('filter validated above'),
        };
        current[x] = (raw + predictor) & 0xff;
      }
      inputOffset += rowBytes;
      for (var x = 0; x < width; x += 1) {
        final source = x * bytesPerPixel;
        rgba[outputOffset++] = current[source];
        rgba[outputOffset++] = current[source + 1];
        rgba[outputOffset++] = current[source + 2];
        rgba[outputOffset++] = bytesPerPixel == 4 ? current[source + 3] : 0xff;
      }
      previous = current;
    }
    return rgba;
  }

  int _paeth(int left, int up, int upperLeft) {
    final prediction = left + up - upperLeft;
    final leftDistance = (prediction - left).abs();
    final upDistance = (prediction - up).abs();
    final upperLeftDistance = (prediction - upperLeft).abs();
    if (leftDistance <= upDistance && leftDistance <= upperLeftDistance) {
      return left;
    }
    return upDistance <= upperLeftDistance ? up : upperLeft;
  }

  int _uint32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

  Uint8List _uint32Bytes(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value);
    return bytes;
  }

  bool _matches(List<int> bytes, int offset, List<int> expected) {
    for (var index = 0; index < expected.length; index += 1) {
      if (bytes[offset + index] != expected[index]) return false;
    }
    return true;
  }

  int _crc32(Uint8List bytes, int start, int end) {
    var crc = 0xffffffff;
    for (var index = start; index < end; index += 1) {
      crc = _crcTable[(crc ^ bytes[index]) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static final List<int> _crcTable = List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit += 1) {
      value = (value & 1) != 0 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    return value;
  }, growable: false);
}
