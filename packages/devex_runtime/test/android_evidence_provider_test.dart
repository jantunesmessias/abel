import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory workspace;
  late Directory sdk;
  late _EvidenceAndroidRunner runner;
  late FileSystemWorkspaceStore store;
  late AndroidEvidenceProvider evidenceProvider;
  late AndroidTargetDescriptor target;
  late TargetContainmentReport containment;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('devex-android-evidence-');
    sdk = Directory.systemTemp.createTempSync('devex-android-sdk-');
    final adb = File(p.join(sdk.path, 'platform-tools', 'adb'));
    adb.parent.createSync(recursive: true);
    adb.writeAsStringSync('fixture');
    runner = _EvidenceAndroidRunner();
    store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    evidenceProvider = AndroidEvidenceProvider(
      provider: AndroidTargetProvider(sdkRoot: sdk.path, runner: runner),
      store: store,
      clock: _Clock(),
      ids: _Ids(),
    );
    target = AndroidTargetDescriptor(
      serial: 'emulator-5556',
      avdName: 'Neutral_API_35',
      apiLevel: 35,
      abi: 'x86_64',
      ownership: AndroidTargetOwnership.managed,
      capabilities: const <String>{
        'android.capture.png',
        'android.semantics',
        'android.logcat',
        'android.screen-recording',
        'android.performance-trace',
      },
    );
    containment = TargetContainmentReport(
      targetId: target.serial,
      adapterId: 'adb-reverse-v1',
      platform: 'androidEmulator',
      executedAt: DateTime.utc(2026, 8, 9, 11),
      networkContainment: NetworkContainment.gatewayOnly,
      probes: <ContainmentProbeResult>[
        ContainmentProbeResult(
          kind: ContainmentProbeKind.gatewayReachable,
          passed: true,
          detailCode: 'adb_reverse_verified',
        ),
      ],
    );
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
    sdk.deleteSync(recursive: true);
  });

  List<int> artifactBytes(Evidence evidence, String role) {
    final artifact = evidence.artifacts.singleWhere(
      (item) => item.role == role,
    );
    return store.readBlob(artifact.digest)!;
  }

  test(
    'collects correlated modalities with sanitized persisted payloads',
    () async {
      final catalog = Digest.semantic('catalog-v3');
      final result = await evidenceProvider.collect(
        target: target,
        catalogDigest: catalog,
        launchProfileId: 'android',
        packageName: 'dev.devexkit.sample',
        containment: containment,
        selection: const AndroidEvidenceSelection(
          screenRecording: true,
          performanceTrace: true,
          syntheticDataConfirmed: true,
        ),
        inputDigests: <String, Digest>{
          'apk': Digest.bytes(const <int>[1, 2, 3]),
        },
        sourceRevision: 'git:0123456789abcdef',
        backendMode: BackendMode.isolated,
      );

      expect(
        result.evidence.fingerprint.runtimeFidelity,
        RuntimeFidelity.hostNative,
      );
      expect(result.evidence.fingerprint.backendMode, BackendMode.isolated);
      expect(
        result.evidence.fingerprint.networkContainment,
        NetworkContainment.gatewayOnly,
      );
      expect(
        result.evidence.fingerprint.inputDigests['android.environment'],
        result.manifest.environment.digest,
      );
      expect(result.manifest.observations, hasLength(5));
      expect(
        result.manifest.observations.map((item) => item.status).toSet(),
        <AndroidEvidenceStatus>{AndroidEvidenceStatus.collected},
      );
      expect(
        result.evidence.artifacts.map((item) => item.role).toSet(),
        <String>{
          'android.environment',
          'android.logcat',
          'android.performance-trace',
          'android.screen-recording',
          'android.screenshot',
          'android.semantics',
        },
      );

      final semantics = artifactBytes(result.evidence, 'android.semantics');
      final logcat = artifactBytes(result.evidence, 'android.logcat');
      final semanticsText = utf8.decode(semantics);
      final logcatText = utf8.decode(logcat);
      expect(semanticsText, contains('textDigest'));
      expect(semanticsText, isNot(contains('Jane Doe')));
      expect(semanticsText, isNot(contains('secret@example.test')));
      expect(logcatText, contains('messageDigest'));
      expect(logcatText, isNot(contains('secret-token')));
      expect(logcatText, isNot(contains('Jane Doe')));

      final manifestArtifact = artifactBytes(
        result.evidence,
        'android.environment',
      );
      final persistedManifest = AndroidEvidenceManifest.fromJson(
        jsonDecode(utf8.decode(manifestArtifact)),
      );
      expect(persistedManifest.digest, result.manifest.digest);
      final repository = LocalEvidenceRepository(store: store);
      repository.persistEvidence(result.evidence);
      expect(repository.readLatestEvidence()!.digest, result.evidence.digest);
      expect(repository.freshnessFor(catalog), EvidenceFreshness.fresh);
      expect(
        runner.calls.where((item) => item.contains(' shell rm -f ')),
        hasLength(2),
      );
    },
  );

  test(
    'denies raw media without synthetic confirmation but retains safe modalities',
    () async {
      final result = await evidenceProvider.collect(
        target: target,
        catalogDigest: Digest.semantic('catalog-policy'),
        launchProfileId: 'android',
        packageName: 'dev.devexkit.sample',
        containment: containment,
        selection: const AndroidEvidenceSelection(
          screenRecording: true,
          performanceTrace: true,
        ),
      );
      final statuses = <String, AndroidEvidenceStatus>{
        for (final item in result.manifest.observations) item.role: item.status,
      };
      expect(
        statuses['android.screenshot'],
        AndroidEvidenceStatus.policyDenied,
      );
      expect(
        statuses['android.screen-recording'],
        AndroidEvidenceStatus.policyDenied,
      );
      expect(
        statuses['android.performance-trace'],
        AndroidEvidenceStatus.policyDenied,
      );
      expect(statuses['android.semantics'], AndroidEvidenceStatus.collected);
      expect(statuses['android.logcat'], AndroidEvidenceStatus.collected);
      expect(runner.calls, isNot(contains(contains('screenrecord'))));
      expect(runner.calls, isNot(contains(contains('perfetto'))));
    },
  );

  test('unavailable Perfetto degrades only that observation', () async {
    runner.perfettoUnavailable = true;
    final result = await evidenceProvider.collect(
      target: target,
      catalogDigest: Digest.semantic('catalog-degraded'),
      launchProfileId: 'android',
      packageName: 'dev.devexkit.sample',
      containment: containment,
      selection: const AndroidEvidenceSelection(
        screenRecording: true,
        performanceTrace: true,
        syntheticDataConfirmed: true,
      ),
    );
    final statuses = <String, AndroidEvidenceStatus>{
      for (final item in result.manifest.observations) item.role: item.status,
    };
    expect(
      statuses['android.performance-trace'],
      AndroidEvidenceStatus.unavailable,
    );
    expect(
      statuses.entries
          .where((item) => item.key != 'android.performance-trace')
          .map((item) => item.value)
          .toSet(),
      <AndroidEvidenceStatus>{AndroidEvidenceStatus.collected},
    );
    expect(
      result.evidence.artifacts.map((item) => item.role),
      isNot(contains('android.performance-trace')),
    );
    expect(runner.calls, contains(contains('shell rm -f')));
  });
}

