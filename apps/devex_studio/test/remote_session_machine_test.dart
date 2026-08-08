import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/remote/remote_session_machine.dart';
import 'package:test/test.dart';

void main() {
  test('viewer machine authenticates and decodes timed H.264 in order', () {
    final machine = RemoteSessionMessageMachine(
      _grant(RemoteInteractiveTransport.scrcpyH264Control),
    );
    expect(
      machine
          .handle(
            jsonEncode(const <String, Object?>{
              'type': 'authenticated',
              'role': 'viewer',
              'runId': 'run-001',
              'sessionDeadline': '2026-08-09T12:05:00.000Z',
            }),
          )
          .single,
      isA<RemoteViewerAuthenticated>(),
    );
    expect(
      machine.handle('{"type":"session.ready","runId":"run-001"}').single,
      isA<RemoteViewerReady>(),
    );
    final metadata = machine.handle(
      RemoteStreamFrameCodec.encode(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.metadataJson,
          sequence: 1,
          payload: utf8.encode(
            '{"schemaVersion":1,"type":"video.session","codec":"avc1",'
            '"width":1080,"height":1920,"clientResized":false}',
          ),
        ),
      ),
    );
    expect(
      metadata.single,
      isA<RemoteVideoSessionChanged>()
          .having((event) => event.width, 'width', 1080)
          .having((event) => event.height, 'height', 1920),
    );
    final packet = RemoteH264Packet(
      configuration: false,
      keyFrame: true,
      timestampMicros: 123456,
      data: const <int>[0, 0, 0, 1, 0x65],
    );
    final video = machine.handle(
      RemoteStreamFrameCodec.encode(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.videoH264,
          sequence: 2,
          payload: RemoteH264PacketCodec.encode(packet),
        ),
      ),
    );
    expect(
      (video.single as RemoteH264PacketReceived).packet.timestampMicros,
      123456,
    );
    expect(
      () => machine.handle(
        RemoteStreamFrameCodec.encode(
          RemoteStreamFrame(
            channel: RemoteStreamChannel.videoH264,
            sequence: 2,
            payload: RemoteH264PacketCodec.encode(packet),
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'web bootstrap is exact and credentials never enter the endpoint URL',
    () {
      final grant = _grant(RemoteInteractiveTransport.webDirect);
      final machine = RemoteSessionMessageMachine(grant);
      machine.handle(
        '{"type":"authenticated","role":"viewer","runId":"run-001",'
        '"sessionDeadline":"2026-08-09T12:05:00.000Z"}',
      );
      machine.handle('{"type":"session.ready","runId":"run-001"}');
      final event =
          machine
                  .handle(
                    '{"type":"web.bootstrap.required",'
                    '"endpoint":"/v1/sessions/run-001/web/bootstrap",'
                    '"grant":"one-time-bootstrap-secret-001",'
                    '"expiresAt":"2026-08-09T12:05:00.000Z"}',
                  )
                  .single
              as RemoteWebBootstrapRequired;
      expect(event.endpoint, isNot(contains(event.grant)));
      expect(grant.endpoint.query, isEmpty);
      expect(grant.endpoint.userInfo, isEmpty);
      expect(
        () => machine.handle(
          '{"type":"web.bootstrap.required",'
          '"endpoint":"https://attacker.test/bootstrap",'
          '"grant":"one-time-bootstrap-secret-002",'
          '"expiresAt":"2026-08-09T12:05:00.000Z"}',
        ),
        throwsFormatException,
      );
    },
  );

  test('read-only screenshot capability rejects control and non-PNG data', () {
    final machine = RemoteSessionMessageMachine(
      _grant(RemoteInteractiveTransport.periodicScreenshotReadOnly),
    );
    machine.handle(
      '{"type":"authenticated","role":"viewer","runId":"run-001",'
      '"sessionDeadline":"2026-08-09T12:05:00.000Z"}',
    );
    machine.handle('{"type":"session.ready","runId":"run-001"}');
    expect(
      () => machine.handle(
        RemoteStreamFrameCodec.encode(
          RemoteStreamFrame(
            channel: RemoteStreamChannel.screenshotPng,
            sequence: 1,
            payload: List<int>.filled(24, 0),
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}

RemoteSessionGrant _grant(RemoteInteractiveTransport transport) =>
    RemoteSessionGrant(
      runId: 'run-001',
      endpoint: Uri.parse(
        'wss://gateway.example.test/v1/sessions/run-001/viewer',
      ),
      compactTicket: 'signed-viewer-ticket',
      allowedTransports: <RemoteInteractiveTransport>{transport},
      expiresAt: DateTime.utc(2026, 8, 9, 12, 1),
    );
