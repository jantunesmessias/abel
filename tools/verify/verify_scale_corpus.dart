import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:interaction_model/interaction_model.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final workspace = Directory(options.workspace).absolute;
  final export = File(options.export).absolute;
  final report = File(options.report).absolute;
  _requireNewOutput(export);
  _requireNewOutput(report);
  final corpus = _readCorpus(workspace);
  final authoringFootprint = _authoringFootprint(workspace);
  if (corpus.scenarioCount != options.scenarioCount ||
      corpus.transitionCount != options.transitionCount ||
      corpus.edgeCount != options.edgeCount ||
      authoringFootprint.files != corpus.authoringFileCount ||
      authoringFootprint.bytes > options.maxAuthoringBytes) {
    throw const FormatException('Scale corpus cardinality fence failed');
  }

  final totalClock = Stopwatch()..start();
  final rssStart = ProcessInfo.currentRss;
  final loadClock = Stopwatch()..start();
  final loaded =
      WorkspaceCatalogLoader(
        maxFiles: options.maxAuthoringFiles,
        maxFileBytes: options.maxAuthoringFileBytes,
        maxTotalBytes: options.maxAuthoringBytes,
      ).load(
        startPath: workspace.path,
        explicitConfigPath: p.join(workspace.path, 'workspace.yaml'),
      );
  loadClock.stop();

  final catalogClock = Stopwatch()..start();
  final catalog = const CatalogCompiler().compile(
    loaded.documents,
    layout: loaded.layout,
  );
  catalogClock.stop();
  final topologyClock = Stopwatch()..start();
  final compiled = const ExperienceTopologyCompiler().compile(
    loaded.documents,
    catalog: catalog,
  );
  final bundle = ExperienceTopologyBundle(
    catalog: catalog,
    topology: compiled.topology,
    layouts: compiled.layouts,
  );
  topologyClock.stop();
  _validateCardinalities(catalog, bundle, corpus);

  final spatial = _measureSpatialWindow(bundle, options);
  final impact = _measureIncrementalImpact(corpus.scenarioCount);
  final worker = await _measureWarmedWorker();
  if (worker.workerStarts != 1 ||
      worker.batchCount != 4 ||
      worker.successCount != 255 ||
      worker.failureCount != 1 ||
      !worker.successAfterFailure) {
    throw StateError('Descriptor failure isolation did not hold');
  }

  final exportClock = Stopwatch()..start();
  final exportDocument = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'DeterministicScaleExport',
    'corpus': corpus.toJson(),
    'catalog': catalog.toJson(),
    'experience': bundle.toJson(),
    'impactPlan': impact.plan.toJson(),
  };
  final exportBytes = utf8.encode(
    '${const JcsCanonicalizer().canonicalize(exportDocument)}\n',
  );
  if (exportBytes.length > options.maxExportBytes) {
    throw StateError('Scale export exceeded its byte budget');
  }
  export.parent.createSync(recursive: true);
  export.writeAsBytesSync(exportBytes, flush: true);
  exportClock.stop();
  totalClock.stop();
  final rssObserved = ProcessInfo.currentRss;

  if (totalClock.elapsedMilliseconds > options.maxElapsedMs) {
    throw StateError('Scale verification exceeded its time budget');
  }
  if (rssObserved > options.maxRssBytes) {
    throw StateError('Scale verification exceeded its RSS budget');
  }
  if (spatial.p95Micros > options.maxWindowP95Micros) {
    throw StateError('Scale window query exceeded its p95 budget');
  }
  final result = <String, Object?>{
    'schemaVersion': 1,
    'status': 'passed',
    'environment': <String, Object?>{
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'processors': Platform.numberOfProcessors,
    },
    'corpus': corpus.toJson(),
    'digests': <String, Object?>{
      'catalog': catalog.digest.value,
      'topology': bundle.topology.digest.value,
      'bundle': bundle.digest.value,
      'export': Digest.bytes(exportBytes).value,
    },
    'budgets': <String, Object?>{
      'maxAuthoringFiles': options.maxAuthoringFiles,
      'maxAuthoringFileBytes': options.maxAuthoringFileBytes,
      'maxAuthoringBytes': options.maxAuthoringBytes,
      'maxElapsedMs': options.maxElapsedMs,
      'maxRssBytes': options.maxRssBytes,
      'maxExportBytes': options.maxExportBytes,
      'maxWindowP95Micros': options.maxWindowP95Micros,
      'maxRenderedItems': options.maxRenderedItems,
      'maxRenderableEdges': options.maxRenderableEdges,
      'maxBoundaryEdges': options.maxBoundaryEdges,
    },
    'measurements': <String, Object?>{
      'loadMs': loadClock.elapsedMilliseconds,
      'catalogCompileMs': catalogClock.elapsedMilliseconds,
      'topologyCompileMs': topologyClock.elapsedMilliseconds,
      'exportMs': exportClock.elapsedMilliseconds,
      'totalMs': totalClock.elapsedMilliseconds,
      'rssStartBytes': rssStart,
      'rssObservedBytes': rssObserved,
      'rssDeltaBytes': rssObserved - rssStart,
      'exportBytes': exportBytes.length,
      'authoringBytes': authoringFootprint.bytes,
      'authoringFiles': authoringFootprint.files,
      'windowSamplesMicros': spatial.samplesMicros,
      'windowP95Micros': spatial.p95Micros,
    },
    'virtualization': <String, Object?>{
      'renderedItems': spatial.maximumRenderedItems,
      'renderedEdges': spatial.maximumRenderedEdges,
      'retainedBoundaryEdges': spatial.maximumBoundaryEdges,
      'totalBoundaryEdgesObserved': spatial.maximumBoundaryEdgeCount,
      'itemsBounded': spatial.maximumRenderedItems <= options.maxRenderedItems,
      'edgesBounded':
          spatial.maximumRenderedEdges <= options.maxRenderableEdges,
      'boundaryMemoryBounded':
          spatial.maximumBoundaryEdges <= options.maxBoundaryEdges,
    },
    'incrementalCapture': <String, Object?>{
      'bindingCount': corpus.scenarioCount,
      'impactedCount': impact.plan.impacted.length,
      'reusableCount': impact.plan.reusableSubjects.length,
      'complete': impact.plan.complete,
      'directAndTransitive': impact.directAndTransitive,
    },
    'descriptorBatches': worker.toJson(),
  };
  report.parent.createSync(recursive: true);
  report.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(result)}\n',
    flush: true,
  );
  stdout.writeln(jsonEncode(result));
}

