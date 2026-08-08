import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/catalog/sample_catalog.dart';
import 'package:devex_studio/src/controllers/studio_workspace_controller.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:test/test.dart';

void main() {
  test('opens a workspace and accepts Host revision events', () async {
    final first = _snapshot(1);
    final second = _snapshot(2);
    final client = _FakeHostClient(<WorkspaceSnapshot>[first, second]);
    final controller = StudioWorkspaceController(clientFactory: () => client);

    await controller.connect();
    expect(controller.state.snapshot?.revision, 1);
    expect(controller.state.connection.connected, isTrue);

    client.notifyWorkspaceChanged();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.snapshot?.revision, 2);
    expect(controller.state.connection.connected, isTrue);
    await controller.close();
  });

  test('preserves stale state and reconnects with a new client', () async {
    final firstClient = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(1)]);
    final secondClient = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(2)]);
    final clients = <_FakeHostClient>[firstClient, secondClient];
    var nextClient = 0;
    final controller = StudioWorkspaceController(
      clientFactory: () => clients[nextClient++],
      reconnectDelay: Duration.zero,
    );

    await controller.connect();
    firstClient.disconnect(StateError('transport lost'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.state.snapshot?.revision, 2);
    expect(controller.state.connection.connected, isTrue);
    expect(firstClient.closed, isTrue);
    await controller.close();
  });

  test(
    'keeps an initial failure explicit and retries without user action',
    () async {
      final failing = _FakeHostClient(
        const <WorkspaceSnapshot>[],
        openError: StateError('Host unavailable'),
      );
      final recovered = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(1)]);
      final clients = <_FakeHostClient>[failing, recovered];
      var nextClient = 0;
      final controller = StudioWorkspaceController(
        clientFactory: () => clients[nextClient++],
        reconnectDelay: Duration.zero,
      );

      await controller.connect();
      expect(controller.state.snapshot, isNull);
      expect(controller.state.failureMessage, contains('Host unavailable'));
      expect(nextClient, 1);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.state.snapshot?.revision, 1);
      expect(controller.state.failureMessage, isNull);
      expect(nextClient, 2);
      await controller.close();
    },
  );
}

final class _FakeHostClient
    implements StudioHostClient, StudioHostWorkspaceEvents {
  _FakeHostClient(this.snapshots, {this.openError});

  final List<WorkspaceSnapshot> snapshots;
  final Object? openError;
  final StreamController<void> _events = StreamController<void>.broadcast();
  var _nextSnapshot = 0;
  bool closed = false;

  @override
  Stream<void> get workspaceChanges => _events.stream;

  @override
  Future<WorkspaceSnapshot> openWorkspace() async {
    if (openError case final error?) {
      return Future<WorkspaceSnapshot>.error(error);
    }
    return snapshots[_nextSnapshot++];
  }

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => openWorkspace();

  void notifyWorkspaceChanged() => _events.add(null);

  void disconnect(Object error) => _events.addError(error);

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

WorkspaceSnapshot _snapshot(int revision) {
  final catalog = sampleCatalogManifest();
  return WorkspaceSnapshot(
    revision: revision,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: const <Variant>[],
      sources: const <VariantDefinitionSource>[],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(<String, Object?>{
        'revision': revision,
      }),
      modules: const <EffectiveModuleState>[],
      commands: const <String>[],
      rpcMethods: const <String>[],
      studioContributions: const <String>['studio.shell'],
      generatedAt: DateTime.utc(2026, 8, 10),
    ),
    providers: const <VisualEvidenceProviderState>[],
    visualProjections: const <VisualEvidenceProjection>[],
    generatedAt: DateTime.utc(2026, 8, 10),
  );
}
