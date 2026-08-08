import 'dart:convert';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';

enum RemoteViewerConnectionState { connecting, authenticated, ready, closed }

sealed class RemoteViewerEvent {
  const RemoteViewerEvent();
}

final class RemoteViewerAuthenticated extends RemoteViewerEvent {
  const RemoteViewerAuthenticated();
}

final class RemoteViewerReady extends RemoteViewerEvent {
  const RemoteViewerReady();
}

final class RemoteWebBootstrapRequired extends RemoteViewerEvent {
  const RemoteWebBootstrapRequired({
    required this.endpoint,
    required this.grant,
    required this.expiresAt,
  });

  final String endpoint;
  final String grant;
  final DateTime expiresAt;
}

final class RemoteWebTargetReady extends RemoteViewerEvent {
  const RemoteWebTargetReady();
}

final class RemoteVideoSessionChanged extends RemoteViewerEvent {
  const RemoteVideoSessionChanged({
    required this.width,
    required this.height,
    required this.clientResized,
  });

  final int width;
  final int height;
  final bool clientResized;
}

final class RemoteH264PacketReceived extends RemoteViewerEvent {
  const RemoteH264PacketReceived(this.packet);

  final RemoteH264Packet packet;
}

final class RemoteScreenshotReceived extends RemoteViewerEvent {
  const RemoteScreenshotReceived(this.png);

  final Uint8List png;
}

final class RemoteSessionMessageMachine {
  RemoteSessionMessageMachine(this.grant) {
    if (grant.allowedTransports.length != 1 ||
        grant.allowedTransports.contains(RemoteInteractiveTransport.none)) {
      throw ArgumentError('remote viewer grant must select one transport');
    }
  }

  final RemoteSessionGrant grant;
  RemoteViewerConnectionState state = RemoteViewerConnectionState.connecting;
  int _lastBinarySequence = 0;

  List<RemoteViewerEvent> handle(Object? message) {
    if (state == RemoteViewerConnectionState.closed) {
      throw StateError('remote viewer session is closed');
    }
    if (message is String) return _text(message);
    if (message is List<int>) return _binary(message);
    throw const FormatException('remote viewer message type is invalid');
  }

  void close() => state = RemoteViewerConnectionState.closed;

  List<RemoteViewerEvent> _text(String message) {
    if (message.length > 65536) {
      throw const FormatException('remote viewer metadata is oversized');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      throw const FormatException('remote viewer metadata is invalid');
    }
    if (decoded is! Map<String, Object?> || decoded['type'] is! String) {
      throw const FormatException('remote viewer metadata is invalid');
    }
    return switch (decoded['type']) {
      'authenticated' => _authenticated(decoded),
      'session.ready' => _ready(decoded),
      'web.bootstrap.required' => _bootstrap(decoded),
      _ => throw const FormatException(
        'remote viewer metadata type is unsupported',
      ),
    };
  }

  List<RemoteViewerEvent> _authenticated(Map<String, Object?> json) {
    _exact(json, const <String>{'type', 'role', 'runId', 'sessionDeadline'});
    final deadline = DateTime.tryParse('${json['sessionDeadline']}');
    if (state != RemoteViewerConnectionState.connecting ||
        json['role'] != 'viewer' ||
        json['runId'] != grant.runId ||
        deadline == null ||
        !deadline.isUtc ||
        deadline.isBefore(grant.expiresAt)) {
      throw const FormatException('remote viewer authentication differs');
    }
    state = RemoteViewerConnectionState.authenticated;
    return const <RemoteViewerEvent>[RemoteViewerAuthenticated()];
  }

  List<RemoteViewerEvent> _ready(Map<String, Object?> json) {
    _exact(json, const <String>{'type', 'runId'});
    if (state != RemoteViewerConnectionState.authenticated ||
        json['runId'] != grant.runId) {
      throw const FormatException('remote viewer readiness is invalid');
    }
    state = RemoteViewerConnectionState.ready;
    return const <RemoteViewerEvent>[RemoteViewerReady()];
  }

