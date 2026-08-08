enum ViewportClass { compact, medium, wide, expansive }

enum ExplorerPresentation { drawer, persistent }

enum InspectorPresentation { sheet, stacked, rail }

final class WorkspaceLayout {
  const WorkspaceLayout({
    required this.viewportClass,
    required this.explorer,
    required this.inspector,
  });

  final ViewportClass viewportClass;
  final ExplorerPresentation explorer;
  final InspectorPresentation inspector;
}

/// Canonical responsive policy shared by every Abel Studio surface.
///
/// Width and height are logical pixels. Callers render the returned pattern;
/// they do not reproduce breakpoint arithmetic locally.
final class WorkspaceLayoutPolicy {
  const WorkspaceLayoutPolicy({
    this.mediumWidth = 576,
    this.wideWidth = 832,
    this.expansiveWidth = 1280,
    this.inspectorRailWidth = 1072,
    this.inspectorStackWidth = 832,
    this.minimumStackHeight = 0,
  }) : assert(mediumWidth > 0),
       assert(wideWidth > mediumWidth),
       assert(expansiveWidth > wideWidth),
       assert(inspectorStackWidth >= mediumWidth),
       assert(inspectorRailWidth >= wideWidth),
       assert(minimumStackHeight >= 0);

  final double mediumWidth;
  final double wideWidth;
  final double expansiveWidth;
  final double inspectorRailWidth;
  final double inspectorStackWidth;
  final double minimumStackHeight;

  WorkspaceLayout resolve({required double width, required double height}) {
    if (!width.isFinite || width < 0 || !height.isFinite || height < 0) {
      throw ArgumentError(
        'Viewport dimensions must be finite and non-negative',
      );
    }
    final viewportClass = width >= expansiveWidth
        ? ViewportClass.expansive
        : width >= wideWidth
        ? ViewportClass.wide
        : width >= mediumWidth
        ? ViewportClass.medium
        : ViewportClass.compact;
    final inspector = width >= inspectorRailWidth
        ? InspectorPresentation.rail
        : width >= inspectorStackWidth && height >= minimumStackHeight
        ? InspectorPresentation.stacked
        : InspectorPresentation.sheet;
    return WorkspaceLayout(
      viewportClass: viewportClass,
      explorer: width >= wideWidth
          ? ExplorerPresentation.persistent
          : ExplorerPresentation.drawer,
      inspector: inspector,
    );
  }
}
