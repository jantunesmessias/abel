import 'dart:io';

import 'package:archive/archive.dart';
import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('devex-system-worker-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  test(
    'web runner consumes only prebuilt archive and emits bounded PNG',
    () async {
      final build = File(p.join(root.path, 'web.zip'));
      _zip(build, <ArchiveFile>[
        ArchiveFile.string('index.html', '<!doctype html><title>DevEx</title>'),
      ]);
      final chromium = File(p.join(root.path, 'chromium'))
        ..writeAsStringSync(r'''#!/bin/sh
set -eu
for argument in "$@"; do
  case "$argument" in
    --screenshot=*) output="${argument#--screenshot=}" ;;
  esac
done
printf '\211PNG\r\n\032\n0000000000000000' > "$output"
''');
      expect(
        Process.runSync('chmod', <String>['755', chromium.path]).exitCode,
        0,
      );
      final backend = SystemRemoteWorkerBackend(
        SystemRemoteWorkerConfiguration(
          chromiumExecutable: chromium.path,
          androidSdkRoot: root.path,
          androidAvdName: 'unused',
          androidImageDigest: Digest.semantic('unused-image'),
          gatewayPort: 8443,
        ),
      );
      final plan = _webPlan(build);
      final result = await backend.execute(
        plan: plan,
        inputsByRole: <String, File>{'webBuild': build},
        workspace: root,
      );
      addTearDown(backend.stop);
      expect(result.artifacts.single.mediaType, 'image/png');
      expect(result.artifacts.single.file.existsSync(), isTrue);
      expect(result.interactiveTransport, RemoteInteractiveTransport.webDirect);
      expect(result.interactiveSession, isNotNull);
    },
  );

  test('web archive traversal fails before the browser is executed', () async {
    final build = File(p.join(root.path, 'unsafe.zip'));
    _zip(build, <ArchiveFile>[
      ArchiveFile.string('../escape.txt', 'escape'),
      ArchiveFile.string('index.html', 'index'),
    ]);
    final marker = File(p.join(root.path, 'browser-was-run'));
    final chromium = File(p.join(root.path, 'chromium'))
      ..writeAsStringSync('#!/bin/sh\ntouch "${marker.path}"\n');
    expect(
      Process.runSync('chmod', <String>['755', chromium.path]).exitCode,
      0,
    );
    final backend = SystemRemoteWorkerBackend(
      SystemRemoteWorkerConfiguration(
        chromiumExecutable: chromium.path,
        androidSdkRoot: root.path,
        androidAvdName: 'unused',
        androidImageDigest: Digest.semantic('unused-image'),
        gatewayPort: 8443,
      ),
    );
    await expectLater(
      backend.execute(
        plan: _webPlan(build),
        inputsByRole: <String, File>{'webBuild': build},
        workspace: root,
      ),
      throwsStateError,
    );
    expect(marker.existsSync(), isFalse);
    expect(File(p.join(root.parent.path, 'escape.txt')).existsSync(), isFalse);
  });
}

void _zip(File output, List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  output.writeAsBytesSync(ZipEncoder().encode(archive));
}

RemoteExecutionPlan _webPlan(File build) {
  final now = DateTime.utc(2026, 8, 9, 12);
  return RemoteExecutionPlan(
    tenantId: 'tenant-a',
    runId: 'run-001',
    requestDigest: Digest.semantic('request'),
    target: RemoteTargetKind.web,
    mode: RemoteRunMode.interactive,
    interactiveTransport: RemoteInteractiveTransport.webDirect,
    artifacts: <RemoteArtifactInput>[
      RemoteArtifactInput(
        role: 'webBuild',
        digest: Digest.bytes(build.readAsBytesSync()),
        size: build.lengthSync(),
        mediaType: 'application/zip',
      ),
    ],
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    containmentPolicyDigest: Digest.semantic('containment'),
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    nonce: 'nonce-001',
  );
}
