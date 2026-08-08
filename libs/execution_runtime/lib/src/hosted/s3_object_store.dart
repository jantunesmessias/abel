import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

final class S3Credentials {
  const S3Credentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
}

final class S3ObjectStoreConfiguration {
  S3ObjectStoreConfiguration({
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.credentials,
    this.allowInsecureLoopback = false,
  }) {
    if (endpoint.userInfo.isNotEmpty || endpoint.query.isNotEmpty) {
      throw ArgumentError('S3 endpoint must not contain credentials or query');
    }
    final loopback =
        endpoint.host == 'localhost' ||
        endpoint.host == '127.0.0.1' ||
        endpoint.host == '::1';
    if (endpoint.scheme != 'https' && !(allowInsecureLoopback && loopback)) {
      throw ArgumentError('S3 endpoint must use verified HTTPS');
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{2,62}$').hasMatch(bucket)) {
      throw ArgumentError.value(bucket, 'bucket');
    }
    if (!RegExp(r'^[a-z0-9-]{3,32}$').hasMatch(region)) {
      throw ArgumentError.value(region, 'region');
    }
  }

  final Uri endpoint;
  final String bucket;
  final String region;
  final S3Credentials credentials;
  final bool allowInsecureLoopback;
}

final class S3CompatibleObjectStore implements HostedObjectStore {
  const S3CompatibleObjectStore({
    required this._configuration,
    required this._clock,
  });

  final S3ObjectStoreConfiguration _configuration;
  final Clock _clock;

  @override
  Future<HostedObjectTransfer> authorizeUpload(
    HostedRequestContext context, {
    required Digest digest,
    required int size,
    required String mediaType,
    required String classification,
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final descriptor = _descriptor(
      context,
      digest: digest,
      size: size,
      mediaType: mediaType,
      classification: classification,
    );
    return _authorize('PUT', descriptor, ttl);
  }

  @override
  Future<HostedObjectTransfer> authorizeDownload(
    HostedRequestContext context,
    HostedBlobDescriptor descriptor, {
    Duration ttl = const Duration(minutes: 5),
  }) async {
    if (descriptor.tenantId != context.tenantId) {
      throw const HostedAuthorizationException(
        'cross-tenant object download rejected',
      );
    }
    return _authorize('GET', descriptor, ttl);
  }

  HostedBlobDescriptor _descriptor(
    HostedRequestContext context, {
    required Digest digest,
    required int size,
    required String mediaType,
    required String classification,
  }) => HostedBlobDescriptor(
    tenantId: context.tenantId,
    digest: digest,
    size: size,
    mediaType: mediaType,
    classification: classification,
    objectKey:
        'tenants/${context.tenantId}/blobs/sha256/${digest.value.substring(7)}',
  );

  HostedObjectTransfer _authorize(
    String method,
    HostedBlobDescriptor descriptor,
    Duration ttl,
  ) {
    if (ttl < const Duration(seconds: 30) ||
        ttl > const Duration(minutes: 15)) {
      throw ArgumentError('object transfer TTL must be 30-900 seconds');
    }
    final now = _clock.nowUtc();
    final expiresAt = now.add(ttl);
    final uri = _presign(
      method: method,
      objectKey: descriptor.objectKey,
      now: now,
      expires: ttl.inSeconds,
    );
    return HostedObjectTransfer(
      method: method,
      uri: uri,
      expiresAt: expiresAt,
      descriptor: descriptor,
      requiredHeaders: const <String, String>{},
    );
  }

  Uri _presign({
    required String method,
    required String objectKey,
    required DateTime now,
    required int expires,
  }) {
    final timestamp = _timestamp(now);
    final day = timestamp.substring(0, 8);
    final scope = '$day/${_configuration.region}/s3/aws4_request';
    final endpointPath = _configuration.endpoint.path == '/'
        ? ''
        : _configuration.endpoint.path.replaceFirst(RegExp(r'/$'), '');
    final canonicalPath = _encodePath(
      '$endpointPath/${_configuration.bucket}/$objectKey',
    );
    final query = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '${_configuration.credentials.accessKeyId}/$scope',
      'X-Amz-Date': timestamp,
      'X-Amz-Expires': '$expires',
      'X-Amz-SignedHeaders': 'host',
      'X-Amz-Security-Token': ?_configuration.credentials.sessionToken,
    };
    final canonicalQuery = _canonicalQuery(query);
    final host = _configuration.endpoint.hasPort
        ? '${_configuration.endpoint.host}:${_configuration.endpoint.port}'
        : _configuration.endpoint.host;
    final canonicalRequest = <String>[
      method,
      canonicalPath,
      canonicalQuery,
      'host:$host\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');
    final stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      timestamp,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final dateKey = _hmac(
      utf8.encode('AWS4${_configuration.credentials.secretAccessKey}'),
      day,
    );
    final regionKey = _hmac(dateKey, _configuration.region);
    final serviceKey = _hmac(regionKey, 's3');
    final signingKey = _hmac(serviceKey, 'aws4_request');
    query['X-Amz-Signature'] = _hex(_hmac(signingKey, stringToSign));
    return _configuration.endpoint.replace(
      path: canonicalPath,
      query: _canonicalQuery(query),
    );
  }

  List<int> _hmac(List<int> key, String value) =>
      Hmac(sha256, key).convert(utf8.encode(value)).bytes;

  String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  String _timestamp(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => '$part'.padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}'
        '${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  String _encodePath(String value) => value
      .split('/')
      .map((segment) => Uri.encodeComponent(segment).replaceAll('%7E', '~'))
      .join('/');

  String _canonicalQuery(Map<String, String> values) {
    final entries =
        values.entries
            .map(
              (entry) => MapEntry<String, String>(
                Uri.encodeQueryComponent(entry.key),
                Uri.encodeQueryComponent(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final key = left.key.compareTo(right.key);
            return key == 0 ? left.value.compareTo(right.value) : key;
          });
    return entries.map((entry) => '${entry.key}=${entry.value}').join('&');
  }
}
