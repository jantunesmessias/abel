import 'dart:convert';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final hostOrigin = Uri.parse('http://127.0.0.1:7367');
  final studioOrigin = Uri.parse('http://127.0.0.1:7368');

  test('grants and serves an immutable resource set atomically', () async {
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
      maxActiveResources: 4,
      maxTotalBytes: 16,
      maxResourceBytes: 8,
    );

    final handles = registry.grantByteSet(
      hostOrigin: hostOrigin,
      audienceOrigin: studioOrigin,
      inputs: <HostResourceGrantInput>[
        HostResourceGrantInput(
          bytes: utf8.encode('one'),
          mediaType: 'application/json',
          purpose: 'first',
        ),
        HostResourceGrantInput(
          bytes: utf8.encode('two'),
          mediaType: 'application/json',
          purpose: 'second',
        ),
      ],
    );

    expect(handles, hasLength(2));
    expect(handles.map((handle) => handle.uri).toSet(), hasLength(2));
    expect(registry.activeCount, 2);
    expect(registry.totalBytes, 6);
    for (final (index, handle) in handles.indexed) {
      final response = registry.serve(
        Request(
          'GET',
          handle.uri,
          headers: <String, String>{'origin': studioOrigin.origin},
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), index == 0 ? 'one' : 'two');
    }
  });

  test('quota failure publishes none of a staged resource set', () {
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
      maxActiveResources: 4,
      maxTotalBytes: 5,
      maxResourceBytes: 4,
    );

    expect(
      () => registry.grantByteSet(
        hostOrigin: hostOrigin,
        audienceOrigin: studioOrigin,
        inputs: <HostResourceGrantInput>[
          const HostResourceGrantInput(
            bytes: <int>[1, 2, 3],
            mediaType: 'application/json',
            purpose: 'first',
          ),
          const HostResourceGrantInput(
            bytes: <int>[4, 5, 6],
            mediaType: 'application/json',
            purpose: 'second',
          ),
        ],
      ),
      throwsStateError,
    );
    expect(registry.activeCount, 0);
    expect(registry.totalBytes, 0);
  });

  test('invalid later input publishes none of a staged resource set', () {
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
    );

    expect(
      () => registry.grantByteSet(
        hostOrigin: hostOrigin,
        audienceOrigin: studioOrigin,
        inputs: <HostResourceGrantInput>[
          const HostResourceGrantInput(
            bytes: <int>[1],
            mediaType: 'application/json',
            purpose: 'first',
          ),
          const HostResourceGrantInput(
            bytes: <int>[2],
            mediaType: 'application/json',
            purpose: 'second',
            classification: ArtifactClassification.sensitive,
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(registry.activeCount, 0);
    expect(registry.totalBytes, 0);
  });

  test(
    'failed replacement preserves the exact prior leases and quota',
    () async {
      final registry = HostResourceRegistry(
        clock: _FixedClock(),
        ids: _SequentialIds(),
        maxActiveResources: 2,
        maxTotalBytes: 6,
        maxResourceBytes: 6,
      );
      final previous = registry.grantByteSet(
        hostOrigin: hostOrigin,
        audienceOrigin: studioOrigin,
        inputs: <HostResourceGrantInput>[
          const HostResourceGrantInput(
            bytes: <int>[1, 2, 3],
            mediaType: 'application/json',
            purpose: 'prior',
          ),
        ],
      );
      expect(previous.single.uri.pathSegments.last, hasLength(32));

      expect(
        () => registry.replaceByteSet(
          hostOrigin: hostOrigin,
          audienceOrigin: studioOrigin,
          previous: previous,
          inputs: <HostResourceGrantInput>[
            const HostResourceGrantInput(
              bytes: <int>[1, 2, 3, 4],
              mediaType: 'application/json',
              purpose: 'next-a',
            ),
            const HostResourceGrantInput(
              bytes: <int>[5, 6, 7, 8],
              mediaType: 'application/json',
              purpose: 'next-b',
            ),
          ],
        ),
        throwsStateError,
      );
      expect(registry.activeCount, 1);
      expect(registry.totalBytes, 3);
      final response = registry.serve(
        Request(
          'GET',
          previous.single.uri,
          headers: <String, String>{'origin': studioOrigin.origin},
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.read().expand((chunk) => chunk).toList(), <int>[
        1,
        2,
        3,
      ]);
    },
  );
}

final class _FixedClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 13, 12);

  @override
  int monotonicMicroseconds() => 0;
}

final class _SequentialIds implements IdGenerator {
  var _next = 0;

  @override
  String nextId() {
    _next += 1;
    return _next.toRadixString(16).padLeft(16, '0');
  }
}