void _requireNewOutput(File file) {
  if (!file.parent.existsSync() || Link(file.parent.path).existsSync()) {
    throw FileSystemException('Output parent is missing or linked', file.path);
  }
  if (file.existsSync() || Link(file.path).existsSync()) {
    throw FileSystemException('Output already exists', file.path);
  }
}

_Corpus _readCorpus(Directory workspace) {
  final file = File(p.join(workspace.path, 'scale-corpus.json'));
  if (!file.existsSync() || Link(file.path).existsSync()) {
    throw FileSystemException('Scale corpus manifest is missing', file.path);
  }
  final bytes = file.readAsBytesSync();
  if (bytes.isEmpty || bytes.length > 64 * 1024) {
    throw const FormatException('Scale corpus manifest is outside its budget');
  }
  return _Corpus.fromJson(jsonDecode(utf8.decode(bytes)));
}

({int files, int bytes}) _authoringFootprint(Directory workspace) {
  final root = Directory(p.join(workspace.path, '.experience'));
  var files = 0;
  var bytes = 0;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw FileSystemException('Scale corpus contains a link', entity.path);
    }
    if (entity is File) {
      files += 1;
      bytes += entity.lengthSync();
    }
  }
  return (files: files, bytes: bytes);
}

void _validateCardinalities(
  CatalogManifest catalog,
  ExperienceTopologyBundle bundle,
  _Corpus corpus,
) {
  if (catalog.scenarios.length != corpus.scenarioCount ||
      catalog.transitions.length != corpus.transitionCount ||
      bundle.topology.nodes.length != corpus.nodeCount ||
      bundle.topology.edges.length != corpus.edgeCount ||
      bundle.topology.projections.length != 1 ||
      bundle.layouts.length != 1 ||
      bundle.layouts.single.nodeFrames.length != corpus.nodeCount) {
    throw StateError('Compiled scale cardinalities differ from the corpus');
  }
}

