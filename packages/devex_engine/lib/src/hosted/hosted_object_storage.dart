import 'package:devex_contracts/devex_contracts.dart';

import 'hosted_collaboration_service.dart';

final class HostedObjectTransfer {
  HostedObjectTransfer({
    required this.method,
    required this.uri,
    required this.expiresAt,
    required this.descriptor,
    required Map<String, String> requiredHeaders,
  }) : requiredHeaders = Map<String, String>.unmodifiable(requiredHeaders) {
    if (method != 'GET' && method != 'PUT') {
      throw ArgumentError.value(method, 'method');
    }
    if (!expiresAt.isUtc) throw ArgumentError('expiresAt must be UTC');
  }

  final String method;
  final Uri uri;
  final DateTime expiresAt;
  final HostedBlobDescriptor descriptor;
  final Map<String, String> requiredHeaders;

  /// Transfer grants are deliberately ephemeral and must never enter CAS,
  /// releases, audit payloads, or canonical domain documents.
  Map<String, Object?> toEphemeralJson() => <String, Object?>{
    'method': method,
    'url': uri.toString(),
    'expiresAt': expiresAt.toIso8601String(),
    'descriptor': descriptor.toJson(),
    'requiredHeaders': requiredHeaders,
  };
}

abstract interface class HostedObjectStore {
  Future<HostedObjectTransfer> authorizeUpload(
    HostedRequestContext context, {
    required Digest digest,
    required int size,
    required String mediaType,
    required String classification,
    Duration ttl = const Duration(minutes: 5),
  });

  Future<HostedObjectTransfer> authorizeDownload(
    HostedRequestContext context,
    HostedBlobDescriptor descriptor, {
    Duration ttl = const Duration(minutes: 5),
  });
}
