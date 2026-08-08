import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late Directory sdk;
  late _FakeAndroidRunner runner;
  late AndroidTargetProvider provider;
  late AndroidBootstrapService service;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync(
      'workspace-android-workspace-',
    );
    sdk = Directory.systemTemp.createTempSync('workspace-android-sdk-');
    final adb = File(p.join(sdk.path, 'platform-tools', 'adb'));
    adb.parent.createSync(recursive: true);
    adb.writeAsStringSync('fixture');
    final emulator = File(p.join(sdk.path, 'emulator', 'emulator'));
    emulator.parent.createSync(recursive: true);
    emulator.writeAsStringSync('fixture');
    runner = _FakeAndroidRunner();
    provider = AndroidTargetProvider(sdkRoot: sdk.path, runner: runner);
    service = AndroidBootstrapService(
      workspaceRoot: workspace.path,
      provider: provider,
    );
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
    sdk.deleteSync(recursive: true);
  });

  test('discovers only emulators and keeps attached ownership', () async {
    final targets = await provider.discover();

    expect(targets, hasLength(1));
    expect(targets.single.serial, 'emulator-5554');
    expect(targets.single.ownership, AndroidTargetOwnership.attached);
    expect(targets.single.apiLevel, 35);
  });

  test(
    'system Android runner kills a command that exceeds its timeout',
    () async {
      if (!Platform.isLinux) return;
      final pidFile = File(p.join(workspace.path, 'timed-out.pid'));

      await expectLater(
        const SystemAndroidCommandRunner().run('/bin/sh', <String>[
          '-c',
          'echo \$\$ > "${pidFile.path}"; exec sleep 30',
        ], timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );

      final childPid = int.parse(pidFile.readAsStringSync().trim());
      final probe = await Process.run('/bin/kill', <String>['-0', '$childPid']);
      expect(probe.exitCode, isNot(0));
    },
  );

  test('bootstrap dry-run, apply, update and undo are idempotent', () async {
    final first = _pairing(host: 41000, target: 51000);
    final second = _pairing(host: 42000, target: 52000);

    final preview = await service.bootstrap(
      serial: 'emulator-5554',
      pairing: first,
      apply: false,
    );
    expect(preview.mode, AndroidLifecycleMode.dryRun);
    expect(runner.reverses, isEmpty);
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );

    final applied = await service.bootstrap(
      serial: 'emulator-5554',
      pairing: first,
      apply: true,
    );
    expect(applied.changed, isTrue);
    expect(applied.verified, isTrue);
    expect(runner.reverses, <int, int>{51000: 41000});

    final again = await service.bootstrap(
      serial: 'emulator-5554',
      pairing: first,
      apply: true,
    );
    expect(again.changed, isFalse);
    expect((await service.verify()).verified, isTrue);

    final updated = await service.update(
      serial: 'emulator-5554',
      pairing: second,
      apply: true,
    );
    expect(updated.changed, isTrue);
    expect(runner.reverses, <int, int>{52000: 42000});

    final removed = await service.remove(apply: true);
    expect(removed.verified, isTrue);
    expect(runner.reverses, isEmpty);
    expect((await service.remove(apply: true)).changed, isFalse);
  });

  test('launch injects only the ephemeral resolved endpoint', () async {
    final request = AndroidLaunchRequest(
      packageName: 'io.github.jantunesmessias.sample',
      activity: '.MainActivity',
      pairing: _pairing(host: 41000, target: 51000),
      overlay: RuntimeConfigurationOverlay(const <String, String>{
        'SCENARIO_ID': 'ready',
      }),
    );

    await provider.launch('emulator-5554', request);

    final launch = runner.calls.singleWhere(
      (call) => call.contains('am start'),
    );
    expect(launch, contains('GATEWAY_ORIGIN'));
    expect(launch, contains('http://127.0.0.1:51000'));
    expect(launch, contains('SCENARIO_ID'));
  });

  test(
    'launch accepts am timeout only after exact activity readiness',
    () async {
      runner.launchStatus = 'timeout';
      final request = AndroidLaunchRequest(
        packageName: 'io.github.jantunesmessias.sample',
        activity: '.MainActivity',
        pairing: _pairing(host: 41000, target: 51000),
        overlay: RuntimeConfigurationOverlay(const <String, String>{}),
      );

      await provider.launch('emulator-5554', request);

      expect(
        runner.calls,
        contains(contains('shell pidof io.github.jantunesmessias.sample')),
      );
      expect(
        runner.calls,
        contains(contains('shell dumpsys activity activities')),
      );
    },
  );

  test(
    'install, reset and lossless capture use bounded ADB operations',
    () async {
      final apk = File(p.join(workspace.path, 'sample.apk'))
        ..writeAsBytesSync(const <int>[1, 2, 3]);

      await provider.installApk('emulator-5554', apk.path);
      await provider.resetPackage(
        'emulator-5554',
        'io.github.jantunesmessias.sample',
      );
      final capture = await provider.capturePng('emulator-5554');

      expect(capture.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    },
  );

  test('privileged operations reject attached emulators', () async {
    final target = (await provider.discover()).single;
    expect(
      () => provider.runManagedAdb(target, const <String>['root']),
      throwsStateError,
    );
    await expectLater(
      service.bootstrap(
        serial: target.serial,
        pairing: AndroidGatewayPairing(
          strategy: AndroidGatewayRouteStrategy.adbReverse,
          hostPort: 41000,
          targetPort: 51000,
          tls: true,
        ),
        apply: false,
      ),
      throwsStateError,
    );
  });

  test(
    'managed lifecycle owns and stops only the emulator it starts',
    () async {
      final managed = AndroidManagedEmulatorService(
        workspaceRoot: workspace.path,
        provider: provider,
        launcher: _FakeEmulatorLauncher(runner),
        processExists: (_) => runner.managedStarted,
      );

      final preview = await managed.start(
        avdName: 'Neutral_API_35',
        port: 5556,
        apply: false,
      );
      expect(preview.changed, isTrue);
      expect(runner.managedStarted, isFalse);

      final started = await managed.start(
        avdName: 'Neutral_API_35',
        port: 5556,
        apply: true,
      );
      expect(started.target?.serial, 'emulator-5556');
      expect(started.target?.ownership, AndroidTargetOwnership.managed);
      expect((await managed.status()).verified, isTrue);
      expect(
        (await managed.start(
          avdName: 'Neutral_API_35',
          port: 5556,
          apply: true,
        )).changed,
        isFalse,
      );

      final stopped = await managed.stop(apply: true);
      expect(stopped.verified, isTrue);
      expect(runner.managedStarted, isFalse);
      expect((await provider.discover()).single.serial, 'emulator-5554');
      expect((await managed.stop(apply: true)).changed, isFalse);
    },
  );

  test('managed lifecycle removes only proven-dead stale ownership', () async {
    final managed = AndroidManagedEmulatorService(
      workspaceRoot: workspace.path,
      provider: provider,
      launcher: _FakeEmulatorLauncher(runner),
      processExists: (_) => runner.managedStarted,
    );
    await managed.start(avdName: 'Neutral_API_35', port: 5556, apply: true);
    runner.managedStarted = false;

    expect((await managed.status()).verified, isFalse);
    final preview = await managed.stop(apply: false);
    expect(preview.changed, isTrue);
    expect(preview.verified, isFalse);
    expect((await managed.stop(apply: true)).verified, isTrue);
    expect((await managed.status()).verified, isTrue);
  });

  test('bootstrap derives managed ownership from lifecycle state', () async {
    final managed = AndroidManagedEmulatorService(
      workspaceRoot: workspace.path,
      provider: provider,
      launcher: _FakeEmulatorLauncher(runner),
      processExists: (_) => runner.managedStarted,
    );
    await managed.start(avdName: 'Neutral_API_35', port: 5556, apply: true);
    final managedBootstrap = AndroidBootstrapService(
      workspaceRoot: workspace.path,
      provider: provider,
      managedTargetResolver: managed.ownedTarget,
    );

    final report = await managedBootstrap.bootstrap(
      serial: 'emulator-5556',
      pairing: AndroidGatewayPairing(
        strategy: AndroidGatewayRouteStrategy.adbReverse,
        hostPort: 41000,
        targetPort: 51000,
        tls: true,
      ),
      apply: true,
    );

    expect(report.target?.ownership, AndroidTargetOwnership.managed);
  });

  test('bootstrap removal recovers when configured target is absent', () async {
    await service.bootstrap(
      serial: 'emulator-5554',
      pairing: _pairing(host: 41000, target: 51000),
      apply: true,
    );
    runner.attachedStarted = false;

    expect((await service.verify()).verified, isFalse);
    expect((await service.remove(apply: true)).verified, isTrue);
    expect((await service.remove(apply: true)).changed, isFalse);
  });

  test(
    'workspace TLS material is managed-only, expiring and reversible',
    () async {
      final target = AndroidTargetDescriptor(
        serial: 'emulator-5556',
        avdName: 'Neutral_API_35',
        apiLevel: 35,
        abi: 'x86_64',
        ownership: AndroidTargetOwnership.managed,
        capabilities: const <String>{'android.install.ca'},
      );
      runner.managedStarted = true;
      final tls = WorkspaceTlsService(
        workspaceRoot: workspace.path,
        provider: provider,
      );

      final preview = await tls.install(target: target, apply: false);
      expect(preview.mode, AndroidLifecycleMode.dryRun);
      expect(
        Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
        isFalse,
      );

      final installed = await tls.install(target: target, apply: true);
      expect(installed.verified, isTrue);
      expect(installed.artifactDigest, isNotNull);
      expect(runner.remoteFiles, hasLength(1));
      final key = File(
        p.join(
          workspace.path,
          '.dart_tool',
          'workspace',
          'full-local',
          'android',
          'tls',
          'ca-key.pem',
        ),
      );
      expect(key.statSync().mode & 0x1ff, 0x180);
      expect((await tls.verify()).verified, isTrue);
      expect((await tls.install(target: target, apply: true)).changed, isFalse);

      expect((await tls.remove(apply: false)).changed, isTrue);
      expect((await tls.remove(apply: true)).verified, isTrue);
      expect(runner.remoteFiles, isEmpty);
      expect(key.existsSync(), isFalse);
      expect((await tls.remove(apply: true)).changed, isFalse);
    },
  );

  test(
    'failed TLS bootstrap removes private material before remote copy',
    () async {
      final target = AndroidTargetDescriptor(
        serial: 'emulator-5556',
        avdName: 'Neutral_API_35',
        apiLevel: 35,
        abi: 'x86_64',
        ownership: AndroidTargetOwnership.managed,
        capabilities: const <String>{'android.install.ca'},
      );
      runner.managedStarted = true;
      runner.rootFails = true;
      final tls = WorkspaceTlsService(
        workspaceRoot: workspace.path,
        provider: provider,
      );

      await expectLater(
        tls.install(target: target, apply: true),
        throwsA(isA<ProcessException>()),
      );

      expect(
        Directory(
          p.join(
            workspace.path,
            '.dart_tool',
            'workspace',
            'full-local',
            'android',
            'tls',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            workspace.path,
            '.dart_tool',
            'workspace',
            'full-local',
            'android',
            'tls-v1.json',
          ),
        ).existsSync(),
        isFalse,
      );
    },
  );
}

