import 'dart:typed_data';

import 'remote_execution_contracts.dart';

enum RemoteSessionRole { viewer }

enum RemoteStreamChannel { videoH264, control, screenshotPng, metadataJson }

const int _maximumPortableUint = 0x1FFFFFFFFFFFFF;
const int _uint32Radix = 0x100000000;

void _writePortableUint(ByteData target, int offset, int value) {
  if (value < 0 || value > _maximumPortableUint) {
    throw RangeError.range(value, 0, _maximumPortableUint, 'value');
  }
  final high = value ~/ _uint32Radix;
  final low = value - high * _uint32Radix;
  target
    ..setUint32(offset, high, Endian.big)
    ..setUint32(offset + 4, low, Endian.big);
}

int? _readPortableUint(ByteData source, int offset) {
  final high = source.getUint32(offset, Endian.big);
  if (high > 0x1FFFFF) return null;
  return high * _uint32Radix + source.getUint32(offset + 4, Endian.big);
}

final class RemoteSessionTicket {
  RemoteSessionTicket({
    required this.tenantId,
    required this.runId,
    required this.principalId,
    required this.role,
    required Set<RemoteInteractiveTransport> allowedTransports,
    required this.issuedAt,
    required this.expiresAt,
    required this.nonce,
  }) : allowedTransports = Set<RemoteInteractiveTransport>.unmodifiable(
         allowedTransports,
       ) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('runId', runId),
      MapEntry<String, String>('principalId', principalId),
      MapEntry<String, String>('nonce', nonce),
    ]) {
      _sessionId(entry.value, 'RemoteSessionTicket.${entry.key}');
    }
    if (this.allowedTransports.isEmpty ||
        this.allowedTransports.contains(RemoteInteractiveTransport.none)) {
      throw const FormatException(
        'RemoteSessionTicket.allowedTransports is invalid',
      );
    }
    _sessionUtc(issuedAt, 'RemoteSessionTicket.issuedAt');
    _sessionUtc(expiresAt, 'RemoteSessionTicket.expiresAt');
    if (!expiresAt.isAfter(issuedAt) ||
        expiresAt.difference(issuedAt) > const Duration(minutes: 2)) {
      throw const FormatException('RemoteSessionTicket lifetime is invalid');
    }
  }

  final String tenantId;
  final String runId;
  final String principalId;
  final RemoteSessionRole role;
  final Set<RemoteInteractiveTransport> allowedTransports;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String nonce;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteSessionTicket',
    'tenantId': tenantId,
    'runId': runId,
    'principalId': principalId,
    'role': role.name,
    'allowedTransports': allowedTransports.map((value) => value.name).toList()
      ..sort(),
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'nonce': nonce,
  };

  factory RemoteSessionTicket.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('RemoteSessionTicket must be an object');
    }
    final unknown = value.keys.toSet().difference(const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'runId',
      'principalId',
      'role',
      'allowedTransports',
      'issuedAt',
      'expiresAt',
      'nonce',
    });
    if (unknown.isNotEmpty ||
        value['schemaVersion'] != 1 ||
        value['kind'] != 'RemoteSessionTicket') {
      throw const FormatException('RemoteSessionTicket header is invalid');
    }
    final rawTransports = value['allowedTransports'];
    if (rawTransports is! List<Object?> || rawTransports.isEmpty) {
      throw const FormatException(
        'RemoteSessionTicket.allowedTransports is invalid',
      );
    }
    final transports = <RemoteInteractiveTransport>{};
    for (final raw in rawTransports) {
      if (raw is! String) {
        throw const FormatException(
          'RemoteSessionTicket.allowedTransports is invalid',
        );
      }
      transports.add(
        RemoteInteractiveTransport.values.singleWhere(
          (value) => value.name == raw,
          orElse: () => throw const FormatException(
            'RemoteSessionTicket.allowedTransports is invalid',
          ),
        ),
      );
    }
    if (transports.length != rawTransports.length) {
      throw const FormatException(
        'RemoteSessionTicket.allowedTransports contains duplicates',
      );
    }
    return RemoteSessionTicket(
      tenantId: _sessionString(value, 'tenantId'),
      runId: _sessionString(value, 'runId'),
      principalId: _sessionString(value, 'principalId'),
      role: RemoteSessionRole.values.singleWhere(
        (role) => role.name == _sessionString(value, 'role'),
        orElse: () =>
            throw const FormatException('RemoteSessionTicket.role is invalid'),
      ),
      allowedTransports: transports,
      issuedAt: _sessionDate(value, 'issuedAt'),
      expiresAt: _sessionDate(value, 'expiresAt'),
      nonce: _sessionString(value, 'nonce'),
    );
  }
}

