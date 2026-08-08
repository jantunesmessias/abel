import 'package:interaction_model/interaction_model.dart';
import 'package:test/test.dart';

void main() {
  group('spatial geometry', () {
    test('transforms world and viewport coordinates through pan and zoom', () {
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(100, 50),
        width: 800,
        height: 600,
        zoom: 2,
      );

      expect(viewport.worldBounds, SpatialRect.fromLTWH(100, 50, 400, 300));
      expect(
        viewport.worldToViewport(SpatialPoint(110, 60)),
        SpatialPoint(20, 20),
      );
      expect(
        viewport.viewportToWorld(SpatialPoint(20, 20)),
        SpatialPoint(110, 60),
      );
      expect(
        viewport.worldToViewportRect(SpatialRect.fromLTWH(110, 60, 20, 10)),
        SpatialRect.fromLTWH(20, 20, 40, 20),
      );

      final panned = viewport.pannedBy(worldDeltaX: 25, worldDeltaY: -10);
      expect(panned.worldOrigin, SpatialPoint(125, 40));

      final anchor = SpatialPoint(400, 300);
      final worldUnderAnchor = viewport.viewportToWorld(anchor);
      final zoomed = viewport.zoomedAt(zoom: 1, viewportAnchor: anchor);
      expect(zoomed.viewportToWorld(anchor), worldUnderAnchor);
    });

    test('rejects non-finite coordinates and invalid dimensions or zoom', () {
      expect(() => SpatialPoint(double.nan, 0), throwsArgumentError);
      expect(() => SpatialRect.fromLTWH(0, 0, -1, 1), throwsArgumentError);
      expect(
        () => SpatialRect.fromLTWH(0, 0, 1, double.infinity),
        throwsArgumentError,
      );
      expect(
        () => SpatialRect.fromLTWH(double.maxFinite, 0, double.maxFinite, 1),
        throwsArgumentError,
      );
      expect(
        () =>
            SpatialItem(id: 'empty', bounds: SpatialRect.fromLTWH(0, 0, 0, 10)),
        throwsArgumentError,
      );
      expect(
        () => SpatialViewport(
          worldOrigin: SpatialPoint(0, 0),
          width: 0,
          height: 100,
          zoom: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SpatialViewport(
          worldOrigin: SpatialPoint(0, 0),
          width: 100,
          height: 100,
          zoom: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => SpatialWindowPolicy(maximumVisibleItems: 0),
        throwsArgumentError,
      );
      expect(
        () => SpatialWindowPolicy(maximumRenderableEdges: 0),
        throwsArgumentError,
      );
      expect(
        () => SpatialWindowPolicy(maximumBoundaryEdges: 0),
        throwsArgumentError,
      );
      expect(
        () => SpatialWindowPolicy(minimumZoom: 2, maximumZoom: 1),
        throwsArgumentError,
      );
    });
  });

  group('fit to content', () {
    test('centers content and respects viewport-pixel padding', () {
      final index = SpatialIndex(
        items: <SpatialItem>[
          _item('a', 0, 0, 100, 100),
          _item('b', 300, 100, 100, 100),
        ],
      );
      final policy = SpatialWindowPolicy(
        fitPadding: 100,
        minimumZoom: 0.1,
        maximumZoom: 10,
      );

      final viewport = policy.fitToContent(
        index: index,
        viewportWidth: 1000,
        viewportHeight: 600,
      );

      expect(viewport.zoom, 2);
      expect(viewport.worldOrigin, SpatialPoint(-50, -50));
      expect(
        viewport.worldToViewport(SpatialPoint(0, 0)),
        SpatialPoint(100, 100),
      );
      expect(
        viewport.worldToViewport(SpatialPoint(400, 200)),
        SpatialPoint(900, 500),
      );
    });

    test('returns a deterministic neutral viewport for empty content', () {
      final policy = SpatialWindowPolicy(minimumZoom: 0.25, maximumZoom: 0.75);
      final viewport = policy.fitToContent(
        index: SpatialIndex(items: const <SpatialItem>[]),
        viewportWidth: 800,
        viewportHeight: 600,
      );

      expect(viewport.worldOrigin, SpatialPoint(0, 0));
      expect(viewport.zoom, 0.75);
    });
  });

  group('spatial window', () {
    test('uses overscan and retains stable input order', () {
      final index = SpatialIndex(
        items: <SpatialItem>[
          _item('third', 80, 0, 10, 10),
          _item('first', 0, 0, 10, 10),
          _item('outside', 121, 0, 10, 10),
          _item('second', 40, 0, 10, 10),
        ],
      );
      final policy = SpatialWindowPolicy(
        overscan: 20,
        maximumVisibleItems: 10,
        minimumZoom: 0.5,
        maximumZoom: 2,
      );
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: 100,
        height: 100,
        zoom: 1,
      );

      final first = policy.window(index: index, viewport: viewport);
      final second = policy.window(index: index, viewport: viewport);

      expect(first.itemIds, <String>['third', 'first', 'second']);
      expect(second.itemIds, first.itemIds);
      expect(first.visibleCandidateCount, 3);
      expect(first.isTruncated, isFalse);
    });

    test('preserves a selected item outside the viewport within the limit', () {
      final index = SpatialIndex(
        items: <SpatialItem>[
          _item('visible-1', 0, 0, 10, 10),
          _item('visible-2', 20, 0, 10, 10),
          _item('visible-3', 40, 0, 10, 10),
          _item('selected', 1000, 1000, 10, 10),
        ],
      );
      final policy = SpatialWindowPolicy(overscan: 0, maximumVisibleItems: 3);
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: 100,
        height: 100,
        zoom: 1,
      );

      final window = policy.window(
        index: index,
        viewport: viewport,
        selectedItemId: 'selected',
      );

      expect(window.itemIds, <String>['visible-1', 'visible-2', 'selected']);
      expect(window.visibleItemIds, <String>['visible-1', 'visible-2']);
      expect(window.itemIds, hasLength(3));
      expect(window.selectedItemWasPreserved, isTrue);
      expect(window.selectedItemIsOutsideQueryBounds, isTrue);
      expect(window.isTruncated, isTrue);
    });

    test('separates renderable and boundary edges without fake endpoints', () {
      final index = SpatialIndex(
        items: <SpatialItem>[
          _item('a', 0, 0, 10, 10),
          _item('b', 20, 0, 10, 10),
          _item('c', 1000, 0, 10, 10),
        ],
        edges: <SpatialEdge>[
          SpatialEdge(id: 'ab', fromId: 'a', toId: 'b'),
          SpatialEdge(id: 'bc', fromId: 'b', toId: 'c'),
          SpatialEdge(id: 'ca', fromId: 'c', toId: 'a'),
        ],
      );
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: 100,
        height: 100,
        zoom: 1,
      );

      final window = SpatialWindowPolicy(
        overscan: 0,
      ).window(index: index, viewport: viewport);

      expect(window.renderableEdges.map((edge) => edge.id), <String>['ab']);
      expect(window.boundaryEdges.map((edge) => edge.edge.id), <String>[
        'bc',
        'ca',
      ]);
      expect(window.boundaryEdges.first.insideEndpointId, 'b');
      expect(window.boundaryEdges.first.outsideEndpointId, 'c');
      expect(window.boundaryEdges.last.insideEndpointId, 'a');
      expect(window.boundaryEdges.last.outsideEndpointId, 'c');
      expect(window.renderableEdgeCount, 1);
      expect(window.boundaryEdgeCount, 2);
      expect(window.renderableEdgesTruncated, isFalse);
      expect(window.boundaryEdgesTruncated, isFalse);
    });

    test('bounds rendered and boundary edge materialization explicitly', () {
      final items = <SpatialItem>[
        for (var index = 0; index < 12; index += 1)
          _item('item-$index', index < 6 ? index * 10 : 1000 + index, 0, 8, 8),
      ];
      final edges = <SpatialEdge>[
        for (var from = 0; from < 6; from += 1)
          for (var to = 0; to < 6; to += 1)
            if (from != to)
              SpatialEdge(
                id: 'inside-$from-$to',
                fromId: 'item-$from',
                toId: 'item-$to',
              ),
        for (var inside = 0; inside < 6; inside += 1)
          for (var outside = 6; outside < 12; outside += 1)
            SpatialEdge(
              id: 'boundary-$inside-$outside',
              fromId: 'item-$inside',
              toId: 'item-$outside',
            ),
      ];
      final window =
          SpatialWindowPolicy(
            overscan: 0,
            maximumVisibleItems: 6,
            maximumRenderableEdges: 7,
            maximumBoundaryEdges: 9,
          ).window(
            index: SpatialIndex(items: items, edges: edges),
            viewport: SpatialViewport(
              worldOrigin: SpatialPoint(0, 0),
              width: 60,
              height: 20,
              zoom: 1,
            ),
          );

      expect(window.renderableEdgeCount, 30);
      expect(window.renderableEdges, hasLength(7));
      expect(window.renderableEdgesTruncated, isTrue);
      expect(window.boundaryEdgeCount, 36);
      expect(window.boundaryEdges, hasLength(9));
      expect(window.boundaryEdgesTruncated, isTrue);
      expect(window.renderableEdges.map((edge) => edge.id), <String>[
        'inside-0-1',
        'inside-0-2',
        'inside-0-3',
        'inside-0-4',
        'inside-0-5',
        'inside-1-0',
        'inside-1-2',
      ]);
    });

    test('bounds ten thousand items and remains deterministic', () {
      final items = <SpatialItem>[
        for (var row = 0; row < 100; row += 1)
          for (var column = 0; column < 100; column += 1)
            _item('item-${row * 100 + column}', column * 10, row * 10, 8, 8),
      ];
      final index = SpatialIndex(items: items);
      final policy = SpatialWindowPolicy(overscan: 0, maximumVisibleItems: 64);
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: 100,
        height: 100,
        zoom: 1,
      );

      final first = policy.window(
        index: index,
        viewport: viewport,
        selectedItemId: 'item-9999',
      );
      final second = policy.window(
        index: index,
        viewport: viewport,
        selectedItemId: 'item-9999',
      );

      expect(first.visibleCandidateCount, 121);
      expect(first.itemIds, hasLength(64));
      expect(first.itemIds, contains('item-9999'));
      expect(first.itemIds, second.itemIds);
      expect(first.visibleItemIds, second.visibleItemIds);
      expect(first.isTruncated, isTrue);
    });

    test('rejects duplicate IDs, missing endpoints, and unknown selection', () {
      expect(
        () => SpatialIndex(
          items: <SpatialItem>[
            _item('same', 0, 0, 10, 10),
            _item('same', 20, 0, 10, 10),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => SpatialIndex(
          items: <SpatialItem>[_item('a', 0, 0, 10, 10)],
          edges: <SpatialEdge>[
            SpatialEdge(id: 'missing', fromId: 'a', toId: 'b'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => SpatialIndex(
          items: <SpatialItem>[
            _item('a', 0, 0, 10, 10),
            _item('b', 20, 0, 10, 10),
          ],
          edges: <SpatialEdge>[
            SpatialEdge(id: 'same', fromId: 'a', toId: 'b'),
            SpatialEdge(id: 'same', fromId: 'b', toId: 'a'),
          ],
        ),
        throwsArgumentError,
      );

      final index = SpatialIndex(
        items: <SpatialItem>[_item('a', 0, 0, 10, 10)],
      );
      final viewport = SpatialViewport(
        worldOrigin: SpatialPoint(0, 0),
        width: 100,
        height: 100,
        zoom: 1,
      );
      expect(
        () => SpatialWindowPolicy().window(
          index: index,
          viewport: viewport,
          selectedItemId: 'missing',
        ),
        throwsArgumentError,
      );
    });
  });
}

SpatialItem _item(String id, num left, num top, num width, num height) =>
    SpatialItem(
      id: id,
      bounds: SpatialRect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
    );