final class _EvidenceAndroidRunner implements AndroidCommandRunner {
  final List<String> calls = <String>[];
  bool perfettoUnavailable = false;

  @override
  Future<AndroidCommandOutput> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final command = arguments.join(' ');
    calls.add(command);
    if (command == 'version') {
      return _text('Android Debug Bridge version 1.0.41\nVersion 36.0.0\n');
    }
    if (command.endsWith('shell getprop ro.build.fingerprint')) {
      return _text('google/sdk_gphone64_x86_64/emu:15/test-keys\n');
    }
    if (command.endsWith('shell getprop ro.build.version.incremental')) {
      return _text('12345678\n');
    }
    if (command.endsWith('shell getprop ro.boot.qemu.gltransport')) {
      return _text('virtio-gpu-pipe\n');
    }
    if (command.endsWith('shell getprop debug.hwui.renderer')) {
      return _text('skiagl\n');
    }
    if (command.endsWith('shell getprop persist.sys.locale')) {
      return _text('pt-BR\n');
    }
    if (command.endsWith('shell getprop persist.sys.timezone')) {
      return _text('America/Sao_Paulo\n');
    }
    if (command.endsWith('exec-out screencap -p')) {
      return _bytes(
        rgbaPng(
          width: 2,
          height: 1,
          pixels: const <int>[10, 20, 30, 255, 40, 50, 60, 255],
        ),
      );
    }
    if (command.endsWith('exec-out uiautomator dump /dev/tty')) {
      return _text('''UI hierchary dumped to: /dev/tty
<hierarchy rotation="0"><node index="0" text="Jane Doe" resource-id="dev.devexkit.sample:id/email" class="android.view.View" content-desc="secret@example.test" clickable="true" enabled="true" bounds="[0,0][10,10]" /></hierarchy>
''');
    }
    if (command.endsWith('shell pidof dev.devexkit.sample')) {
      return _text('42\n');
    }
    if (command.endsWith('logcat --pid=42 -d -v threadtime -t 2000')) {
      return _text(
        '08-09 12:34:56.789  42  43 I SecretTag: Jane Doe secret-token\n',
      );
    }
    if (command.contains(' shell screenrecord ')) return _text('');
    if (command.endsWith('.mp4') && command.contains(' exec-out cat ')) {
      return _bytes(<int>[
        0,
        0,
        0,
        24,
        ...utf8.encode('ftyp'),
        ...List<int>.filled(24, 1),
      ]);
    }
    if (command.contains(' shell perfetto ')) {
      if (perfettoUnavailable) {
        return _failure('perfetto: inaccessible or not found');
      }
      return _text('');
    }
    if (command.endsWith('.perfetto-trace') &&
        command.contains(' exec-out cat ')) {
      return _bytes(List<int>.generate(64, (index) => index));
    }
    if (command.contains(' shell rm -f ')) return _text('');
    throw StateError('Unexpected fake Android command: $command');
  }

  AndroidCommandOutput _text(String value) => _bytes(utf8.encode(value));

  AndroidCommandOutput _bytes(List<int> value) =>
      AndroidCommandOutput(exitCode: 0, stdout: value, stderr: const <int>[]);

  AndroidCommandOutput _failure(String value) => AndroidCommandOutput(
    exitCode: 127,
    stdout: const <int>[],
    stderr: utf8.encode(value),
  );
}

final class _Clock implements Clock {
  @override
  int monotonicMicroseconds() => 123;

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 9, 12);
}

final class _Ids implements IdGenerator {
  var next = 0;

  @override
  String nextId() => 'fixture-${next++}';
}
