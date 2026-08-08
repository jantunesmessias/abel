/// A bounded slice of an ordered collection centered around the current
/// selection. The complete outline remains the accessible navigation model;
/// this window only bounds the expensive visual canvas DOM.
final class DevExSequenceWindow<T> {
  const DevExSequenceWindow({
    required this.items,
    required this.start,
    required this.total,
  });

  final List<T> items;
  final int start;
  final int total;

  int get endExclusive => start + items.length;
  int get before => start;
  int get after => total - endExclusive;
  bool get isVirtualized => items.length < total;
}

final class DevExSequenceWindowPolicy {
  const DevExSequenceWindowPolicy({this.maximumVisibleItems = 24})
    : assert(maximumVisibleItems > 0);

  final int maximumVisibleItems;

  DevExSequenceWindow<T> around<T>(
    List<T> items, {
    required int selectedIndex,
  }) {
    if (items.isEmpty) {
      return DevExSequenceWindow<T>(
        items: List<T>.unmodifiable(<T>[]),
        start: 0,
        total: 0,
      );
    }
    if (selectedIndex < 0 || selectedIndex >= items.length) {
      throw RangeError.range(selectedIndex, 0, items.length - 1);
    }
    if (items.length <= maximumVisibleItems) {
      return DevExSequenceWindow<T>(
        items: List<T>.unmodifiable(items),
        start: 0,
        total: items.length,
      );
    }
    final half = maximumVisibleItems ~/ 2;
    var start = selectedIndex - half;
    if (start < 0) start = 0;
    final latestStart = items.length - maximumVisibleItems;
    if (start > latestStart) start = latestStart;
    return DevExSequenceWindow<T>(
      items: List<T>.unmodifiable(
        items.sublist(start, start + maximumVisibleItems),
      ),
      start: start,
      total: items.length,
    );
  }
}
