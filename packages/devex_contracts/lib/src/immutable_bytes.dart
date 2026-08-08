import 'dart:collection';
import 'dart:typed_data';

/// An owned immutable byte sequence that can cross trusted DevExKit layers
/// without being copied again.
final class ImmutableBytes extends ListBase<int> {
  factory ImmutableBytes.copyOf(List<int> source) {
    if (source is ImmutableBytes) return source;
    for (final byte in source) {
      if (byte < 0 || byte > 255) {
        throw const FormatException('Byte sequence contains a non-byte value');
      }
    }
    return ImmutableBytes._(Uint8List.fromList(source));
  }

  ImmutableBytes._(this._storage);

  final Uint8List _storage;

  @override
  int get length => _storage.length;

  @override
  set length(int value) => throw UnsupportedError('Immutable byte sequence');

  @override
  int operator [](int index) => _storage[index];

  @override
  void operator []=(int index, int value) {
    throw UnsupportedError('Immutable byte sequence');
  }
}
