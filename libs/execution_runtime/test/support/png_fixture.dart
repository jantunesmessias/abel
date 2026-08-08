import 'dart:io';
import 'dart:typed_data';

List<int> rgbaPng({
  required int width,
  required int height,
  required List<int> pixels,
  int filter = 0,
  int compressionLevel = 6,
  List<List<int>> beforeImageData = const <List<int>>[],
}) {
  if (pixels.length != width * height * 4) {
    throw ArgumentError('pixels must contain width * height RGBA values');
  }
  final header = Uint8List(13);
  final headerData = ByteData.sublistView(header);
  headerData.setUint32(0, width);
  headerData.setUint32(4, height);
  header[8] = 8;
  header[9] = 6;
  final scanlines = BytesBuilder(copy: false);
  final rowBytes = width * 4;
  for (var row = 0; row < height; row += 1) {
    scanlines.addByte(filter);
    final start = row * rowBytes;
    for (var column = 0; column < rowBytes; column += 1) {
      final raw = pixels[start + column];
      final left = column >= 4 ? pixels[start + column - 4] : 0;
      scanlines.addByte(switch (filter) {
        0 => raw,
        1 => (raw - left) & 0xff,
        _ => throw ArgumentError.value(filter, 'filter'),
      });
    }
  }
  final compressed = ZLibCodec(
    level: compressionLevel,
  ).encode(scanlines.takeBytes());
  return <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ...pngChunk('IHDR', header),
    for (final chunk in beforeImageData) ...chunk,
    ...pngChunk('IDAT', compressed),
    ...pngChunk('IEND', const <int>[]),
  ];
}

List<int> pngChunk(String type, List<int> data) {
  final typed = type.codeUnits;
  final crcInput = <int>[...typed, ...data];
  return <int>[
    ...uint32(data.length),
    ...typed,
    ...data,
    ...uint32(pngCrc32(crcInput)),
  ];
}

List<int> uint32(int value) => <int>[
  (value >>> 24) & 0xff,
  (value >>> 16) & 0xff,
  (value >>> 8) & 0xff,
  value & 0xff,
];

int pngCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
