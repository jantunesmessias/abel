import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  final clock = _FixedClock(DateTime.utc(2026, 8, 9, 12, 34, 56));
  final store = S3CompatibleObjectStore(
    configuration: S3ObjectStoreConfiguration(
      endpoint: Uri.parse('https://objects.example.test'),
      bucket: 'workspace-artifacts',
      region: 'us-test-1',
      credentials: const S3Credentials(
        accessKeyId: 'TESTACCESS',
        secretAccessKey: 'test-secret-never-exported',
      ),
    ),
    clock: clock,
  );
  final context = HostedRequestContext(
    tenantId: 'tenant-a',
    principalId: 'principal-a',
    correlationId: 'correlation-001',
  );
  final digest = Digest.semantic('artifact');

  test(
    'presigned upload is deterministic, short-lived, and tenant scoped',
    () async {
      final first = await store.authorizeUpload(
        context,
        digest: digest,
        size: 8,
        mediaType: 'application/octet-stream',
        classification: 'internal',
      );
      final second = await store.authorizeUpload(
        context,
        digest: digest,
        size: 8,
        mediaType: 'application/octet-stream',
        classification: 'internal',
      );
      expect(first.uri, second.uri);
      expect(first.uri.scheme, 'https');
      expect(
        first.uri.path,
        '/workspace-artifacts/tenants/tenant-a/blobs/sha256/${digest.value.substring(7)}',
      );
      expect(first.uri.queryParameters['X-Amz-Expires'], '300');
      expect(first.uri.queryParameters['X-Amz-Signature'], hasLength(64));
      expect(
        first.uri.toString(),
        isNot(contains('test-secret-never-exported')),
      );
      expect(first.descriptor.tenantId, 'tenant-a');
    },
  );

  test(
    'download rejects cross-tenant descriptors and insecure endpoints',
    () async {
      final descriptor = HostedBlobDescriptor(
        tenantId: 'tenant-b',
        digest: digest,
        size: 8,
        mediaType: 'application/octet-stream',
        classification: 'internal',
        objectKey: 'tenants/tenant-b/blobs/sha256/${digest.value.substring(7)}',
      );
      expect(
        () => store.authorizeDownload(context, descriptor),
        throwsA(isA<HostedAuthorizationException>()),
      );
      expect(
        () => S3ObjectStoreConfiguration(
          endpoint: Uri.parse('http://objects.example.test'),
          bucket: 'workspace-artifacts',
          region: 'us-test-1',
          credentials: const S3Credentials(
            accessKeyId: 'access',
            secretAccessKey: 'secret',
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}
