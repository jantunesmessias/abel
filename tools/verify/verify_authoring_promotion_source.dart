import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

void main(List<String> arguments) {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run tools/verify/verify_authoring_promotion_source.dart '
      '<baseline-workspace> <promoted-workspace> <projection-id> <node-instance-id>',
    );
    exitCode = 64;
    return;
  }

  final baseline = _load(arguments[0]);
  final promoted = _load(arguments[1]);
  final projectionId = ExperienceProjectionId(arguments[2]);
  final expectedNodeId = NodeInstanceId(arguments[3]);
  if (baseline.catalog.digest != promoted.catalog.digest ||
      baseline.bundle.topology.digest != promoted.bundle.topology.digest) {
    throw StateError('Promotion changed Catalog or semantic topology');
  }

  final baselineLayouts = <ExperienceProjectionId, ProjectionLayoutManifest>{
    for (final layout in baseline.bundle.layouts) layout.projectionId: layout,
  };
  final promotedLayouts = <ExperienceProjectionId, ProjectionLayoutManifest>{
    for (final layout in promoted.bundle.layouts) layout.projectionId: layout,
  };
  if (baselineLayouts.keys
          .toSet()
          .difference(promotedLayouts.keys.toSet())
          .isNotEmpty ||
      promotedLayouts.keys
          .toSet()
          .difference(baselineLayouts.keys.toSet())
          .isNotEmpty) {
    throw StateError('Promotion changed the ProjectionLayout set');
  }
  for (final entry in baselineLayouts.entries) {
    if (entry.key != projectionId &&
        promotedLayouts[entry.key]?.digest != entry.value.digest) {
      throw StateError('Promotion changed an unrelated ProjectionLayout');
    }
  }

  final before = baselineLayouts[projectionId];
  final after = promotedLayouts[projectionId];
  if (before == null || after == null || before.digest == after.digest) {
    throw StateError('Promotion did not produce the expected layout revision');
  }
  if (before.topologyDigest != after.topologyDigest ||
      Digest.semantic(<Object?>[
            for (final value in before.groups) value.toJson(),
            for (final value in before.lanes) value.toJson(),
            for (final value in before.annotations) value.toJson(),
            before.camera.toJson(),
          ]) !=
          Digest.semantic(<Object?>[
            for (final value in after.groups) value.toJson(),
            for (final value in after.lanes) value.toJson(),
            for (final value in after.annotations) value.toJson(),
            after.camera.toJson(),
          ])) {
    throw StateError('Promotion changed non-frame layout semantics');
  }

  final beforeFrames = <NodeInstanceId, ProjectionNodeFrame>{
    for (final frame in before.nodeFrames) frame.nodeInstanceId: frame,
  };
  final afterFrames = <NodeInstanceId, ProjectionNodeFrame>{
    for (final frame in after.nodeFrames) frame.nodeInstanceId: frame,
  };
  if (beforeFrames.length != afterFrames.length ||
      beforeFrames.keys
          .toSet()
          .difference(afterFrames.keys.toSet())
          .isNotEmpty ||
      afterFrames.keys
          .toSet()
          .difference(beforeFrames.keys.toSet())
          .isNotEmpty) {
    throw StateError('Promotion changed the layout frame set');
  }
  final changed = <NodeInstanceId>[];
  for (final entry in beforeFrames.entries) {
    final candidate = afterFrames[entry.key]!;
    if (Digest.semantic(entry.value.toJson()) !=
        Digest.semantic(candidate.toJson())) {
      changed.add(entry.key);
    }
  }
  if (changed.length != 1 || changed.single != expectedNodeId) {
    throw StateError('Promotion changed an unexpected frame cardinality');
  }
  final original = beforeFrames[changed.single]!;
  final candidate = afterFrames[changed.single]!;
  if (candidate.x != original.x + 20 ||
      candidate.y != original.y ||
      candidate.width != original.width ||
      candidate.height != original.height ||
      candidate.groupId != original.groupId ||
      candidate.laneId != original.laneId) {
    throw StateError('Promotion changed fields outside the exact right move');
  }

  stdout.writeln(
    jsonEncode(<String, Object?>{
      'catalogStable': true,
      'topologyStable': true,
      'unrelatedLayoutsStable': true,
      'changedFrameCount': changed.length,
      'movedRightByTwenty': true,
    }),
  );
}

({CatalogManifest catalog, CompiledExperienceTopology bundle}) _load(
  String workspace,
) {
  final loaded = const WorkspaceCatalogLoader().load(startPath: workspace);
  final catalog = const CatalogCompiler().compile(
    loaded.documents,
    layout: loaded.layout,
  );
  return (
    catalog: catalog,
    bundle: const ExperienceTopologyCompiler().compile(
      loaded.documents,
      catalog: catalog,
    ),
  );
}
