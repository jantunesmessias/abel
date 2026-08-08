import 'dart:math' as math;

/// An immutable point in either world or viewport coordinates.
final class SpatialPoint {
  factory SpatialPoint(double x, double y) {
    _finite(x, 'x');
    _finite(y, 'y');
    return SpatialPoint._(x, y);
  }

  const SpatialPoint._(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is SpatialPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'SpatialPoint($x, $y)';
}

/// An immutable axis-aligned rectangle.
final class SpatialRect {
  factory SpatialRect.fromLTWH(
    double left,
    double top,
    double width,
    double height,
  ) {
    _finite(left, 'left');
    _finite(top, 'top');
    _nonNegativeFinite(width, 'width');
    _nonNegativeFinite(height, 'height');
    _finite(left + width, 'right');
    _finite(top + height, 'bottom');
    return SpatialRect._(left, top, width, height);
  }

  const SpatialRect._(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  bool get isEmpty => width == 0 || height == 0;
  SpatialPoint get center => SpatialPoint(left + width / 2, top + height / 2);

  bool intersects(SpatialRect other) =>
      left <= other.right &&
      right >= other.left &&
      top <= other.bottom &&
      bottom >= other.top;

  SpatialRect inflated(double amount) {
    _nonNegativeFinite(amount, 'amount');
    return SpatialRect.fromLTWH(
      left - amount,
      top - amount,
      width + amount * 2,
      height + amount * 2,
    );
  }

  SpatialRect union(SpatialRect other) {
    final nextLeft = math.min(left, other.left);
    final nextTop = math.min(top, other.top);
    final nextRight = math.max(right, other.right);
    final nextBottom = math.max(bottom, other.bottom);
    return SpatialRect.fromLTWH(
      nextLeft,
      nextTop,
      nextRight - nextLeft,
      nextBottom - nextTop,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpatialRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SpatialRect($left, $top, $width, $height)';
}

/// A viewport over world coordinates.
///
/// [worldOrigin] is the world point shown at viewport coordinate `(0, 0)`.
/// Width and height are viewport pixels; [zoom] is viewport pixels per world
/// unit.
final class SpatialViewport {
  factory SpatialViewport({
    required SpatialPoint worldOrigin,
    required double width,
    required double height,
    required double zoom,
  }) {
    _positiveFinite(width, 'width');
    _positiveFinite(height, 'height');
    _positiveFinite(zoom, 'zoom');
    return SpatialViewport._(
      worldOrigin: worldOrigin,
      width: width,
      height: height,
      zoom: zoom,
    );
  }

  const SpatialViewport._({
    required this.worldOrigin,
    required this.width,
    required this.height,
    required this.zoom,
  });

  final SpatialPoint worldOrigin;
  final double width;
  final double height;
  final double zoom;

  SpatialRect get worldBounds => SpatialRect.fromLTWH(
    worldOrigin.x,
    worldOrigin.y,
    width / zoom,
    height / zoom,
  );

  SpatialPoint worldToViewport(SpatialPoint point) => SpatialPoint(
    (point.x - worldOrigin.x) * zoom,
    (point.y - worldOrigin.y) * zoom,
  );

  SpatialPoint viewportToWorld(SpatialPoint point) => SpatialPoint(
    worldOrigin.x + point.x / zoom,
    worldOrigin.y + point.y / zoom,
  );

  SpatialRect worldToViewportRect(SpatialRect rect) => SpatialRect.fromLTWH(
    (rect.left - worldOrigin.x) * zoom,
    (rect.top - worldOrigin.y) * zoom,
    rect.width * zoom,
    rect.height * zoom,
  );

  SpatialRect viewportToWorldRect(SpatialRect rect) => SpatialRect.fromLTWH(
    worldOrigin.x + rect.left / zoom,
    worldOrigin.y + rect.top / zoom,
    rect.width / zoom,
    rect.height / zoom,
  );

  SpatialViewport pannedBy({
    required double worldDeltaX,
    required double worldDeltaY,
  }) {
    _finite(worldDeltaX, 'worldDeltaX');
    _finite(worldDeltaY, 'worldDeltaY');
    return SpatialViewport(
      worldOrigin: SpatialPoint(
        worldOrigin.x + worldDeltaX,
        worldOrigin.y + worldDeltaY,
      ),
      width: width,
      height: height,
      zoom: zoom,
    );
  }

  /// Changes zoom while preserving the world point under [viewportAnchor].
  SpatialViewport zoomedAt({
    required double zoom,
    required SpatialPoint viewportAnchor,
  }) {
    _positiveFinite(zoom, 'zoom');
    final worldAnchor = viewportToWorld(viewportAnchor);
    return SpatialViewport(
      worldOrigin: SpatialPoint(
        worldAnchor.x - viewportAnchor.x / zoom,
        worldAnchor.y - viewportAnchor.y / zoom,
      ),
      width: width,
      height: height,
      zoom: zoom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpatialViewport &&
      other.worldOrigin == worldOrigin &&
      other.width == width &&
      other.height == height &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(worldOrigin, width, height, zoom);
}

/// A domain-independent item placed in world coordinates.
final class SpatialItem {
  SpatialItem({required this.id, required this.bounds}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (bounds.isEmpty) {
      throw ArgumentError.value(bounds, 'bounds', 'must have positive area');
    }
  }

  final String id;
  final SpatialRect bounds;
}

/// An edge between two existing spatial items.
final class SpatialEdge {
  SpatialEdge({required this.id, required this.fromId, required this.toId}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (fromId.trim().isEmpty) {
      throw ArgumentError.value(fromId, 'fromId', 'must not be empty');
    }
    if (toId.trim().isEmpty) {
      throw ArgumentError.value(toId, 'toId', 'must not be empty');
    }
  }

  final String id;
  final String fromId;
  final String toId;
}

/// An edge with exactly one endpoint retained by a spatial window.
///
/// Both endpoint IDs come from the original edge. No synthetic endpoint or
/// geometry is introduced; a renderer can choose how to represent the
/// boundary explicitly.
final class SpatialBoundaryEdge {
  const SpatialBoundaryEdge._({
    required this.edge,
    required this.insideEndpointId,
    required this.outsideEndpointId,
  });

  final SpatialEdge edge;
  final String insideEndpointId;
  final String outsideEndpointId;
}

/// Immutable spatial data indexed once and queried by many viewports.
///
/// Input order is the canonical stable order for items and edges.
final class SpatialIndex {
  SpatialIndex({
    required Iterable<SpatialItem> items,
    Iterable<SpatialEdge> edges = const <SpatialEdge>[],
  }) {
    final itemCopy = List<SpatialItem>.of(items);
    final edgeCopy = List<SpatialEdge>.of(edges);
    final itemsById = <String, _IndexedSpatialItem>{};
    SpatialRect? contentBounds;
    for (final (order, item) in itemCopy.indexed) {
      if (itemsById.containsKey(item.id)) {
        throw ArgumentError.value(item.id, 'items', 'contains duplicate ID');
      }
      final indexed = _IndexedSpatialItem(order: order, item: item);
      itemsById[item.id] = indexed;
      contentBounds = contentBounds == null
          ? item.bounds
          : contentBounds.union(item.bounds);
    }

    final edgeIds = <String>{};
    for (final edge in edgeCopy) {
      if (!edgeIds.add(edge.id)) {
        throw ArgumentError.value(edge.id, 'edges', 'contains duplicate ID');
      }
      if (!itemsById.containsKey(edge.fromId) ||
          !itemsById.containsKey(edge.toId)) {
        throw ArgumentError.value(
          edge.id,
          'edges',
          'references an unknown endpoint',
        );
      }
    }

    final search = itemsById.values.toList(growable: false)
      ..sort((left, right) {
        final position = left.item.bounds.left.compareTo(
          right.item.bounds.left,
        );
        return position != 0 ? position : left.order.compareTo(right.order);
      });
    _items = List<SpatialItem>.unmodifiable(itemCopy);
    _edges = List<SpatialEdge>.unmodifiable(edgeCopy);
    _itemsById = Map<String, _IndexedSpatialItem>.unmodifiable(itemsById);
    _searchByLeft = List<_IndexedSpatialItem>.unmodifiable(search);
    _contentBounds = contentBounds;
  }

  late final List<SpatialItem> _items;
  late final List<SpatialEdge> _edges;
  late final Map<String, _IndexedSpatialItem> _itemsById;
  late final List<_IndexedSpatialItem> _searchByLeft;
  late final SpatialRect? _contentBounds;

  List<SpatialItem> get items => _items;
  List<SpatialEdge> get edges => _edges;
  SpatialRect? get contentBounds => _contentBounds;
  bool get isEmpty => _items.isEmpty;

  List<int> _ordersIntersecting(SpatialRect bounds) {
    var low = 0;
    var high = _searchByLeft.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_searchByLeft[middle].item.bounds.left <= bounds.right) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final orders = <int>[];
    for (var index = 0; index < low; index += 1) {
      final candidate = _searchByLeft[index];
      if (candidate.item.bounds.intersects(bounds)) {
        orders.add(candidate.order);
      }
    }
    orders.sort();
    return orders;
  }
}

/// Policy for fitting and windowing an immutable spatial index.
final class SpatialWindowPolicy {
  SpatialWindowPolicy({
    this.overscan = 120,
    this.maximumVisibleItems = 256,
    this.maximumRenderableEdges = 512,
    this.maximumBoundaryEdges = 512,
    this.minimumZoom = 0.25,
    this.maximumZoom = 3,
    this.fitPadding = 48,
  }) {
    _nonNegativeFinite(overscan, 'overscan');
    if (maximumVisibleItems <= 0) {
      throw ArgumentError.value(
        maximumVisibleItems,
        'maximumVisibleItems',
        'must be positive',
      );
    }
    if (maximumRenderableEdges <= 0) {
      throw ArgumentError.value(
        maximumRenderableEdges,
        'maximumRenderableEdges',
        'must be positive',
      );
    }
    if (maximumBoundaryEdges <= 0) {
      throw ArgumentError.value(
        maximumBoundaryEdges,
        'maximumBoundaryEdges',
        'must be positive',
      );
    }
    _positiveFinite(minimumZoom, 'minimumZoom');
    _positiveFinite(maximumZoom, 'maximumZoom');
    if (maximumZoom < minimumZoom) {
      throw ArgumentError.value(
        maximumZoom,
        'maximumZoom',
        'must be greater than or equal to minimumZoom',
      );
    }
    _nonNegativeFinite(fitPadding, 'fitPadding');
  }

  /// Overscan in viewport pixels, converted to world units for each query.
  final double overscan;
  final int maximumVisibleItems;
  final int maximumRenderableEdges;
  final int maximumBoundaryEdges;
  final double minimumZoom;
  final double maximumZoom;
  final double fitPadding;

  SpatialViewport fitToContent({
    required SpatialIndex index,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    _positiveFinite(viewportWidth, 'viewportWidth');
    _positiveFinite(viewportHeight, 'viewportHeight');
    if (index.isEmpty) {
      return SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: viewportWidth,
        height: viewportHeight,
        zoom: 1.clamp(minimumZoom, maximumZoom).toDouble(),
      );
    }
    final availableWidth = viewportWidth - fitPadding * 2;
    final availableHeight = viewportHeight - fitPadding * 2;
    if (availableWidth <= 0 || availableHeight <= 0) {
      throw ArgumentError('fitPadding must leave positive viewport dimensions');
    }
    final content = index.contentBounds!;
    final fittedZoom = math.min(
      availableWidth / content.width,
      availableHeight / content.height,
    );
    final zoom = fittedZoom.clamp(minimumZoom, maximumZoom).toDouble();
    final visibleWorldWidth = viewportWidth / zoom;
    final visibleWorldHeight = viewportHeight / zoom;
    return SpatialViewport(
      worldOrigin: SpatialPoint(
        content.center.x - visibleWorldWidth / 2,
        content.center.y - visibleWorldHeight / 2,
      ),
      width: viewportWidth,
      height: viewportHeight,
      zoom: zoom,
    );
  }

  SpatialWindow window({
    required SpatialIndex index,
    required SpatialViewport viewport,
    String? selectedItemId,
  }) {
    if (viewport.zoom < minimumZoom || viewport.zoom > maximumZoom) {
      throw ArgumentError.value(
        viewport.zoom,
        'viewport.zoom',
        'is outside the configured zoom range',
      );
    }
    final selected = selectedItemId == null
        ? null
        : index._itemsById[selectedItemId];
    if (selectedItemId != null && selected == null) {
      throw ArgumentError.value(
        selectedItemId,
        'selectedItemId',
        'is not present in the index',
      );
    }

    final queryBounds = viewport.worldBounds.inflated(overscan / viewport.zoom);
    final visibleOrders = index._ordersIntersecting(queryBounds);
    final visibleOrderSet = visibleOrders.toSet();
    final retainedOrders = visibleOrders
        .take(maximumVisibleItems)
        .toList(growable: true);
    var selectedItemWasPreserved = false;
    if (selected != null && !retainedOrders.contains(selected.order)) {
      selectedItemWasPreserved = true;
      if (retainedOrders.length == maximumVisibleItems) {
        retainedOrders.removeLast();
      }
      retainedOrders.add(selected.order);
      retainedOrders.sort();
    }

    final retainedIds = <String>[
      for (final order in retainedOrders) index._items[order].id,
    ];
    final visibleIds = <String>[
      for (final order in retainedOrders)
        if (visibleOrderSet.contains(order)) index._items[order].id,
    ];
    final retainedIdSet = retainedIds.toSet();
    final renderableEdges = <SpatialEdge>[];
    final boundaryEdges = <SpatialBoundaryEdge>[];
    var renderableEdgeCount = 0;
    var boundaryEdgeCount = 0;
    for (final edge in index._edges) {
      final fromRetained = retainedIdSet.contains(edge.fromId);
      final toRetained = retainedIdSet.contains(edge.toId);
      if (fromRetained && toRetained) {
        renderableEdgeCount += 1;
        if (renderableEdges.length < maximumRenderableEdges) {
          renderableEdges.add(edge);
        }
      } else if (fromRetained != toRetained) {
        boundaryEdgeCount += 1;
        if (boundaryEdges.length < maximumBoundaryEdges) {
          boundaryEdges.add(
            SpatialBoundaryEdge._(
              edge: edge,
              insideEndpointId: fromRetained ? edge.fromId : edge.toId,
              outsideEndpointId: fromRetained ? edge.toId : edge.fromId,
            ),
          );
        }
      }
    }

    return SpatialWindow._(
      queryBounds: queryBounds,
      itemIds: List<String>.unmodifiable(retainedIds),
      visibleItemIds: List<String>.unmodifiable(visibleIds),
      visibleCandidateCount: visibleOrders.length,
      isTruncated: visibleIds.length < visibleOrders.length,
      selectedItemId: selectedItemId,
      selectedItemWasPreserved: selectedItemWasPreserved,
      selectedItemIsOutsideQueryBounds:
          selected != null && !visibleOrderSet.contains(selected.order),
      renderableEdges: List<SpatialEdge>.unmodifiable(renderableEdges),
      boundaryEdges: List<SpatialBoundaryEdge>.unmodifiable(boundaryEdges),
      renderableEdgeCount: renderableEdgeCount,
      boundaryEdgeCount: boundaryEdgeCount,
    );
  }
}

/// A bounded, deterministic view over a spatial index.
final class SpatialWindow {
  const SpatialWindow._({
    required this.queryBounds,
    required this.itemIds,
    required this.visibleItemIds,
    required this.visibleCandidateCount,
    required this.isTruncated,
    required this.selectedItemId,
    required this.selectedItemWasPreserved,
    required this.selectedItemIsOutsideQueryBounds,
    required this.renderableEdges,
    required this.boundaryEdges,
    required this.renderableEdgeCount,
    required this.boundaryEdgeCount,
  });

  /// IDs retained for rendering, including a forced selection when necessary.
  final List<String> itemIds;

  /// Retained IDs that actually intersect [queryBounds].
  final List<String> visibleItemIds;
  final SpatialRect queryBounds;
  final int visibleCandidateCount;
  final bool isTruncated;
  final String? selectedItemId;
  final bool selectedItemWasPreserved;
  final bool selectedItemIsOutsideQueryBounds;

  /// Edges whose original endpoints are both present in [itemIds].
  final List<SpatialEdge> renderableEdges;

  /// Total renderable edges before the deterministic edge window was applied.
  final int renderableEdgeCount;

  bool get renderableEdgesTruncated =>
      renderableEdges.length < renderableEdgeCount;

  /// Edges with one original endpoint in [itemIds] and one outside it.
  final List<SpatialBoundaryEdge> boundaryEdges;

  /// Total boundary edges before the deterministic diagnostic window.
  final int boundaryEdgeCount;

  bool get boundaryEdgesTruncated => boundaryEdges.length < boundaryEdgeCount;
}

final class _IndexedSpatialItem {
  const _IndexedSpatialItem({required this.order, required this.item});

  final int order;
  final SpatialItem item;
}

void _finite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}

void _nonNegativeFinite(double value, String name) {
  _finite(value, name);
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

void _positiveFinite(double value, String name) {
  _finite(value, name);
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}
