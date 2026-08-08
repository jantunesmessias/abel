import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  const service = EvidenceComparisonService();

  test(
    'visual comparison uses normalized RGBA pixels and versioned policy',
    () {
      final expected = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[10, 20, 30, 255, 40, 50, 60, 255],
        compressionLevel: 1,
      );
      final samePixelsDifferentEncoding = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[10, 20, 30, 255, 40, 50, 60, 255],
        compressionLevel: 9,
        filter: 1,
      );
      final changed = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[10, 20, 30, 255, 90, 50, 60, 255],
      );
      final policy = VisualComparisonPolicy(
        id: 'visual-v1',
        maxChannelDelta: 2,
        maxChangedPixelRatio: 0,
      );

      final equal = service.compareVisual(
        expected: expected,
        actual: samePixelsDifferentEncoding,
        policy: policy,
      );
      expect(equal.passed, isTrue);
      expect(equal.changedUnits, 0);
      expect(equal.expectedDigest, isNot(equal.actualDigest));

      final difference = service.compareVisual(
        expected: expected,
        actual: changed,
        policy: policy,
      );
      expect(difference.passed, isFalse);
      expect(difference.changedUnits, 1);
      expect(difference.metrics['changedPixelRatio'], 0.5);
    },
  );

  test('semantic comparison can ignore bounds but detects node changes', () {
    List<int> snapshot(List<Map<String, Object?>> nodes) => utf8.encode(
      '${const JcsCanonicalizer().canonicalize(<String, Object?>{'schemaVersion': 1, 'kind': 'AndroidSemanticsSnapshot', 'privacy': 'hashedTextV1', 'nodes': nodes})}\n',
    );
    final expected = snapshot(<Map<String, Object?>>[
      <String, Object?>{
        'sequence': 0,
        'textDigest': Digest.semantic('one').value,
        'bounds': '[0,0][1,1]',
      },
    ]);
    final moved = snapshot(<Map<String, Object?>>[
      <String, Object?>{
        'sequence': 0,
        'textDigest': Digest.semantic('one').value,
        'bounds': '[2,2][3,3]',
      },
    ]);
    final changed = snapshot(<Map<String, Object?>>[
      <String, Object?>{
        'sequence': 0,
        'textDigest': Digest.semantic('two').value,
        'bounds': '[2,2][3,3]',
      },
    ]);
    final policy = SemanticComparisonPolicy(
      id: 'semantic-v1',
      maxChangedNodes: 0,
      ignoreBounds: true,
    );
    expect(
      service
          .compareSemantic(expected: expected, actual: moved, policy: policy)
          .passed,
      isTrue,
    );
    expect(
      service
          .compareSemantic(expected: expected, actual: changed, policy: policy)
          .passed,
      isFalse,
    );
  });
}