_SpatialMeasurement _measureSpatialWindow(
  ExperienceTopologyBundle bundle,
  _Options options,
) {
  final layout = bundle.layouts.single;
  final frames = <NodeInstanceId, ProjectionNodeFrame>{
    for (final frame in layout.nodeFrames) frame.nodeInstanceId: frame,
  };
  final index = SpatialIndex(
    items: <SpatialItem>[
      for (final node in bundle.topology.nodes)
        SpatialItem(
          id: node.id.value,
          bounds: SpatialRect.fromLTWH(
            frames[node.id]!.x,
            frames[node.id]!.y,
            frames[node.id]!.width,
            frames[node.id]!.height,
          ),
        ),
    ],
    edges: <SpatialEdge>[
      for (final edge in bundle.topology.edges)
        SpatialEdge(
          id: edge.id.value,
          fromId: edge.fromNodeId.value,
          toId: edge.toNodeId.value,
        ),
    ],
  );
  final policy = SpatialWindowPolicy(
    overscan: 80,
    maximumVisibleItems: options.maxRenderedItems,
    maximumRenderableEdges: options.maxRenderableEdges,
    maximumBoundaryEdges: options.maxBoundaryEdges,
    minimumZoom: 0.05,
    maximumZoom: 8,
  );
  final samples = <int>[];
  var maximumItems = 0;
  var maximumEdges = 0;
  var maximumBoundary = 0;
  var maximumBoundaryCount = 0;
  for (final selectedIndex in const <int>[
    0,
    199,
    499,
    799,
    999,
    1199,
    1499,
    1799,
    1999,
  ]) {
    final boundedIndex = selectedIndex.clamp(
      0,
      bundle.topology.nodes.length - 1,
    );
    final selected = bundle.topology.nodes[boundedIndex];
    final frame = frames[selected.id]!;
    final clock = Stopwatch()..start();
    final window = policy.window(
      index: index,
      viewport: SpatialViewport(
        worldOrigin: SpatialPoint(frame.x - 480, frame.y - 320),
        width: 1440,
        height: 900,
        zoom: 1,
      ),
      selectedItemId: selected.id.value,
    );
    clock.stop();
    samples.add(clock.elapsedMicroseconds);
    maximumItems = _max(maximumItems, window.itemIds.length);
    maximumEdges = _max(maximumEdges, window.renderableEdges.length);
    maximumBoundary = _max(maximumBoundary, window.boundaryEdges.length);
    maximumBoundaryCount = _max(maximumBoundaryCount, window.boundaryEdgeCount);
  }
  final sorted = List<int>.of(samples)..sort();
  return _SpatialMeasurement(
    samplesMicros: samples,
    p95Micros: sorted[((sorted.length - 1) * 0.95).ceil()],
    maximumRenderedItems: maximumItems,
    maximumRenderedEdges: maximumEdges,
    maximumBoundaryEdges: maximumBoundary,
    maximumBoundaryEdgeCount: maximumBoundaryCount,
  );
}

_ImpactMeasurement _measureIncrementalImpact(int scenarioCount) {
  final repository = SourceRepository(
    id: 'scale-source',
    kind: SourceRepositoryKind.filesystem,
    root: '.',
  );
  final before = <SourceFileEntry>[];
  final after = <SourceFileEntry>[];
  final bindings = <SourceBinding>[];
  for (var index = 0; index < scenarioCount; index += 1) {
    final path = 'lib/${_id('scenario', index)}.dart';
    final oldBytes = utf8.encode('scenario-$index-v1');
    final newBytes = index == 0 ? utf8.encode('scenario-0-v2') : oldBytes;
    before.add(
      SourceFileEntry(
        path: path,
        digest: Digest.bytes(oldBytes),
        size: oldBytes.length,
      ),
    );
    after.add(
      SourceFileEntry(
        path: path,
        digest: Digest.bytes(newBytes),
        size: newBytes.length,
      ),
    );
    bindings.add(
      SourceBinding(
        id: _id('binding', index),
        subject: _id('scenario', index),
        repositoryId: repository.id,
        pathGlobs: <String>[path],
        dependsOn: index % 8 == 0
            ? const <String>[]
            : <String>[_id('binding', index - 1)],
      ),
    );
  }
  final engine = const SourceImpactEngine();
  final changes = engine.diff(
    SourceSnapshot(
      repository: repository,
      revision: 'base',
      completeness: SnapshotCompleteness.complete,
      files: before,
    ),
    SourceSnapshot(
      repository: repository,
      revision: 'current',
      completeness: SnapshotCompleteness.complete,
      files: after,
    ),
  );
  final plan = engine.plan(changes, bindings);
  final reasons = plan.impacted.expand((item) => item.reasons).toSet();
  if (!plan.complete ||
      plan.impacted.length != 8 ||
      plan.reusableSubjects.length != scenarioCount - 8 ||
      !reasons.contains(ImpactReason.direct) ||
      !reasons.contains(ImpactReason.transitive)) {
    throw StateError('Incremental impact did not remain bounded and complete');
  }
  return _ImpactMeasurement(plan: plan, directAndTransitive: true);
}

