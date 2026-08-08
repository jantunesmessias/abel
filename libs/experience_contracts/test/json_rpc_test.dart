import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  const codec = JsonRpcCodec();

  test('round-trips a request with a stable envelope', () {
    const request = JsonRpcRequest(
      method: 'workspace.initialize',
      id: 'op-1',
      params: <String, Object?>{'protocolVersion': 1},
    );

    final decoded = codec.decode(request.encode());

    expect(decoded, isA<JsonRpcRequest>());
    expect((decoded as JsonRpcRequest).method, 'workspace.initialize');
    expect(decoded.id, 'op-1');
  });

  test('rejects an ambiguous response', () {
    expect(
      () => codec.decode('{"jsonrpc":"2.0","id":1,"result":{},"error":{}}'),
      throwsA(isA<JsonRpcFormatException>()),
    );
  });

  test('rejects invalid params and identifiers', () {
    expect(
      () => codec.decode(
        '{"jsonrpc":"2.0","method":"workspace.initialize","params":1,"id":1}',
      ),
      throwsA(isA<JsonRpcFormatException>()),
    );
    expect(
      () => codec.decode(
        '{"jsonrpc":"2.0","method":"workspace.initialize","id":1.5}',
      ),
      throwsA(isA<JsonRpcFormatException>()),
    );
  });
}
