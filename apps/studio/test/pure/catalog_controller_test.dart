import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/catalog_repository.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/controllers/catalog_controller.dart';
import 'package:studio/src/model/catalog_view_state.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loads catalog and preserves prior content as stale on failure',
    () async {
      final manifest = sampleCatalogManifest();
      var shouldFail = false;
      final controller = CatalogController(
        _CallbackCatalogRepository(() async {
          if (shouldFail) throw StateError('host unavailable');
          return manifest;
        }),
      );
      final changes = <CatalogViewState>[];
      final subscription = controller.changes.listen(changes.add);

      await controller.refresh();
      expect(controller.state, isA<CatalogContent>());

      shouldFail = true;
      await controller.refresh();

      expect(changes[changes.length - 2], isA<CatalogContent>());
      expect(
        (changes[changes.length - 2] as CatalogContent).isRefreshing,
        isTrue,
      );
      final stale = controller.state as CatalogContent;
      expect(stale.manifest, same(manifest));
      expect(stale.isRefreshing, isFalse);
      expect(stale.isStale, isTrue);

      await subscription.cancel();
      await controller.close();
    },
  );

  test('ignores an older refresh that completes after a newer one', () async {
    final first = Completer<CatalogManifest>();
    final second = Completer<CatalogManifest>();
    var call = 0;
    final controller = CatalogController(
      _CallbackCatalogRepository(
        () => call++ == 0 ? first.future : second.future,
      ),
    );

    final olderRefresh = controller.refresh();
    final newerRefresh = controller.refresh();
    final expected = sampleCatalogManifest();
    second.complete(expected);
    await newerRefresh;
    first.complete(_emptyCatalog());
    await olderRefresh;

    final content = controller.state as CatalogContent;
    expect(content.manifest, same(expected));
    await controller.close();
  });

  test(
    'reports an initial repository failure without renderer types',
    () async {
      final controller = CatalogController(
        _CallbackCatalogRepository(
          () => Future<CatalogManifest>.error(StateError('offline')),
        ),
      );

      await controller.refresh();

      final failure = controller.state as CatalogFailure;
      expect(failure.message, contains('offline'));
      await controller.close();
    },
  );
}

final class _CallbackCatalogRepository implements CatalogRepository {
  const _CallbackCatalogRepository(this._load);

  final Future<CatalogManifest> Function() _load;

  @override
  Future<CatalogManifest> loadCatalog() => _load();
}

CatalogManifest _emptyCatalog() {
  final sample = sampleCatalogManifest();
  return CatalogManifest(
    distribution: sample.distribution,
    layout: sample.layout,
    workspace: sample.workspace,
    applications: sample.applications,
    journeys: const <Journey>[],
    scenarios: const <Scenario>[],
    transitions: const <Transition>[],
  );
}
