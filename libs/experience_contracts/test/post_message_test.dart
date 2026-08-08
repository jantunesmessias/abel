import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  final message = <String, Object?>{
    'protocolVersion': 1,
    'sessionId': 'session-1',
    'nonce': 'nonce-1',
    'sequence': 2,
    'payload': <String, Object?>{'method': 'ready'},
  };

  test('authorizes exact origin, source, nonce and monotonic sequence', () {
    final envelope = PostMessageEnvelope.decodeAndAuthorize(
      message,
      eventOrigin: Uri.parse('http://127.0.0.1:8181'),
      expectedOrigin: Uri.parse('http://127.0.0.1:8181'),
      sourceMatches: true,
      expectedSessionId: 'session-1',
      expectedNonce: 'nonce-1',
      minimumSequence: 1,
    );

    expect(envelope.sequence, 2);
  });

  test('rejects wildcard-like origin and replay', () {
    expect(
      () => PostMessageEnvelope.decodeAndAuthorize(
        message,
        eventOrigin: Uri.parse('http://attacker.test'),
        expectedOrigin: Uri.parse('http://127.0.0.1:8181'),
        sourceMatches: true,
        expectedSessionId: 'session-1',
        expectedNonce: 'nonce-1',
        minimumSequence: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => PostMessageEnvelope.decodeAndAuthorize(
        message,
        eventOrigin: Uri.parse('http://127.0.0.1:8181'),
        expectedOrigin: Uri.parse('http://127.0.0.1:8181'),
        sourceMatches: true,
        expectedSessionId: 'session-1',
        expectedNonce: 'nonce-1',
        minimumSequence: 2,
      ),
      throwsFormatException,
    );
  });
}
