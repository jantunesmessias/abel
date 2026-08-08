import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';

import 'png_capture_inspector.dart';

final class EvidenceComparisonService {
  const EvidenceComparisonService({
    this.pngInspector = const PngCaptureInspector(),
  });

  final PngCaptureInspector pngInspector;

  EvidenceComparisonReport compareVisual({
    required List<int> expected,
    required List<int> actual,
    required VisualComparisonPolicy policy,
  }) {
    final left = pngInspector.inspect(expected);
    final right = pngInspector.inspect(actual);
    if (left.width != right.width || left.height != right.height) {
      final units = left.width * left.height > right.width * right.height
          ? left.width * left.height
          : right.width * right.height;
      return EvidenceComparisonReport(
        comparisonKind: 'visual',
        expectedDigest: Digest.bytes(expected),
        actualDigest: Digest.bytes(actual),
        policyDigest: policy.digest,
        passed: false,
        comparedUnits: units,
        changedUnits: units,
        metrics: <String, Object?>{
          'dimensionMismatch': true,
          'expectedWidth': left.width,
          'expectedHeight': left.height,
          'actualWidth': right.width,
          'actualHeight': right.height,
          'changedPixelRatio': 1.0,
          'maxObservedChannelDelta': 255,
        },
      );
    }
    final expectedPixels = left.rgbaBytes.toList();
    final actualPixels = right.rgbaBytes.toList();
    var changed = 0;
    var maxDelta = 0;
    final pixels = left.width * left.height;
    for (var pixel = 0; pixel < pixels; pixel += 1) {
      var pixelChanged = false;
      for (var channel = 0; channel < 4; channel += 1) {
        final offset = pixel * 4 + channel;
        final delta = (expectedPixels[offset] - actualPixels[offset]).abs();
        if (delta > maxDelta) maxDelta = delta;
        if (delta > policy.maxChannelDelta) pixelChanged = true;
      }
      if (pixelChanged) changed += 1;
    }
    final ratio = pixels == 0 ? 0.0 : changed / pixels;
    return EvidenceComparisonReport(
      comparisonKind: 'visual',
      expectedDigest: Digest.bytes(expected),
      actualDigest: Digest.bytes(actual),
      policyDigest: policy.digest,
      passed: ratio <= policy.maxChangedPixelRatio,
      comparedUnits: pixels,
      changedUnits: changed,
      metrics: <String, Object?>{
        'dimensionMismatch': false,
        'width': left.width,
        'height': left.height,
        'changedPixelRatio': ratio,
        'maxObservedChannelDelta': maxDelta,
      },
    );
  }

  EvidenceComparisonReport compareSemantic({
    required List<int> expected,
    required List<int> actual,
    required SemanticComparisonPolicy policy,
  }) {
    final left = _semanticNodes(expected, 'expected');
    final right = _semanticNodes(actual, 'actual');
    final compared = left.length > right.length ? left.length : right.length;
    var changed = 0;
    for (var index = 0; index < compared; index += 1) {
      if (index >= left.length || index >= right.length) {
        changed += 1;
        continue;
      }
      final leftNode = Map<String, Object?>.of(left[index]);
      final rightNode = Map<String, Object?>.of(right[index]);
      if (policy.ignoreBounds) {
        leftNode.remove('bounds');
        rightNode.remove('bounds');
      }
      if (const JcsCanonicalizer().canonicalize(leftNode) !=
          const JcsCanonicalizer().canonicalize(rightNode)) {
        changed += 1;
      }
    }
    return EvidenceComparisonReport(
      comparisonKind: 'semantic',
      expectedDigest: Digest.bytes(expected),
      actualDigest: Digest.bytes(actual),
      policyDigest: policy.digest,
      passed: changed <= policy.maxChangedNodes,
      comparedUnits: compared,
      changedUnits: changed,
      metrics: <String, Object?>{
        'expectedNodes': left.length,
        'actualNodes': right.length,
        'ignoreBounds': policy.ignoreBounds,
      },
    );
  }

  List<Map<String, Object?>> _semanticNodes(List<int> bytes, String label) {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw FormatException('$label semantics snapshot size is invalid');
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    final value = jsonDecode(text);
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 1 ||
        value['kind'] != 'AndroidSemanticsSnapshot' ||
        value['nodes'] is! List<Object?>) {
      throw FormatException('$label semantics snapshot is invalid');
    }
    final canonical = '${const JcsCanonicalizer().canonicalize(value)}\n';
    if (text != canonical) {
      throw FormatException('$label semantics snapshot is not canonical JCS');
    }
    final nodes = value['nodes']! as List<Object?>;
    if (nodes.length > 100000 ||
        nodes.any((node) => node is! Map<String, Object?>)) {
      throw FormatException('$label semantics node inventory is invalid');
    }
    return nodes.cast<Map<String, Object?>>();
  }
}
