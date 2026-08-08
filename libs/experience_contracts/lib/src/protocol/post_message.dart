final class PostMessageEnvelope {
  const PostMessageEnvelope({
    required this.protocolVersion,
    required this.sessionId,
    required this.nonce,
    required this.sequence,
    required this.payload,
  });

  final int protocolVersion;
  final String sessionId;
  final String nonce;
  final int sequence;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'sessionId': sessionId,
    'nonce': nonce,
    'sequence': sequence,
    'payload': payload,
  };

  static PostMessageEnvelope decodeAndAuthorize(
    Object? message, {
    required Uri eventOrigin,
    required Uri expectedOrigin,
    required bool sourceMatches,
    required String expectedSessionId,
    required String expectedNonce,
    required int minimumSequence,
  }) {
    if (eventOrigin.origin != expectedOrigin.origin) {
      throw const FormatException('postMessage origin mismatch');
    }
    if (!sourceMatches) {
      throw const FormatException('postMessage source mismatch');
    }
    if (message is! Map<String, Object?>) {
      throw const FormatException('postMessage payload must be an object');
    }
    final protocolVersion = message['protocolVersion'];
    final sessionId = message['sessionId'];
    final nonce = message['nonce'];
    final sequence = message['sequence'];
    final payload = message['payload'];
    if (protocolVersion != 1 ||
        sessionId is! String ||
        nonce is! String ||
        sequence is! int ||
        payload is! Map<String, Object?>) {
      throw const FormatException('invalid postMessage envelope');
    }
    if (sessionId != expectedSessionId || nonce != expectedNonce) {
      throw const FormatException('postMessage session or nonce mismatch');
    }
    if (sequence <= minimumSequence) {
      throw const FormatException('postMessage replay detected');
    }
    return PostMessageEnvelope(
      protocolVersion: protocolVersion as int,
      sessionId: sessionId,
      nonce: nonce,
      sequence: sequence,
      payload: payload,
    );
  }
}