AndroidGatewayPairing _pairing({required int host, required int target}) =>
    AndroidGatewayPairing(
      strategy: AndroidGatewayRouteStrategy.adbReverse,
      hostPort: host,
      targetPort: target,
      tls: false,
    );

final class _FakeAndroidRunner implements AndroidCommandRunner {
  final Map<int, int> reverses = <int, int>{};
  final List<String> calls = <String>[];
  final Set<String> remoteFiles = <String>{};
  bool managedStarted = false;
  bool attachedStarted = true;
  String launchStatus = 'ok';
  bool rootFails = false;

  @override
  Future<AndroidCommandOutput> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls.add(arguments.join(' '));
    final command = arguments.join(' ');
    if (command == '-list-avds') return _text('Neutral_API_35\n');
    if (command == 'devices -l') {
      return _text('''List of devices attached
${attachedStarted ? 'emulator-5554 device product:sdk_gphone64_x86_64' : ''}
${managedStarted ? 'emulator-5556 device product:sdk_gphone64_x86_64' : ''}
R58M123456A device product:physical
''');
    }
    if (command == 'devices') {
      return _text('''List of devices attached
${attachedStarted ? 'emulator-5554\tdevice' : ''}
${managedStarted ? 'emulator-5556\tdevice' : ''}
''');
    }
    if (command.endsWith('shell getprop ro.build.version.sdk')) {
      return _text('35\n');
    }
    if (command.endsWith('shell getprop ro.product.cpu.abi')) {
      return _text('x86_64\n');
    }
    if (command.endsWith('emu avd name')) {
      return _text(
        command.contains('emulator-5556')
            ? 'Neutral_API_35\nOK\n'
            : 'Neutral_API_35\nOK\n',
      );
    }
    if (command.endsWith('wait-for-device')) return _text('');
    if (command.endsWith('shell getprop sys.boot_completed')) {
      return _text('1\n');
    }
    if (command.endsWith('shell getprop init.svc.bootanim')) {
      return _text('stopped\n');
    }
    if (command.endsWith('shell cmd package list packages --user 0')) {
      return _text('package:android\n');
    }
    if (command.endsWith('emu kill')) {
      managedStarted = false;
      return _text('OK\n');
    }
    if (command.endsWith(' root') && rootFails) {
      return AndroidCommandOutput(
        exitCode: 1,
        stdout: const <int>[],
        stderr: utf8.encode('adbd cannot run as root'),
      );
    }
    if (command.endsWith(' root') || command.endsWith(' wait-for-device')) {
      return _text('');
    }
    if (command.contains(' push ')) return _text('1 file pushed\n');
    final copy = RegExp(r' shell cp \S+ (\S+)$').firstMatch(command);
    if (copy != null) {
      remoteFiles.add(copy.group(1)!);
      return _text('');
    }
    final removeRemote = RegExp(r' shell rm -f (\S+)$').firstMatch(command);
    if (removeRemote != null) {
      remoteFiles.remove(removeRemote.group(1)!);
      return _text('');
    }
    final testRemote = RegExp(r' shell test -f (\S+)$').firstMatch(command);
    if (testRemote != null) {
      return AndroidCommandOutput(
        exitCode: remoteFiles.contains(testRemote.group(1)) ? 0 : 1,
        stdout: const <int>[],
        stderr: const <int>[],
      );
    }
    if (command.contains(' shell mkdir ') ||
        command.contains(' shell chmod ') ||
        command.contains(' shell restorecon ')) {
      return _text('');
    }
    if (command.endsWith('reverse --list')) {
      return _text(
        reverses.entries
            .map(
              (entry) => 'emulator-5554 tcp:${entry.key} tcp:${entry.value}\n',
            )
            .join(),
      );
    }
    final add = RegExp(
      r'reverse tcp:([0-9]+) tcp:([0-9]+)$',
    ).firstMatch(command);
    if (add != null) {
      reverses[int.parse(add.group(1)!)] = int.parse(add.group(2)!);
      return _text('');
    }
    final remove = RegExp(
      r'reverse --remove tcp:([0-9]+)$',
    ).firstMatch(command);
    if (remove != null) {
      reverses.remove(int.parse(remove.group(1)!));
      return _text('');
    }
    if (command.contains(' shell am start ')) {
      return _text('Status: $launchStatus\n');
    }
    if (command.contains(' shell pidof ')) return _text('42\n');
    if (command.endsWith('shell dumpsys activity activities')) {
      return _text(
        'topResumedActivity=ActivityRecord{a1 u0 io.github.jantunesmessias.sample/.MainActivity t1}\n',
      );
    }
    if (command.contains(' shell am force-stop ')) {
      return _text('');
    }
    if (command.contains(' shell pm clear ')) {
      return _text('Success\n');
    }
    if (command.contains(' install -r --no-streaming ')) {
      return _text('Success\n');
    }
    if (command.endsWith('exec-out screencap -p')) {
      return AndroidCommandOutput(
        exitCode: 0,
        stdout: <int>[
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          ...List<int>.filled(24, 0),
        ],
        stderr: const <int>[],
      );
    }
    throw StateError('Unexpected fake Android command: $command');
  }

  AndroidCommandOutput _text(String value) => AndroidCommandOutput(
    exitCode: 0,
    stdout: utf8.encode(value),
    stderr: const <int>[],
  );
}

final class _FakeEmulatorLauncher implements AndroidEmulatorLauncher {
  const _FakeEmulatorLauncher(this.runner);

  final _FakeAndroidRunner runner;

  @override
  Future<int> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    expect(arguments, containsAllInOrder(<String>['-avd', 'Neutral_API_35']));
    expect(arguments, containsAllInOrder(<String>['-port', '5556']));
    runner.managedStarted = true;
    return 12345;
  }
}
