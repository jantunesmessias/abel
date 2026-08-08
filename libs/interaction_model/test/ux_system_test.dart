import 'package:interaction_model/interaction_model.dart';
import 'package:test/test.dart';

void main() {
  const policy = WorkspaceLayoutPolicy();

  test('resolves one canonical workspace composition per viewport', () {
    final compact = policy.resolve(width: 390, height: 844);
    expect(compact.viewportClass, ViewportClass.compact);
    expect(compact.explorer, ExplorerPresentation.drawer);
    expect(compact.inspector, InspectorPresentation.sheet);

    final medium = policy.resolve(width: 700, height: 700);
    expect(medium.viewportClass, ViewportClass.medium);
    expect(medium.inspector, InspectorPresentation.sheet);

    final stacked = policy.resolve(width: 900, height: 700);
    expect(stacked.viewportClass, ViewportClass.wide);
    expect(stacked.inspector, InspectorPresentation.stacked);

    final wide = policy.resolve(width: 1100, height: 800);
    expect(wide.explorer, ExplorerPresentation.persistent);
    expect(wide.inspector, InspectorPresentation.rail);
  });

  test('minimum stacked height can be configured by the host surface', () {
    const heightConstrainedPolicy = WorkspaceLayoutPolicy(
      minimumStackHeight: 560,
    );
    expect(
      heightConstrainedPolicy.resolve(width: 900, height: 500).inspector,
      InspectorPresentation.sheet,
    );
  });

  test('interaction and motion policies retain accessibility invariants', () {
    const interaction = InteractionPolicy();
    expect(interaction.minimumTarget(InputModality.touch), 48);
    expect(interaction.minimumTarget(InputModality.keyboard), 48);

    const motion = MotionPolicy();
    expect(motion.resolve(motion.standard, reduceMotion: true), Duration.zero);
    expect(
      motion.resolve(motion.standard, reduceMotion: false),
      const Duration(milliseconds: 180),
    );
  });

  test('visual canvas window remains bounded around deep selections', () {
    final scenarios = List<int>.generate(10000, (index) => index);
    const policy = SequenceWindowPolicy(maximumVisibleItems: 24);

    final middle = policy.around(scenarios, selectedIndex: 5000);
    expect(middle.items, hasLength(24));
    expect(middle.items, contains(5000));
    expect(middle.before + middle.items.length + middle.after, 10000);
    expect(middle.isVirtualized, isTrue);

    final first = policy.around(scenarios, selectedIndex: 0);
    expect(first.start, 0);
    expect(first.items.first, 0);

    final last = policy.around(scenarios, selectedIndex: 9999);
    expect(last.endExclusive, 10000);
    expect(last.items.last, 9999);
  });
}
