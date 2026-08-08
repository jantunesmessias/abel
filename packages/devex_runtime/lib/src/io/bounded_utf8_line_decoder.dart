import 'dart:async';
import 'dart:convert';

/// Incrementally frames UTF-8 lines without allowing an unbounded buffer.
///
/// The limit is measured in bytes before decoding, so malformed or fragmented
/// input cannot evade it. A final line without LF is accepted.
final class BoundedUtf8LineDecoder
    extends StreamTransformerBase<List<int>, String> {
  const BoundedUtf8LineDecoder({required this.maxLineBytes});

  final int maxLineBytes;

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    if (maxLineBytes <= 0) {
      throw ArgumentError.value(maxLineBytes, 'maxLineBytes');
    }
    final line = <int>[];
    await for (final chunk in stream) {
      for (final byte in chunk) {
        if (byte < 0 || byte > 255) {
          throw const FormatException('Input contains a non-byte value');
        }
        if (byte == 0x0a) {
          yield _decode(line);
          line.clear();
          continue;
        }
        if (line.length == maxLineBytes) {
          throw FormatException('Line exceeds $maxLineBytes bytes');
        }
        line.add(byte);
      }
    }
    if (line.isNotEmpty) yield _decode(line);
  }

  String _decode(List<int> source) {
    final end = source.isNotEmpty && source.last == 0x0d
        ? source.length - 1
        : source.length;
    return utf8.decode(source.sublist(0, end), allowMalformed: false);
  }
}