Future<_WorkerSummary> _measureWarmedWorker() async {
  final ready = ReceivePort();
  final exit = ReceivePort();
  await Isolate.spawn(_descriptorWorker, ready.sendPort, onExit: exit.sendPort);
  final command = await ready.first as SendPort;
  var success = 0;
  var failure = 0;
  var successAfterFailure = false;
  var sawFailure = false;
  for (var batch = 0; batch < 4; batch += 1) {
    final reply = ReceivePort();
    final descriptors = <Map<String, Object?>>[
      for (var offset = 0; offset < 64; offset += 1)
        <String, Object?>{
          'id': 'descriptor-${batch * 64 + offset}',
          'kind': 'capture',
          'payload': <String, Object?>{
            'schemaVersion': 1,
            'digest': Digest.semantic(<String, Object?>{
              'batch': batch,
              'offset': offset,
            }).value,
          },
          if (batch == 1 && offset == 36) 'path': '../../outside',
        },
    ];
    command.send(<Object?>[reply.sendPort, descriptors]);
    final result = await reply.first as List<Object?>;
    reply.close();
    final batchSuccess = result[0]! as int;
    final batchFailure = result[1]! as int;
    success += batchSuccess;
    failure += batchFailure;
    if (sawFailure && batchSuccess > 0) successAfterFailure = true;
    if (batchFailure > 0) sawFailure = true;
  }
  command.send('close');
  await exit.first;
  ready.close();
  exit.close();
  return _WorkerSummary(
    workerStarts: 1,
    batchCount: 4,
    descriptorCount: 256,
    successCount: success,
    failureCount: failure,
    successAfterFailure: successAfterFailure,
  );
}

void _descriptorWorker(SendPort ready) {
  final input = ReceivePort();
  ready.send(input.sendPort);
  input.listen((message) {
    if (message == 'close') {
      input.close();
      return;
    }
    final request = message! as List<Object?>;
    final reply = request[0]! as SendPort;
    final descriptors = request[1]! as List<Object?>;
    var success = 0;
    var failure = 0;
    for (final value in descriptors) {
      try {
        if (value is! Map<Object?, Object?> ||
            value.keys.toSet().difference(const <String>{
              'id',
              'kind',
              'payload',
            }).isNotEmpty ||
            value['id'] is! String ||
            value['kind'] != 'capture' ||
            value['payload'] is! Map<Object?, Object?>) {
          throw const FormatException('Invalid descriptor envelope');
        }
        final payload = value['payload']! as Map<Object?, Object?>;
        if (payload.length != 2 ||
            payload['schemaVersion'] != 1 ||
            payload['digest'] is! String) {
          throw const FormatException('Invalid descriptor payload');
        }
        Digest(payload['digest']! as String);
        success += 1;
      } on Object {
        failure += 1;
      }
    }
    reply.send(<Object?>[success, failure]);
  });
}

int _max(int left, int right) => left > right ? left : right;

String _id(String prefix, int index) =>
    '$prefix-${index.toString().padLeft(5, '0')}';

final class _Corpus {
  const _Corpus({
    required this.scenarioCount,
    required this.nodeCount,
    required this.transitionCount,
    required this.edgeCount,
    required this.authoringFileCount,
  });

  final int scenarioCount;
  final int nodeCount;
  final int transitionCount;
  final int edgeCount;
  final int authoringFileCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'scenarioCount': scenarioCount,
    'nodeCount': nodeCount,
    'transitionCount': transitionCount,
    'edgeCount': edgeCount,
    'authoringFileCount': authoringFileCount,
    'nonlinear': true,
  };

  factory _Corpus.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value.keys.toSet().difference(const <String>{
          'schemaVersion',
          'kind',
          'scenarioCount',
          'nodeCount',
          'transitionCount',
          'edgeCount',
          'authoringFileCount',
          'batchSize',
          'nonlinear',
        }).isNotEmpty ||
        value['schemaVersion'] != 1 ||
        value['kind'] != 'DeterministicScaleCorpus' ||
        value['scenarioCount'] is! int ||
        value['nodeCount'] is! int ||
        value['transitionCount'] is! int ||
        value['edgeCount'] is! int ||
        value['authoringFileCount'] is! int ||
        value['batchSize'] != 500 ||
        value['nonlinear'] != true) {
      throw const FormatException('Invalid scale corpus manifest');
    }
    return _Corpus(
      scenarioCount: value['scenarioCount']! as int,
      nodeCount: value['nodeCount']! as int,
      transitionCount: value['transitionCount']! as int,
      edgeCount: value['edgeCount']! as int,
      authoringFileCount: value['authoringFileCount']! as int,
    );
  }
}

