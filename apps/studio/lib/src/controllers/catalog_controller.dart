import 'dart:async';

import 'package:studio/src/catalog/catalog_repository.dart';
import 'package:studio/src/model/catalog_view_state.dart';

final class CatalogController {
  CatalogController(this._repository);

  final CatalogRepository _repository;
  final StreamController<CatalogViewState> _changes =
      StreamController<CatalogViewState>.broadcast(sync: true);

  CatalogViewState _state = const CatalogLoading();
  int _refreshGeneration = 0;
  bool _closed = false;

  CatalogViewState get state => _state;
  Stream<CatalogViewState> get changes => _changes.stream;

  Future<void> refresh() async {
    if (_closed) {
      throw StateError('CatalogController is closed');
    }

    final generation = ++_refreshGeneration;
    final previous = _state;
    _publish(
      previous is CatalogContent
          ? previous.copyWith(isRefreshing: true)
          : const CatalogLoading(),
    );

    try {
      final manifest = await _repository.loadCatalog();
      if (!_canPublish(generation)) return;
      _publish(
        manifest.journeys.isEmpty && manifest.scenarios.isEmpty
            ? const CatalogEmpty()
            : CatalogContent(manifest: manifest),
      );
    } on Object catch (error) {
      if (!_canPublish(generation)) return;
      _publish(
        previous is CatalogContent
            ? previous.copyWith(isRefreshing: false, isStale: true)
            : CatalogFailure('$error'),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _refreshGeneration++;
    await _changes.close();
  }

  bool _canPublish(int generation) =>
      !_closed && generation == _refreshGeneration;

  void _publish(CatalogViewState next) {
    if (_closed) return;
    _state = next;
    _changes.add(next);
  }
}
