import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/controllers/studio_filters_controller.dart';
import 'package:devex_studio/src/model/studio_filters.dart';
import 'package:test/test.dart';

void main() {
  test('applies and clears filters synchronously in pure Dart', () async {
    final controller = StudioFiltersController();
    final changes = <StudioFilters>[];
    final subscription = controller.changes.listen(changes.add);

    expect(controller.state.isEmpty, isTrue);
    controller
      ..setQuery('  launch')
      ..selectApplication('sample-app')
      ..selectVariant(VariantId('phone.light'))
      ..selectProvider(ModuleId('evidence.auto-preview'))
      ..selectStatus(VisualEvidenceStatus.collected)
      ..selectFreshness(EvidenceFreshness.fresh)
      ..selectFidelity(RuntimeFidelity.structural);

    expect(controller.state.query, 'launch');
    expect(controller.state.applicationId, 'sample-app');
    expect(controller.state.variantId, VariantId('phone.light'));
    expect(controller.state.providerId, ModuleId('evidence.auto-preview'));
    expect(controller.state.status, VisualEvidenceStatus.collected);
    expect(controller.state.freshness, EvidenceFreshness.fresh);
    expect(controller.state.fidelity, RuntimeFidelity.structural);
    expect(changes, hasLength(7));

    controller
      ..selectVariant(null)
      ..selectProvider(null);
    expect(controller.state.variantId, isNull);
    expect(controller.state.providerId, isNull);

    controller.clear();
    expect(controller.state.isEmpty, isTrue);

    await subscription.cancel();
    await controller.close();
  });

  test('rejects transitions after disposal', () async {
    final controller = StudioFiltersController();
    await controller.close();

    expect(() => controller.setQuery('late'), throwsStateError);
  });
}