final class RemoteSessionGrant {
  RemoteSessionGrant({
    required this.runId,
    required this.endpoint,
    required this.compactTicket,
    required Set<RemoteInteractiveTransport> allowedTransports,
    required this.expiresAt,
  }) : allowedTransports = Set<RemoteInteractiveTransport>.unmodifiable(
         allowedTransports,
       ) {
    _sessionId(runId, 'RemoteSessionGrant.runId');
    if (endpoint.scheme != 'wss' ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw const FormatException('RemoteSessionGrant.endpoint is invalid');
    }
    if (compactTicket.isEmpty || compactTicket.length > 16384) {
      throw const FormatException(
        'RemoteSessionGrant.compactTicket is invalid',
      );
    }
    if (this.allowedTransports.isEmpty ||
        this.allowedTransports.contains(RemoteInteractiveTransport.none)) {
      throw const FormatException(
        'RemoteSessionGrant.allowedTransports is invalid',
      );
    }
    _sessionUtc(expiresAt, 'RemoteSessionGrant.expiresAt');
  }

  static const String protocol = 'workspace.remote.session.v1';

  final String runId;
  final Uri endpoint;
  final String compactTicket;
  final Set<RemoteInteractiveTransport> allowedTransports;
  final DateTime expiresAt;

  Map<String, Object?> toEphemeralJson() => <String, Object?>{
    'runId': runId,
    'endpoint': endpoint.toString(),
    'ticket': compactTicket,
    'protocol': protocol,
    'allowedTransports': allowedTransports.map((value) => value.name).toList()
      ..sort(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory RemoteSessionGrant.fromEphemeralJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value.keys.toSet().difference(const <String>{
          'runId',
          'endpoint',
          'ticket',
          'protocol',
          'allowedTransports',
          'expiresAt',
        }).isNotEmpty ||
        value['protocol'] != protocol) {
      throw const FormatException('RemoteSessionGrant is invalid');
    }
    final rawTransports = value['allowedTransports'];
    if (rawTransports is! List<Object?> || rawTransports.isEmpty) {
      throw const FormatException(
        'RemoteSessionGrant.allowedTransports is invalid',
      );
    }
    final transports = <RemoteInteractiveTransport>{};
    for (final raw in rawTransports) {
      if (raw is! String) {
        throw const FormatException(
          'RemoteSessionGrant.allowedTransports is invalid',
        );
      }
      transports.add(
        RemoteInteractiveTransport.values.singleWhere(
          (value) => value.name == raw,
          orElse: () => throw const FormatException(
            'RemoteSessionGrant.allowedTransports is invalid',
          ),
        ),
      );
    }
    if (transports.length != rawTransports.length) {
      throw const FormatException(
        'RemoteSessionGrant.allowedTransports contains duplicates',
      );
    }
    final endpoint = Uri.tryParse('${value['endpoint']}');
    final expiresAt = DateTime.tryParse('${value['expiresAt']}');
    if (endpoint == null || expiresAt == null || !expiresAt.isUtc) {
      throw const FormatException('RemoteSessionGrant is invalid');
    }
    return RemoteSessionGrant(
      runId: _sessionString(value, 'runId'),
      endpoint: endpoint,
      compactTicket: _sessionString(value, 'ticket'),
      allowedTransports: transports,
      expiresAt: expiresAt,
    );
  }
}

final class RemoteStreamFrame {
  RemoteStreamFrame({
    required this.channel,
    required this.sequence,
    required List<int> payload,
  }) : payload = Uint8List.fromList(payload) {
    if (sequence < 1 || sequence > _maximumPortableUint) {
      throw const FormatException('RemoteStreamFrame.sequence is invalid');
    }
    final maximum = RemoteStreamFrameCodec.maximumPayload(channel);
    if (this.payload.isEmpty || this.payload.length > maximum) {
      throw const FormatException('RemoteStreamFrame.payload is invalid');
    }
  }

  final RemoteStreamChannel channel;
  final int sequence;
  final Uint8List payload;
}

final class RemoteStreamProtocolException implements Exception {
  const RemoteStreamProtocolException(this.message);

  final String message;

  @override
  String toString() => 'RemoteStreamProtocolException: $message';
}

final class RemoteH264Packet {
  RemoteH264Packet({
    required this.configuration,
    required this.keyFrame,
    required this.timestampMicros,
    required List<int> data,
  }) : data = Uint8List.fromList(data) {
    if (configuration && keyFrame ||
        configuration != (timestampMicros == null) ||
        timestampMicros != null &&
            (timestampMicros! < 0 || timestampMicros! > _maximumPortableUint) ||
        this.data.isEmpty ||
        this.data.length > RemoteH264PacketCodec.maximumDataBytes) {
      throw const FormatException('RemoteH264Packet is invalid');
    }
  }

  final bool configuration;
  final bool keyFrame;
  final int? timestampMicros;
  final Uint8List data;
}

abstract final class RemoteH264PacketCodec {
  static const int headerBytes = 20;
  static const int _magic = 0x48323634;
  static const int maximumDataBytes = 4 * 1024 * 1024 - headerBytes;

