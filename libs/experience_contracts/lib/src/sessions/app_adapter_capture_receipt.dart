import 'dart:convert';

import '../canonical_json.dart';
import '../digest.dart';
import '../immutable_bytes.dart';

/// Exact JCS provenance emitted after a Host-verified App Adapter PNG upload.
///
/// The document predates a `kind` discriminator, so Scenario Quality pairs it
/// with `ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt`.
final class AppAdapterCaptureReceipt {
  AppAdapterCaptureReceipt({
    required this.requestId,
    required this.sessionId,
    required this.artifactDigest,
    required this.pixelDigest,
    required this.size,
    required this.width,
    required this.height,
    required DateTime completedAt,
  }) : completedAt = completedAt.toUtc() {
    _receiptString(requestId, 'requestId');
    _receiptString(sessionId, 'sessionId');
    _receiptInteger(size, 'size', 32 * 1024 * 1024);
    _receiptInteger(width, 'width', 100000);
    _receiptInteger(height, 'height', 100000);
  }

  final String requestId;
  final String sessionId;
  final Digest artifactDigest;
  final Digest pixelDigest;
  final int size;
  final int width;
  final int height;
  final DateTime completedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'requestId': requestId,
    'sessionId': sessionId,
    'artifactDigest': artifactDigest.value,
    'pixelDigest': pixelDigest.value,
    'size': size,
    'width': width,
    'height': height,
    'mediaType': 'image/png',
    'completedAt': completedAt.toIso8601String(),
  };

  late final ImmutableBytes canonicalBytes = ImmutableBytes.copyOf(
    utf8.encode(const JcsCanonicalizer().canonicalize(toJson())),
  );

  late final Digest digest = Digest.bytes(canonicalBytes);

  factory AppAdapterCaptureReceipt.fromJson(
    Object? value, {
    required Digest expectedDigest,
  }) {
    if (value is! Map) {
      throw const FormatException('AppAdapterCaptureReceipt must be an object');
    }
    final json = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'AppAdapterCaptureReceipt keys must be strings',
        );
      }
      json[entry.key! as String] = entry.value;
    }
    const fields = <String>{
      'schemaVersion',
      'requestId',
      'sessionId',
      'artifactDigest',
      'pixelDigest',
      'size',
      'width',
      'height',
      'mediaType',
      'completedAt',
    };
    if (json.length != fields.length ||
        json.keys.any((key) => !fields.contains(key)) ||
        json['schemaVersion'] != 1 ||
        json['mediaType'] != 'image/png') {
      throw const FormatException('Invalid AppAdapterCaptureReceipt document');
    }
    String string(String key, {int maxLength = 512}) {
      final item = json[key];
      if (item is! String || item.isEmpty || item.length > maxLength) {
        throw FormatException('AppAdapterCaptureReceipt.$key is invalid');
      }
      return item;
    }

    int integer(String key, int maximum) {
      final item = json[key];
      if (item is! num ||
          !item.isFinite ||
          item != item.truncateToDouble() ||
          item < 1 ||
          item > maximum ||
          item.abs() > 9007199254740991) {
        throw FormatException('AppAdapterCaptureReceipt.$key is invalid');
      }
      return item.toInt();
    }

    final completedAtValue = string('completedAt');
    final completedAt = DateTime.tryParse(completedAtValue);
    if (completedAt == null ||
        !completedAtValue.endsWith('Z') ||
        completedAt.toUtc().toIso8601String() != completedAtValue) {
      throw const FormatException(
        'AppAdapterCaptureReceipt.completedAt is invalid',
      );
    }
    final receipt = AppAdapterCaptureReceipt(
      requestId: string('requestId', maxLength: 256),
      sessionId: string('sessionId', maxLength: 256),
      artifactDigest: Digest(string('artifactDigest')),
      pixelDigest: Digest(string('pixelDigest')),
      size: integer('size', 32 * 1024 * 1024),
      width: integer('width', 100000),
      height: integer('height', 100000),
      completedAt: completedAt,
    );
    if (receipt.digest != expectedDigest) {
      throw const FormatException('AppAdapterCaptureReceipt digest mismatch');
    }
    return receipt;
  }
}

void _receiptString(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value)) {
    throw ArgumentError.value(value, field);
  }
}

void _receiptInteger(int value, String field, int maximum) {
  if (value < 1 || value > maximum) {
    throw ArgumentError.value(value, field);
  }
}
