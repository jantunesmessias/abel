import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/model/studio_filters.dart';

final class StudioFiltersController {
  final StreamController<StudioFilters> _changes =
      StreamController<StudioFilters>.broadcast(sync: true);

  StudioFilters _state = const StudioFilters();
  bool _closed = false;

  StudioFilters get state => _state;
  Stream<StudioFilters> get changes => _changes.stream;

  void setQuery(String value) {
    _publish(_state.copyWith(query: value.trimLeft()));
  }

  void selectApplication(String? id) {
    _publish(
      id == null
          ? _state.copyWith(clearApplication: true)
          : _state.copyWith(applicationId: id),
    );
  }

  void selectVariant(VariantId? id) {
    _publish(
      id == null
          ? _state.copyWith(clearVariant: true)
          : _state.copyWith(variantId: id),
    );
  }

  void selectProvider(ModuleId? id) {
    _publish(
      id == null
          ? _state.copyWith(clearProvider: true)
          : _state.copyWith(providerId: id),
    );
  }

  void selectStatus(VisualEvidenceStatus? value) {
    _publish(
      value == null
          ? _state.copyWith(clearStatus: true)
          : _state.copyWith(status: value),
    );
  }

  void selectFreshness(EvidenceFreshness? value) {
    _publish(
      value == null
          ? _state.copyWith(clearFreshness: true)
          : _state.copyWith(freshness: value),
    );
  }

  void selectFidelity(RuntimeFidelity? value) {
    _publish(
      value == null
          ? _state.copyWith(clearFidelity: true)
          : _state.copyWith(fidelity: value),
    );
  }

  void clear() {
    _publish(const StudioFilters());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _changes.close();
  }

  void _publish(StudioFilters next) {
    if (_closed) {
      throw StateError('StudioFiltersController is closed');
    }
    _state = next;
    _changes.add(next);
  }
}
