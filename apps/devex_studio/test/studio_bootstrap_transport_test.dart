import 'package:devex_studio/src/host/studio_bootstrap_transport.dart';
import 'package:test/test.dart';

void main() {
  test('rejects an HTML SPA fallback before attempting JSON decoding', () {
    expect(
      () => decodeStudioBootstrapResponse(
        statusCode: 200,
        contentType: 'text/html; charset=utf-8',
        body: '<!doctype html><title>DevExKit Studio</title>',
      ),
      throwsA(
        isA<StudioBootstrapException>().having(
          (error) => error.message,
          'message',
          contains('devex dev'),
        ),
      ),
    );
  });

  test('accepts JSON and rejects oversized or malformed responses', () {
    expect(
      decodeStudioBootstrapResponse(
        statusCode: 200,
        contentType: 'application/json; charset=utf-8',
        body: '{"schemaVersion":1}',
      ),
      <String, Object?>{'schemaVersion': 1},
    );
    expect(
      () => decodeStudioBootstrapResponse(
        statusCode: 503,
        contentType: 'text/plain',
        body: 'starting',
      ),
      throwsA(isA<StudioBootstrapException>()),
    );
    expect(
      () => decodeStudioBootstrapResponse(
        statusCode: 200,
        contentType: 'application/json',
        body: '{invalid',
      ),
      throwsA(isA<StudioBootstrapException>()),
    );
  });

  test('resolves only the default path or an explicit loopback URL', () {
    expect(resolveStudioBootstrapUri(''), Uri(path: '/devex/bootstrap.json'));
    expect(
      resolveStudioBootstrapUri('http://127.0.0.1:39001/devex/bootstrap.json'),
      Uri.parse('http://127.0.0.1:39001/devex/bootstrap.json'),
    );
    expect(
      () =>
          resolveStudioBootstrapUri('https://example.com/devex/bootstrap.json'),
      throwsA(isA<StudioBootstrapException>()),
    );
    expect(
      () => resolveStudioBootstrapUri('http://127.0.0.1:39001/other'),
      throwsA(isA<StudioBootstrapException>()),
    );
  });
}