  List<RemoteViewerEvent> _bootstrap(Map<String, Object?> json) {
    _exact(json, const <String>{'type', 'endpoint', 'grant', 'expiresAt'});
    final endpoint = json['endpoint'];
    final bootstrapGrant = json['grant'];
    final expiresAt = DateTime.tryParse('${json['expiresAt']}');
    final expected = '/v1/sessions/${grant.runId}/web/bootstrap';
    if (state != RemoteViewerConnectionState.ready ||
        !grant.allowedTransports.contains(
          RemoteInteractiveTransport.webDirect,
        ) ||
        endpoint != expected ||
        bootstrapGrant is! String ||
        bootstrapGrant.length < 16 ||
        bootstrapGrant.length > 256 ||
        expiresAt == null ||
        !expiresAt.isUtc ||
        expiresAt.isBefore(grant.expiresAt)) {
      throw const FormatException('remote web bootstrap is invalid');
    }
    return <RemoteViewerEvent>[
      RemoteWebBootstrapRequired(
        endpoint: endpoint as String,
        grant: bootstrapGrant,
        expiresAt: expiresAt,
      ),
    ];
  }

  List<RemoteViewerEvent> _binary(List<int> bytes) {
    if (state != RemoteViewerConnectionState.ready) {
      throw const FormatException('remote viewer received an early frame');
    }
    final frame = RemoteStreamFrameCodec.decode(bytes);
    if (frame.sequence != _lastBinarySequence + 1) {
      throw const FormatException('remote viewer frame sequence is invalid');
    }
    _lastBinarySequence = frame.sequence;
    return switch (frame.channel) {
      RemoteStreamChannel.videoH264 => _video(frame.payload),
      RemoteStreamChannel.screenshotPng => _screenshot(frame.payload),
      RemoteStreamChannel.metadataJson => _metadata(frame.payload),
      RemoteStreamChannel.control => throw const FormatException(
        'remote viewer cannot receive a control frame',
      ),
    };
  }

  List<RemoteViewerEvent> _video(List<int> payload) {
    if (!grant.allowedTransports.contains(
      RemoteInteractiveTransport.scrcpyH264Control,
    )) {
      throw const FormatException('H.264 is not granted for this viewer');
    }
    return <RemoteViewerEvent>[
      RemoteH264PacketReceived(RemoteH264PacketCodec.decode(payload)),
    ];
  }

  List<RemoteViewerEvent> _screenshot(List<int> payload) {
    if (!grant.allowedTransports.contains(
          RemoteInteractiveTransport.periodicScreenshotReadOnly,
        ) ||
        payload.length < 24 ||
        payload.length > 16 * 1024 * 1024) {
      throw const FormatException('remote screenshot is invalid');
    }
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (var index = 0; index < signature.length; index += 1) {
      if (payload[index] != signature[index]) {
        throw const FormatException('remote screenshot is not PNG');
      }
    }
    return <RemoteViewerEvent>[
      RemoteScreenshotReceived(Uint8List.fromList(payload)),
    ];
  }

  List<RemoteViewerEvent> _metadata(List<int> payload) {
    if (payload.length > 64 * 1024) {
      throw const FormatException('remote video metadata is oversized');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      throw const FormatException('remote video metadata is invalid');
    }
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException('remote video metadata is invalid');
    }
    if (decoded['type'] == 'web.direct.ready') {
      _exact(decoded, const <String>{'schemaVersion', 'type'});
      if (!grant.allowedTransports.contains(
        RemoteInteractiveTransport.webDirect,
      )) {
        throw const FormatException('web direct is not granted');
      }
      return const <RemoteViewerEvent>[RemoteWebTargetReady()];
    }
    if (decoded['type'] != 'video.session') {
      throw const FormatException('remote video metadata type is unsupported');
    }
    _exact(decoded, const <String>{
      'schemaVersion',
      'type',
      'codec',
      'width',
      'height',
      'clientResized',
    });
    final width = decoded['width'];
    final height = decoded['height'];
    if (!grant.allowedTransports.contains(
          RemoteInteractiveTransport.scrcpyH264Control,
        ) ||
        decoded['codec'] != 'avc1' ||
        width is! int ||
        width < 1 ||
        width > 16384 ||
        height is! int ||
        height < 1 ||
        height > 16384 ||
        decoded['clientResized'] is! bool) {
      throw const FormatException('remote video session is invalid');
    }
    return <RemoteViewerEvent>[
      RemoteVideoSessionChanged(
        width: width,
        height: height,
        clientResized: decoded['clientResized']! as bool,
      ),
    ];
  }

  void _exact(Map<String, Object?> json, Set<String> allowed) {
    if (json.keys.toSet().difference(allowed).isNotEmpty) {
      throw const FormatException('remote viewer metadata has unknown fields');
    }
  }
}
