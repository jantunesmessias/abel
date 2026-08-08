import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  _NetworkTestBinding();

  testWidgets('binding is constructor-injected through the target scope', (
    tester,
  ) async {
    final binding = TargetBinding(
      sessionId: 'session-1',
      nonce: '0123456789abcdef',
      runtimeConfiguration: <String, String>{
        'EXAMPLE_API_URL': 'http://127.0.0.1:8181',
      },
      capabilities: <String>{'checkpoint.open'},
    );
    late TargetBinding observed;

    await tester.pumpWidget(
      TargetScope(
        binding: binding,
        child: Builder(
          builder: (context) {
            observed = TargetScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(observed, same(binding));
  });

  testWidgets(
    'target composition injects only advertised App Adapter controls',
    (tester) async {
      var highlighted = false;
      final control = BooleanControlCapability(
        id: 'sample.dashboard.ready-control',
        readOperation: 'read-enabled',
        writeOperation: 'write-enabled',
        resetOperation: 'reset-enabled',
        read: () => highlighted,
        write: (value) => highlighted = value,
        reset: () => highlighted = false,
      );
      final binding = TargetBinding(
        sessionId: 'session-control',
        nonce: '0123456789abcdef',
        runtimeConfiguration: const <String, String>{},
        capabilities: <String>{control.descriptor.id},
      );
      final handle = runFlutterTarget(
        binding: binding,
        capabilities: <AppCapability>[control],
        app: const SizedBox(),
      );
      await tester.pump();

      expect(handle.adapter.descriptors.single.id, control.descriptor.id);
      await handle.adapter.invoke(
        capabilityId: control.descriptor.id,
        operation: control.writeOperation,
        arguments: const <String, Object?>{'value': true},
      );
      expect(highlighted, isTrue);
      handle.dispose();

      final unadvertisedBinding = TargetBinding(
        sessionId: 'session-unadvertised',
        nonce: '0123456789abcdef',
        runtimeConfiguration: const <String, String>{},
        capabilities: const <String>{},
      );
      expect(
        () => runFlutterTarget(
          binding: unadvertisedBinding,
          capabilities: <AppCapability>[control],
          app: const SizedBox(),
        ),
        throwsArgumentError,
      );
    },
  );

  testWidgets('target composition binds an optional typed relay instance', (
    tester,
  ) async {
    const nonce = 'relay_nonce_value_123456';
    final control = BooleanControlCapability(
      id: 'sample.dashboard.ready-control',
      readOperation: 'read-enabled',
      writeOperation: 'write-enabled',
      resetOperation: 'reset-enabled',
      read: () => false,
      write: (_) {},
      reset: () {},
    );
    final binding = TargetBinding(
      sessionId: 'run-session-1',
      nonce: nonce,
      runtimeConfiguration: const <String, String>{},
      capabilities: <String>{control.descriptor.id},
    );
    final configuration = AppAdapterRelayConfiguration(
      runId: ScenarioLabRunId('run-session-1'),
      adapterInstanceId: 'adapter-instance-1',
      nonce: AppAdapterRelayNonce(nonce),
      evidenceProviderIds: <ModuleId>[ModuleId('capture.web')],
    );

    final handle = runFlutterTarget(
      binding: binding,
      capabilities: <AppCapability>[control],
      relayConfiguration: configuration,
      app: const SizedBox(),
    );
    await tester.pump();

    expect(handle.relay?.hello.runId, configuration.runId);
    expect(handle.relay?.hello.adapterInstanceId, 'adapter-instance-1');
    expect(
      handle.relay?.hello.capabilities.single.id.value,
      control.descriptor.id,
    );
    handle.dispose();

    expect(
      () => runFlutterTarget(
        binding: binding,
        capabilities: <AppCapability>[control],
        relayConfiguration: AppAdapterRelayConfiguration(
          runId: ScenarioLabRunId('run-session-2'),
          adapterInstanceId: 'adapter-instance-2',
          nonce: AppAdapterRelayNonce(nonce),
        ),
        app: const SizedBox(),
      ),
      throwsArgumentError,
    );

    expect(
      () => runFlutterTarget(
        binding: binding,
        capabilities: <AppCapability>[control],
        relayConfiguration: AppAdapterRelayConfiguration(
          runId: ScenarioLabRunId('run-session-1'),
          adapterInstanceId: 'adapter-instance-3',
          nonce: AppAdapterRelayNonce('different_nonce_value_1234'),
        ),
        app: const SizedBox(),
      ),
      throwsArgumentError,
    );
  });

  testWidgets('semantics identifier is independent from visible copy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TargetSemantics(
          identifier: 'sample.increment',
          label: 'Incrementar',
          button: true,
          child: Text('Outro texto'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(TargetSemantics)).identifier,
      'sample.increment',
    );
    semantics.dispose();
  });

  testWidgets('widget capture controller produces a lossless PNG', (
    tester,
  ) async {
    final capture = WidgetCaptureController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: capture.wrap(
          const ColoredBox(
            color: Color(0xff123456),
            child: SizedBox(width: 32, height: 24),
          ),
        ),
      ),
    );

    await tester.pump();
    final bytes = await tester.runAsync(capture.capturePng);

    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  });

  testWidgets('App Adapter uploads a real widget capture into controller CAS', (
    tester,
  ) async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-flutter-capture-',
    );
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    final bridge = AppAdapterCaptureBridge(
      store: store,
      clock: SystemClock(),
      ids: SecureIdGenerator(),
    );
    final capture = WidgetCaptureController();
    final adapter = AppAdapter(
      capabilities: const <AppCapability>[],
      captureHandler: (_) => capture.capturePng(),
    );
    final originClient = _OriginClient(
      delegate: http.Client(),
      origin: 'http://127.0.0.1:8181',
    );
    final uploader = AppAdapterCaptureUploader(client: originClient);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: capture.wrap(
          const ColoredBox(
            color: Color(0xff654321),
            child: SizedBox(width: 24, height: 16),
          ),
        ),
      ),
    );

    try {
      await tester.runAsync(bridge.start);
      final command = bridge.issue(
        requestId: 'request_flutter_capture',
        sessionId: 'session_flutter_capture',
        targetOrigin: Uri.parse('http://127.0.0.1:8181'),
      );
      final result = await tester.runAsync(
        () => uploader.upload(command: command, adapter: adapter),
      );
      final status = bridge.status(
        sessionId: command.sessionId,
        requestId: command.requestId,
      );

      expect(result?.ok, isTrue);
      expect(status.state, 'completed');
      expect(
        status.receipt?.width,
        tester.view.physicalSize.width ~/ tester.view.devicePixelRatio,
      );
      expect(
        status.receipt?.height,
        tester.view.physicalSize.height ~/ tester.view.devicePixelRatio,
      );
      expect(store.readBlob(status.receipt!.artifactDigest), isNotEmpty);
    } finally {
      uploader.close();
      originClient.close();
      await tester.runAsync(bridge.close);
      workspace.deleteSync(recursive: true);
    }
  });
}

final class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

final class _OriginClient extends http.BaseClient {
  _OriginClient({required this.delegate, required this.origin});

  final http.Client delegate;
  final String origin;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['origin'] = origin;
    return delegate.send(request);
  }

  @override
  void close() => delegate.close();
}
