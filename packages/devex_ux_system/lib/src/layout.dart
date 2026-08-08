enum DevExViewportClass { compact, medium, wide, expansive }

enum DevExExplorerPresentation { drawer, persistent }

enum DevExInspectorPresentation { sheet, stacked, rail }

final class DevExWorkspaceLayout {
  const DevExWorkspaceLayout({
    required this.viewportClass,
    required this.explorer,
    required this.inspector,
  });

  final DevExViewportClass viewportClass;
  final DevExExplorerPresentation explorer;
  final DevExInspectorPresentation inspector;
}

/// Canonical responsive policy shared by every DevEx Studio surface.
///
/// Width and height are logical pixels. Callers render the returned pattern;
/// they do not reproduce breakpoint arithmetic locally.
final class DevExWorkspaceLayoutPolicy {
  const DevExWorkspaceLayoutPolicy({
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

  DevExWorkspaceLayout resolve({
    required double width,
    required double height,
  }) {
    if (!width.isFinite || width < 0 || !height.isFinite || height < 0) {
      throw ArgumentError(
        'Viewport dimensions must be finite and non-negative',
      );
    }
    final viewportClass = width >= expansiveWidth
        ? DevExViewportClass.expansive
        : width >= wideWidth
        ? DevExViewportClass.wide
        : width >= mediumWidth
        ? DevExViewportClass.medium
        : DevExViewportClass.compact;
    final inspector = width >= inspectorRailWidth
        ? DevExInspectorPresentation.rail
        : width >= inspectorStackWidth && height >= minimumStackHeight
        ? DevExInspectorPresentation.stacked
        : DevExInspectorPresentation.sheet;
    return DevExWorkspaceLayout(
      viewportClass: viewportClass,
      explorer: width >= wideWidth
          ? DevExExplorerPresentation.persistent
          : DevExExplorerPresentation.drawer,
      inspector: inspector,
    );
  }
}
