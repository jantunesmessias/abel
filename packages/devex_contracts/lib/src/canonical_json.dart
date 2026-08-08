/// Raised when a value cannot participate in the DevExKit I-JSON profile.
final class CanonicalJsonException implements Exception {
  const CanonicalJsonException(this.message, {this.path = r'$'});

  final String message;
  final String path;

  @override
  String toString() => 'CanonicalJsonException at $path: $message';
}

/// RFC 8785/JCS canonicalizer for the DevExKit I-JSON profile.
///
/// It accepts only JSON primitives, string-keyed maps and lists. Integers are
/// restricted to the interoperable IEEE-754 range and negative zero, non-finite
/// doubles, malformed UTF-16 and cyclic structures are rejected.
final class JcsCanonicalizer {
  const JcsCanonicalizer();

  static const int maxSafeInteger = 9007199254740991;

  String canonicalize(Object? value) {
    final output = StringBuffer();
    final ancestors = Set<Object>.identity();
    _write(value, output, ancestors, r'$');
    return output.toString();
  }

  void _write(
    Object? value,
    StringBuffer output,
    Set<Object> ancestors,
    String path,
  ) {
    switch (value) {
      case null:
        output.write('null');
      case final bool value:
        output.write(value ? 'true' : 'false');
      case final String value:
        _writeString(value, output, path);
      case final int value:
        if (value.abs() > maxSafeInteger) {
          throw CanonicalJsonException(
            'integer is outside the interoperable range',
            path: path,
          );
        }
        output.write(value);
      case final double value:
        output.write(_canonicalDouble(value, path));
      case final List<Object?> value:
        _withContainer(value, ancestors, path, () {
          output.write('[');
          for (var index = 0; index < value.length; index += 1) {
            if (index > 0) output.write(',');
            _write(value[index], output, ancestors, '$path[$index]');
          }
          output.write(']');
        });
      case final Map<Object?, Object?> value:
        _withContainer(value, ancestors, path, () {
          final entries = <MapEntry<String, Object?>>[];
          for (final entry in value.entries) {
            final key = entry.key;
            if (key is! String) {
              throw CanonicalJsonException(
                'object key is not a string',
                path: path,
              );
            }
            _validateUtf16(key, '$path.<key>');
            entries.add(MapEntry<String, Object?>(key, entry.value));
          }
          entries.sort((left, right) => _compareUtf16(left.key, right.key));

          output.write('{');
          for (var index = 0; index < entries.length; index += 1) {
            if (index > 0) output.write(',');
            final entry = entries[index];
            _writeString(entry.key, output, '$path.<key>');
            output.write(':');
            _write(
              entry.value,
              output,
              ancestors,
              '$path.${_pathSegment(entry.key)}',
            );
          }
          output.write('}');
        });
      default:
        throw CanonicalJsonException(
          'unsupported value type ${value.runtimeType}',
          path: path,
        );
    }
  }

  void _withContainer(
    Object container,
    Set<Object> ancestors,
    String path,
    void Function() body,
  ) {
    if (!ancestors.add(container)) {
      throw CanonicalJsonException('cyclic value', path: path);
    }
    try {
      body();
    } finally {
      ancestors.remove(container);
    }
  }

  void _writeString(String value, StringBuffer output, String path) {
    _validateUtf16(value, path);
    output.write('"');
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      switch (unit) {
        case 0x08:
          output.write(r'\b');
        case 0x09:
          output.write(r'\t');
        case 0x0a:
          output.write(r'\n');
        case 0x0c:
          output.write(r'\f');
        case 0x0d:
          output.write(r'\r');
        case 0x22:
          output.write(r'\"');
        case 0x5c:
          output.write(r'\\');
        default:
          if (unit <= 0x1f) {
            output
              ..write(r'\u')
              ..write(unit.toRadixString(16).padLeft(4, '0'));
          } else if (_isHighSurrogate(unit)) {
            output.writeCharCode(unit);
            index += 1;
            output.writeCharCode(value.codeUnitAt(index));
          } else {
            output.writeCharCode(unit);
          }
      }
    }
    output.write('"');
  }

  void _validateUtf16(String value, String path) {
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (_isHighSurrogate(unit)) {
        if (index + 1 >= value.length ||
            !_isLowSurrogate(value.codeUnitAt(index + 1))) {
          throw CanonicalJsonException('unpaired high surrogate', path: path);
        }
        index += 1;
      } else if (_isLowSurrogate(unit)) {
        throw CanonicalJsonException('unpaired low surrogate', path: path);
      }
    }
  }

  String _canonicalDouble(double value, String path) {
    if (!value.isFinite) {
      throw CanonicalJsonException('non-finite number', path: path);
    }
    if (value == 0 && value.isNegative) {
      throw CanonicalJsonException('negative zero', path: path);
    }

    final negative = value.isNegative;
    final raw = value.abs().toString().toLowerCase();
    final exponentIndex = raw.indexOf('e');
    final coefficient = exponentIndex < 0
        ? raw
        : raw.substring(0, exponentIndex);
    final sourceExponent = exponentIndex < 0
        ? 0
        : int.parse(raw.substring(exponentIndex + 1));
    final dotIndex = coefficient.indexOf('.');
    final integralDigits = dotIndex < 0 ? coefficient.length : dotIndex;
    var digits = coefficient.replaceAll('.', '');
    while (digits.length > 1 && digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    final decimalPosition = integralDigits + sourceExponent;
    final absolute = value.abs();
    final useDecimal = absolute == 0 || (absolute >= 1e-6 && absolute < 1e21);

    final rendered = useDecimal
        ? _renderDecimal(digits, decimalPosition)
        : _renderScientific(digits, decimalPosition - 1);
    return negative ? '-$rendered' : rendered;
  }

  String _renderDecimal(String digits, int decimalPosition) {
    if (decimalPosition <= 0) {
      return '0.${'0' * -decimalPosition}$digits';
    }
    if (decimalPosition >= digits.length) {
      return '$digits${'0' * (decimalPosition - digits.length)}';
    }
    return '${digits.substring(0, decimalPosition)}.'
        '${digits.substring(decimalPosition)}';
  }

  String _renderScientific(String digits, int exponent) {
    final coefficient = digits.length == 1
        ? digits
        : '${digits[0]}.${digits.substring(1)}';
    final sign = exponent >= 0 ? '+' : '';
    return '${coefficient}e$sign$exponent';
  }

  int _compareUtf16(String left, String right) {
    final length = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < length; index += 1) {
      final comparison = left
          .codeUnitAt(index)
          .compareTo(right.codeUnitAt(index));
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }

  bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

  bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  String _pathSegment(String key) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key) ? key : '[$key]';
}