  static Uint8List encode(RemoteH264Packet packet) {
    final output = Uint8List(headerBytes + packet.data.length);
    final flags =
        (packet.configuration ? 1 : 0) |
        (packet.keyFrame ? 2 : 0) |
        (packet.timestampMicros != null ? 4 : 0);
    final header = ByteData.sublistView(output, 0, headerBytes)
      ..setUint32(0, _magic, Endian.big)
      ..setUint8(4, flags)
      ..setUint8(5, 0)
      ..setUint16(6, 0, Endian.big)
      ..setUint32(16, packet.data.length, Endian.big);
    _writePortableUint(header, 8, packet.timestampMicros ?? 0);
    output.setRange(headerBytes, output.length, packet.data);
    return output;
  }

  static RemoteH264Packet decode(List<int> bytes) {
    if (bytes.length < headerBytes) {
      throw const RemoteStreamProtocolException('H.264 packet is truncated');
    }
    final input = Uint8List.fromList(bytes);
    final header = ByteData.sublistView(input, 0, headerBytes);
    final flags = header.getUint8(4);
    final length = header.getUint32(16, Endian.big);
    if (header.getUint32(0, Endian.big) != _magic ||
        flags & ~7 != 0 ||
        header.getUint8(5) != 0 ||
        header.getUint16(6, Endian.big) != 0 ||
        length < 1 ||
        length > maximumDataBytes ||
        bytes.length != headerBytes + length) {
      throw const RemoteStreamProtocolException('H.264 packet is invalid');
    }
    final configuration = flags & 1 != 0;
    final keyFrame = flags & 2 != 0;
    final hasTimestamp = flags & 4 != 0;
    if (configuration == hasTimestamp || configuration && keyFrame) {
      throw const RemoteStreamProtocolException(
        'H.264 packet flags are invalid',
      );
    }
    final timestamp = _readPortableUint(header, 8);
    if (timestamp == null || !hasTimestamp && timestamp != 0) {
      throw const RemoteStreamProtocolException(
        'H.264 packet timestamp is invalid',
      );
    }
    return RemoteH264Packet(
      configuration: configuration,
      keyFrame: keyFrame,
      timestampMicros: hasTimestamp ? timestamp : null,
      data: input.sublist(headerBytes),
    );
  }
}

abstract final class RemoteStreamFrameCodec {
  static const int headerBytes = 20;
  static const int _magic = 0x44565831;

  static int maximumPayload(RemoteStreamChannel channel) => switch (channel) {
    RemoteStreamChannel.videoH264 => 4 * 1024 * 1024,
    RemoteStreamChannel.control => 64 * 1024,
    RemoteStreamChannel.screenshotPng => 16 * 1024 * 1024,
    RemoteStreamChannel.metadataJson => 64 * 1024,
  };

  static Uint8List encode(RemoteStreamFrame frame) {
    final output = Uint8List(headerBytes + frame.payload.length);
    final header = ByteData.sublistView(output, 0, headerBytes)
      ..setUint32(0, _magic, Endian.big)
      ..setUint8(4, frame.channel.index + 1)
      ..setUint8(5, 0)
      ..setUint16(6, 0, Endian.big)
      ..setUint32(16, frame.payload.length, Endian.big);
    _writePortableUint(header, 8, frame.sequence);
    output.setRange(headerBytes, output.length, frame.payload);
    return output;
  }

  static RemoteStreamFrame decode(List<int> bytes) {
    if (bytes.length < headerBytes) {
      throw const RemoteStreamProtocolException('remote frame is truncated');
    }
    final input = Uint8List.fromList(bytes);
    final header = ByteData.sublistView(input, 0, headerBytes);
    if (header.getUint32(0, Endian.big) != _magic ||
        header.getUint8(5) != 0 ||
        header.getUint16(6, Endian.big) != 0) {
      throw const RemoteStreamProtocolException(
        'remote frame header is invalid',
      );
    }
    final wireChannel = header.getUint8(4);
    if (wireChannel < 1 || wireChannel > RemoteStreamChannel.values.length) {
      throw const RemoteStreamProtocolException(
        'remote frame channel is invalid',
      );
    }
    final channel = RemoteStreamChannel.values[wireChannel - 1];
    final sequence = _readPortableUint(header, 8);
    final length = header.getUint32(16, Endian.big);
    if (sequence == null ||
        sequence < 1 ||
        length < 1 ||
        length > maximumPayload(channel) ||
        bytes.length != headerBytes + length) {
      throw const RemoteStreamProtocolException(
        'remote frame bounds are invalid',
      );
    }
    return RemoteStreamFrame(
      channel: channel,
      sequence: sequence,
      payload: input.sublist(headerBytes),
    );
  }
}

String _sessionString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('RemoteSessionTicket.$key is invalid');
  }
  return value;
}

DateTime _sessionDate(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_sessionString(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('RemoteSessionTicket.$key is invalid');
  }
  return value;
}

void _sessionId(String value, String path) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$').hasMatch(value)) {
    throw FormatException('$path is invalid');
  }
}

void _sessionUtc(DateTime value, String path) {
  if (!value.isUtc) throw ArgumentError('$path must be UTC');
}
