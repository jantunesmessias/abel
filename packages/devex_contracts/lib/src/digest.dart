import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'canonical_json.dart';

final class Digest {
  factory Digest(String value) {
    if (!_pattern.hasMatch(value)) {
      throw FormatException('Expected sha256:<64 lowercase hex characters>');
    }
    return Digest._(value);
  }

  const Digest._(this.value);

  static final RegExp _pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

  final String value;

  static Digest semantic(Object? value) {
    final canonical = const JcsCanonicalizer().canonicalize(value);
    return bytes(utf8.encode(canonical));
  }

  static Digest bytes(List<int> value) {
    final hex = crypto.sha256.convert(value).toString();
    return Digest._('sha256:$hex');
  }

  @override
  bool operator ==(Object other) => other is Digest && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