final class _SpatialMeasurement {
  const _SpatialMeasurement({
    required this.samplesMicros,
    required this.p95Micros,
    required this.maximumRenderedItems,
    required this.maximumRenderedEdges,
    required this.maximumBoundaryEdges,
    required this.maximumBoundaryEdgeCount,
  });

  final List<int> samplesMicros;
  final int p95Micros;
  final int maximumRenderedItems;
  final int maximumRenderedEdges;
  final int maximumBoundaryEdges;
  final int maximumBoundaryEdgeCount;
}

final class _ImpactMeasurement {
  const _ImpactMeasurement({
    required this.plan,
    required this.directAndTransitive,
  });

  final ImpactPlan plan;
  final bool directAndTransitive;
}

final class _WorkerSummary {
  const _WorkerSummary({
    required this.workerStarts,
    required this.batchCount,
    required this.descriptorCount,
    required this.successCount,
    required this.failureCount,
    required this.successAfterFailure,
  });

  final int workerStarts;
  final int batchCount;
  final int descriptorCount;
  final int successCount;
  final int failureCount;
  final bool successAfterFailure;

  Map<String, Object?> toJson() => <String, Object?>{
    'workerStarts': workerStarts,
    'batchCount': batchCount,
    'descriptorCount': descriptorCount,
    'successCount': successCount,
    'failureCount': failureCount,
    'successAfterFailure': successAfterFailure,
  };
}

final class _Options {
  const _Options({
    required this.workspace,
    required this.export,
    required this.report,
    required this.scenarioCount,
    required this.transitionCount,
    required this.edgeCount,
    required this.maxAuthoringFiles,
    required this.maxAuthoringFileBytes,
    required this.maxAuthoringBytes,
    required this.maxElapsedMs,
    required this.maxRssBytes,
    required this.maxExportBytes,
    required this.maxWindowP95Micros,
    required this.maxRenderedItems,
    required this.maxRenderableEdges,
    required this.maxBoundaryEdges,
  });

  final String workspace;
  final String export;
  final String report;
  final int scenarioCount;
  final int transitionCount;
  final int edgeCount;
  final int maxAuthoringFiles;
  final int maxAuthoringFileBytes;
  final int maxAuthoringBytes;
  final int maxElapsedMs;
  final int maxRssBytes;
  final int maxExportBytes;
  final int maxWindowP95Micros;
  final int maxRenderedItems;
  final int maxRenderableEdges;
  final int maxBoundaryEdges;

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
        throw const FormatException('Scale verifier arguments are invalid');
      }
      values[arguments[index].substring(2)] = arguments[index + 1];
    }
    String required(String key) =>
        values[key] ?? (throw FormatException('Missing --$key'));
    int integer(String key) => int.parse(required(key));
    final options = _Options(
      workspace: required('workspace'),
      export: required('export'),
      report: required('report'),
      scenarioCount: integer('scenarios'),
      transitionCount: integer('transitions'),
      edgeCount: integer('edges'),
      maxAuthoringFiles: integer('max-authoring-files'),
      maxAuthoringFileBytes: integer('max-authoring-file-bytes'),
      maxAuthoringBytes: integer('max-authoring-bytes'),
      maxElapsedMs: integer('max-elapsed-ms'),
      maxRssBytes: integer('max-rss-bytes'),
      maxExportBytes: integer('max-export-bytes'),
      maxWindowP95Micros: integer('max-window-p95-micros'),
      maxRenderedItems: integer('max-rendered-items'),
      maxRenderableEdges: integer('max-renderable-edges'),
      maxBoundaryEdges: integer('max-boundary-edges'),
    );
    if (options.scenarioCount < 1000 ||
        options.transitionCount < 20000 ||
        options.edgeCount < options.scenarioCount ||
        options.edgeCount > options.transitionCount ||
        options.maxAuthoringFiles < 1 ||
        options.maxAuthoringFileBytes < 1024 ||
        options.maxAuthoringBytes < options.maxAuthoringFileBytes ||
        options.maxElapsedMs < 1 ||
        options.maxRssBytes < 1 ||
        options.maxExportBytes < 1 ||
        options.maxWindowP95Micros < 1 ||
        options.maxRenderedItems < 1 ||
        options.maxRenderableEdges < 1 ||
        options.maxBoundaryEdges < 1) {
      throw const FormatException('Scale verifier budgets are invalid');
    }
    return options;
  }
}
