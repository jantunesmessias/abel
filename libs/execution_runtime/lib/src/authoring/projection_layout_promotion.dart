import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../host/host_workspace_service.dart';
import '../workspace/workspace_configuration_loader.dart';
import 'experience_authoring_service.dart';
import 'experience_authoring_store.dart';
import 'filesystem_experience_authoring_store.dart';
import 'projection_layout_preserving_swap.dart';

export 'projection_layout_preserving_swap.dart';

Digest projectionLayoutPromotionContentDigest(HostWorkspaceContent content) =>
    Digest.semantic(<String, Object?>{
      'catalogDigest': content.catalog.digest.value,
      if (content.experienceBundle != null)
        'experienceBundleDigest': content.experienceBundle!.digest.value,
      if (content.scenarioFacetManifest != null)
        'scenarioFacetManifestDigest':
            content.scenarioFacetManifest!.digest.value,
      if (content.scenarioLabManifest != null)
        'scenarioLabManifestDigest': content.scenarioLabManifest!.digest.value,
    });

/// Host-only digest that binds a promotion WAL to its exact resolved routing
/// authority without persisting or exposing a filesystem path.
Digest projectionLayoutPromotionConfigurationAuthorityDigest(
  LoadedWorkspaceConfiguration configuration,
  AuthoringSubjectRef subject,
) => Digest.semantic(<String, Object?>{
  'kind': 'projection-layout-configuration-authority-v1',
  'workspaceRootDigest': Digest.semantic(
    p.normalize(p.absolute(configuration.workspaceRoot)),
  ).value,
  'contentRootDigest': Digest.semantic(
    p.normalize(p.absolute(configuration.contentRoot)),
  ).value,
  'configurationDocumentDigest': configuration.documentDigest.value,
  if (configuration.localDocumentDigest != null)
    'localConfigurationDocumentDigest':
        configuration.localDocumentDigest!.value,
  'workspaceId': configuration.workspaceId,
  'subject': subject.toJson(),
});

final class BoundedAuthoringSource {
  const BoundedAuthoringSource({
    required this.path,
    required this.bytes,
    required this.digest,
  });

  final String path;
  final List<int> bytes;
  final Digest digest;
}

final class BoundedWorkspaceAuthoringCorpus {
  BoundedWorkspaceAuthoringCorpus({
    required this.configuration,
    required List<AuthoringDocument> documents,
    required Map<String, BoundedAuthoringSource> sources,
  }) : documents = List<AuthoringDocument>.unmodifiable(documents),
       sources = Map<String, BoundedAuthoringSource>.unmodifiable(sources);

  final LoadedWorkspaceConfiguration configuration;
  final List<AuthoringDocument> documents;
  final Map<String, BoundedAuthoringSource> sources;
}

/// Loads every content document through the parser's real byte budget.
///
/// The ordinary workspace loader calls `readAsStringSync()` before parsing.
/// This boundary performs no-follow regular-file checks, a pre-read stat, a
/// bounded incremental read with a growth sentinel, and a post-read stat.
final class BoundedWorkspaceAuthoringLoader {
  const BoundedWorkspaceAuthoringLoader({
    this.parser = const SafeAuthoringParser(),
    this.configurationLoader = const WorkspaceConfigurationLoader(),
    this.maxFiles = 16000,
    this.maxEntries = 40000,
    this.maxDirectories = 16000,
    this.maxAggregateBytes = 64 * 1024 * 1024,
    this.beforeRead,
  }) : assert(maxFiles > 0 && maxFiles <= 16000),
       assert(maxEntries >= maxFiles && maxEntries <= 100000),
       assert(maxDirectories > 0 && maxDirectories <= 32000),
       assert(maxAggregateBytes > 0 && maxAggregateBytes <= 128 * 1024 * 1024);

  final SafeAuthoringParser parser;
  final WorkspaceConfigurationLoader configurationLoader;
  final int maxFiles;
  final int maxEntries;
  final int maxDirectories;
  final int maxAggregateBytes;
  final void Function(File file, int initialSize)? beforeRead;

  BoundedWorkspaceAuthoringCorpus load({
    required String startPath,
    String? explicitConfigPath,
    Map<String, String>? environment,
  }) => loadFromConfiguration(
    configurationLoader.load(
      startPath: startPath,
      explicitConfigPath: explicitConfigPath,
      environment: environment,
    ),
  );

  BoundedWorkspaceAuthoringCorpus loadFromConfiguration(
    LoadedWorkspaceConfiguration configuration,
  ) {
    final documents = <AuthoringDocument>[
      AuthoringDocument(
        schemaVersion: 1,
        kind: AuthoringKind.workspace,
        id: configuration.workspaceId,
        spec: <String, Object?>{
          'displayName': configuration.workspaceDisplayName,
        },
        sourceName: '${configuration.configPath}#workspace',
      ),
      for (final application in configuration.applications.values)
        AuthoringDocument(
          schemaVersion: 1,
          kind: AuthoringKind.application,
          id: application.id,
          spec: <String, Object?>{
            'workspaceId': configuration.workspaceId,
            'displayName': application.displayName,
            'root': application.root,
            'target': application.target,
          },
          sourceName:
              '${configuration.configPath}#applications.${application.id}',
        ),
    ];
    final root = Directory(configuration.contentRoot);
    final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
    if (rootType != FileSystemEntityType.directory ||
        Link(root.path).existsSync()) {
      throw FileSystemException(
        'Content root must be a regular directory',
        root.path,
      );
    }
    final files = <File>[];
    final pendingDirectories = <Directory>[root];
    var totalEntries = 0;
    var totalDirectories = 1;
    while (pendingDirectories.isNotEmpty) {
      final directory = pendingDirectories.removeLast();
      final children = directory.listSync(recursive: false, followLinks: false)
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final entity in children) {
        totalEntries += 1;
        if (totalEntries > maxEntries) {
          throw FileSystemException(
            'Content root exceeds $maxEntries total entries',
            root.path,
          );
        }
        final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
        if (entity is Link || type == FileSystemEntityType.link) {
          throw FileSystemException(
            'Links are forbidden in content root',
            entity.path,
          );
        }
        if (type == FileSystemEntityType.directory) {
          totalDirectories += 1;
          if (totalDirectories > maxDirectories) {
            throw FileSystemException(
              'Content root exceeds $maxDirectories directories',
              root.path,
            );
          }
          pendingDirectories.add(Directory(entity.path));
        } else if (entity is File &&
            const <String>{
              '.yaml',
              '.yml',
              '.json',
            }.contains(p.extension(entity.path).toLowerCase())) {
          if (type != FileSystemEntityType.file) {
            throw FileSystemException(
              'Authoring source must be a regular file',
              entity.path,
            );
          }
          files.add(entity);
          if (files.length > maxFiles) {
            throw FileSystemException(
              'Content root exceeds $maxFiles authoring files',
              root.path,
            );
          }
        }
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    var aggregateBytes = 0;
    final candidates = <({File file, int size})>[];
    for (final file in files) {
      final type = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (type != FileSystemEntityType.file || Link(file.path).existsSync()) {
        throw FileSystemException(
          'Authoring source must be a regular non-link file',
          file.path,
        );
      }
      final size = file.statSync().size;
      if (size < 0 || size > parser.maxSourceBytes) {
        throw FileSystemException(
          'Authoring source exceeds ${parser.maxSourceBytes} bytes',
          file.path,
        );
      }
      aggregateBytes += size;
      if (aggregateBytes > maxAggregateBytes) {
        throw FileSystemException(
          'Authoring corpus exceeds $maxAggregateBytes bytes',
          root.path,
        );
      }
      candidates.add((file: file, size: size));
    }
    final sources = <String, BoundedAuthoringSource>{};
    for (final candidate in candidates) {
      final file = candidate.file;
      final bytes = _readBounded(file, initialSize: candidate.size);
      final text = utf8.decode(bytes, allowMalformed: false);
      final document = parser.parse(text, sourceName: file.path);
      documents.add(document);
      sources[file.path] = BoundedAuthoringSource(
        path: file.path,
        bytes: List<int>.unmodifiable(bytes),
        digest: Digest.bytes(bytes),
      );
    }
    return BoundedWorkspaceAuthoringCorpus(
      configuration: configuration,
      documents: documents,
      sources: sources,
    );
  }

  List<int> _readBounded(File file, {required int initialSize}) {
    final initialType = FileSystemEntity.typeSync(
      file.path,
      followLinks: false,
    );
    if (initialType != FileSystemEntityType.file ||
        Link(file.path).existsSync()) {
      throw FileSystemException(
        'Authoring source must be a regular non-link file',
        file.path,
      );
    }
    if (initialSize < 0 || initialSize > parser.maxSourceBytes) {
      throw FileSystemException(
        'Authoring source exceeds ${parser.maxSourceBytes} bytes',
        file.path,
      );
    }
    beforeRead?.call(file, initialSize);
    final output = BytesBuilder(copy: false);
    final reader = file.openSync();
    var total = 0;
    try {
      while (true) {
        final remaining = initialSize - total;
        final requestBytes = remaining < 64 * 1024 ? remaining + 1 : 64 * 1024;
        final chunk = reader.readSync(requestBytes);
        if (chunk.isEmpty) break;
        total += chunk.length;
        if (total > initialSize || total > parser.maxSourceBytes) {
          throw FileSystemException(
            'Authoring source grew during bounded read',
            file.path,
          );
        }
        output.add(chunk);
      }
    } finally {
      reader.closeSync();
    }
    final finalType = FileSystemEntity.typeSync(file.path, followLinks: false);
    final finalSize = finalType == FileSystemEntityType.file
        ? file.statSync().size
        : -1;
    if (finalType != FileSystemEntityType.file ||
        Link(file.path).existsSync() ||
        total != initialSize ||
        finalSize != initialSize) {
      throw FileSystemException(
        'Authoring source changed during bounded read',
        file.path,
      );
    }
    return Uint8List.fromList(output.takeBytes());
  }
}

final class PreparedProjectionLayoutPromotion {
  PreparedProjectionLayoutPromotion({
    required this.subject,
    required this.relativeSourcePath,
    required List<int> originalSourceBytes,
    required List<int> candidateSourceBytes,
    required this.originalSourceDigest,
    required this.candidateSourceDigest,
    required this.baseLayout,
    required this.candidateLayout,
    required this.currentContent,
    required this.candidateContent,
  }) : originalSourceBytes = List<int>.unmodifiable(originalSourceBytes),
       candidateSourceBytes = List<int>.unmodifiable(candidateSourceBytes);

  final AuthoringSubjectRef subject;

  /// Host-private routing derived from the configured content root.
  final String relativeSourcePath;
  final List<int> originalSourceBytes;
  final List<int> candidateSourceBytes;
  final Digest originalSourceDigest;
  final Digest candidateSourceDigest;
  final ProjectionLayoutManifest baseLayout;
  final ProjectionLayoutManifest candidateLayout;
  final HostWorkspaceContent currentContent;
  final HostWorkspaceContent candidateContent;
}

/// Resolves one unique ProjectionLayout source and proves a layout-only edit.
final class ProjectionLayoutPromotionCompiler {
  const ProjectionLayoutPromotionCompiler({
    this.parser = const SafeAuthoringParser(),
  });

  final SafeAuthoringParser parser;

  HostWorkspaceContent compileCurrent(BoundedWorkspaceAuthoringCorpus corpus) =>
      _compile(corpus);

  PreparedProjectionLayoutPromotion prepare({
    required BoundedWorkspaceAuthoringCorpus corpus,
    required AuthoringSubjectRef subject,
    required Digest expectedBaseLayoutDigest,
    required Digest expectedSourceDigest,
    required ProjectionLayoutManifest candidateLayout,
  }) {
    final currentContent = _compile(corpus);
    if (currentContent.catalog.workspace.id != subject.workspaceId) {
      throw StateError('Authoring subject belongs to another workspace');
    }
    final applications = currentContent.catalog.applications
        .where((application) => application.id == subject.applicationId)
        .toList(growable: false);
    if (applications.length != 1) {
      throw StateError('Authoring subject has an unknown Application');
    }
    final bundle = currentContent.experienceBundle;
    if (bundle == null) throw StateError('Experience topology is absent');
    final projections = bundle.topology.projections
        .where((projection) => projection.id == subject.projectionId)
        .toList(growable: false);
    if (projections.length != 1 ||
        projections.single.applicationId != subject.applicationId) {
      throw StateError('Projection is outside the authoring subject');
    }
    final layouts = bundle.layouts
        .where((layout) => layout.projectionId == subject.projectionId)
        .toList(growable: false);
    if (layouts.length != 1) {
      throw StateError('Projection must have one authoritative layout');
    }
    final baseLayout = layouts.single;
    if (baseLayout.digest != expectedBaseLayoutDigest ||
        candidateLayout.projectionId != baseLayout.projectionId ||
        candidateLayout.topologyDigest != baseLayout.topologyDigest) {
      throw StateError('Layout promotion is stale against its base');
    }
    final matchingDocuments = corpus.documents
        .where(
          (document) =>
              document.kind == AuthoringKind.projectionLayout &&
              document.id == subject.projectionId.value,
        )
        .toList(growable: false);
    if (matchingDocuments.length != 1) {
      throw StateError('ProjectionLayout source is not unique');
    }
    final sourceDocument = matchingDocuments.single;
    if (sourceDocument.schemaVersion != 2) {
      throw const FormatException(
        'ProjectionLayout source must already be authoring v2',
      );
    }
    final source = corpus.sources[sourceDocument.sourceName];
    if (source == null || source.digest != expectedSourceDigest) {
      throw StateError('ProjectionLayout source bytes changed');
    }
    final contentRoot = p.normalize(corpus.configuration.contentRoot);
    final sourcePath = p.normalize(p.absolute(source.path));
    if (!p.isWithin(contentRoot, sourcePath)) {
      throw FileSystemException(
        'ProjectionLayout source escapes configured content root',
        sourcePath,
      );
    }
    final candidateJson = _candidateDocument(sourceDocument, candidateLayout);
    final canonical = const JcsCanonicalizer().canonicalize(candidateJson);
    final candidateBytes = utf8.encode('$canonical\n');
    if (candidateBytes.length > parser.maxSourceBytes) {
      throw StateError('Candidate ProjectionLayout exceeds source budget');
    }
    final reparsed = parser.parse(canonical, sourceName: source.path);
    final candidateDocuments = <AuthoringDocument>[
      for (final document in corpus.documents)
        if (identical(document, sourceDocument)) reparsed else document,
    ];
    final candidateCorpus = BoundedWorkspaceAuthoringCorpus(
      configuration: corpus.configuration,
      documents: candidateDocuments,
      sources: <String, BoundedAuthoringSource>{
        ...corpus.sources,
        source.path: BoundedAuthoringSource(
          path: source.path,
          bytes: List<int>.unmodifiable(candidateBytes),
          digest: Digest.bytes(candidateBytes),
        ),
      },
    );
    final candidateContent = _compile(candidateCorpus);
    final compiledCandidate = candidateContent.experienceBundle?.layouts
        .where((layout) => layout.projectionId == subject.projectionId)
        .toList(growable: false);
    if (compiledCandidate == null ||
        compiledCandidate.length != 1 ||
        compiledCandidate.single.digest != candidateLayout.digest ||
        currentContent.catalog.digest != candidateContent.catalog.digest ||
        currentContent.experienceBundle!.topology.digest !=
            candidateContent.experienceBundle!.topology.digest ||
        currentContent.scenarioFacetManifest?.digest !=
            candidateContent.scenarioFacetManifest?.digest ||
        currentContent.scenarioLabManifest?.digest !=
            candidateContent.scenarioLabManifest?.digest) {
      throw StateError('Candidate source is not the exact layout-only change');
    }
    return PreparedProjectionLayoutPromotion(
      subject: subject,
      relativeSourcePath: p.relative(sourcePath, from: contentRoot),
      originalSourceBytes: source.bytes,
      candidateSourceBytes: List<int>.unmodifiable(candidateBytes),
      originalSourceDigest: source.digest,
      candidateSourceDigest: Digest.bytes(candidateBytes),
      baseLayout: baseLayout,
      candidateLayout: compiledCandidate.single,
      currentContent: currentContent,
      candidateContent: candidateContent,
    );
  }

  Map<String, Object?> _candidateDocument(
    AuthoringDocument source,
    ProjectionLayoutManifest candidate,
  ) {
    final rawFrames = source.spec['nodeFrames'];
    if (rawFrames is! List<Object?>) {
      throw const FormatException('ProjectionLayout nodeFrames must be a list');
    }
    final candidates = <String, ProjectionNodeFrame>{
      for (final frame in candidate.nodeFrames)
        frame.nodeInstanceId.value: frame,
    };
    final seen = <String>{};
    final frames = <Object?>[];
    for (final raw in rawFrames) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException(
          'ProjectionLayout node frame must be an object',
        );
      }
      final nodeId = raw['nodeInstanceId'];
      if (nodeId is! String || !seen.add(nodeId)) {
        throw const FormatException(
          'ProjectionLayout node frames must have unique IDs',
        );
      }
      final replacement = candidates[nodeId];
      if (replacement == null) {
        throw StateError('Candidate layout is missing a source node frame');
      }
      frames.add(<String, Object?>{
        ...raw,
        'x': replacement.x,
        'y': replacement.y,
      });
    }
    if (seen.length != candidates.length) {
      throw StateError('Candidate layout contains a non-source node frame');
    }
    return <String, Object?>{
      'schemaVersion': 2,
      'kind': 'ProjectionLayout',
      'metadata': <String, Object?>{'id': source.id},
      'spec': <String, Object?>{...source.spec, 'nodeFrames': frames},
    };
  }

  HostWorkspaceContent _compile(BoundedWorkspaceAuthoringCorpus corpus) {
    final catalog = const CatalogCompiler().compile(
      corpus.documents,
      layout: corpus.configuration.layout,
    );
    const topologyCompiler = ExperienceTopologyCompiler();
    final ExperienceTopologyBundle? bundle;
    if (topologyCompiler.hasAuthoring(corpus.documents)) {
      final compiled = topologyCompiler.compile(
        corpus.documents,
        catalog: catalog,
      );
      bundle = ExperienceTopologyBundle(
        catalog: catalog,
        topology: compiled.topology,
        layouts: compiled.layouts,
      );
    } else {
      bundle = null;
    }
    const facetCompiler = ScenarioFacetCompiler();
    final facets = facetCompiler.hasAuthoring(corpus.documents)
        ? facetCompiler.compile(corpus.documents, catalog: catalog)
        : null;
    const labCompiler = ScenarioLabCompiler();
    final lab = labCompiler.hasAuthoring(corpus.documents)
        ? labCompiler.compile(corpus.documents, catalog: catalog)
        : null;
    const motionCompiler = MotionManifestCompiler();
    final motion =
        bundle != null && motionCompiler.hasAuthoring(corpus.documents)
        ? motionCompiler.compile(
            corpus.documents,
            catalog: catalog,
            topology: bundle.topology,
          )
        : null;
    return HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: bundle,
      scenarioFacetManifest: facets,
      scenarioLabManifest: lab,
      motionManifest: motion,
    );
  }
}

abstract interface class ProjectionLayoutContentAuthority {
  /// Computes the semantic content-set digest without publishing a revision.
  Digest previewContentSetDigest(HostWorkspaceContent content);

  /// Atomically publishes the supplied precompiled content and returns the
  /// semantic content-set digest of the new live revision.
  Digest publish(HostWorkspaceContent content);
}

enum ProjectionLayoutPromotionPhase {
  prepare,
  stage,
  replace,
  publish,
  commit,
  rollback,
  recovery,
}

final class ProjectionLayoutPromotionFailure implements Exception {
  const ProjectionLayoutPromotionFailure({
    required this.phase,
    required this.cause,
    this.recoveryCause,
  });

  final ProjectionLayoutPromotionPhase phase;
  final Object cause;
  final Object? recoveryCause;

  @override
  String toString() =>
      'ProjectionLayoutPromotionFailure(${phase.name}, $cause'
      '${recoveryCause == null ? '' : ', recovery: $recoveryCause'})';
}

final class ProjectionLayoutStagedWrite {
  const ProjectionLayoutStagedWrite({
    required this.workspaceRoot,
    required this.contentRoot,
    required this.relativeSourcePath,
    required this.destinationPath,
    required this.stagingPath,
    required this.stagingRelativePath,
    required this.replaceProtocol,
    required this.replaceProviderKind,
    required this.digest,
    required this.byteLength,
    required this.sourceMetadataDigest,
  });

  final String workspaceRoot;
  final String contentRoot;
  final String relativeSourcePath;
  final String destinationPath;
  final String stagingPath;
  final String stagingRelativePath;
  final String replaceProtocol;
  final String replaceProviderKind;
  final Digest digest;
  final int byteLength;
  final Digest sourceMetadataDigest;
}

final class ProjectionLayoutAtomicReplaceReceipt {
  const ProjectionLayoutAtomicReplaceReceipt({
    required this.replaceProtocol,
    required this.providerKind,
    required this.recoverySlot,
    required this.candidateDigest,
    required this.displacedDigest,
    required this.candidateMetadataDigest,
    required this.displacedMetadataDigest,
  });

  final String replaceProtocol;
  final String providerKind;
  final String recoverySlot;
  final Digest candidateDigest;
  final Digest displacedDigest;
  final Digest candidateMetadataDigest;
  final Digest displacedMetadataDigest;
}

final class ProjectionLayoutRecoverySlotObservation {
  const ProjectionLayoutRecoverySlotObservation({
    required this.replaceProtocol,
    required this.providerKind,
    required this.recoverySlot,
    required this.destinationDigest,
    required this.stagingDigest,
    required this.destinationMetadataDigest,
    required this.stagingMetadataDigest,
  });

  final String replaceProtocol;
  final String providerKind;
  final String recoverySlot;
  final Digest? destinationDigest;
  final Digest? stagingDigest;
  final Digest? destinationMetadataDigest;
  final Digest? stagingMetadataDigest;
}

abstract interface class ProjectionLayoutAtomicFileWriter {
  String get replaceProtocol;

  String get replaceProviderKind;

  void requireSupported();

  String recoverySlot({
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
  });

  ProjectionLayoutStagedWrite stage({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required List<int> bytes,
  });

  ProjectionLayoutStagedWrite bindStaged({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required Digest digest,
    required int byteLength,
    required Digest sourceMetadataDigest,
  });

  ProjectionLayoutAtomicReplaceReceipt replace(
    ProjectionLayoutStagedWrite staged, {
    required Digest expectedCurrentDigest,
  });

  ProjectionLayoutRecoverySlotObservation inspectRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
  });

  ProjectionLayoutAtomicReplaceReceipt exchangeRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
    required Digest expectedDestinationDigest,
    required Digest expectedRecoveryDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedRecoveryMetadataDigest,
  });

  List<int> readStaged(ProjectionLayoutStagedWrite staged);
}

/// Stages into one Host-private rotating slot and atomically exchanges it with
/// the configured source. Only the strict Linux x64 provider is active.
final class FilesystemProjectionLayoutAtomicFileWriter
    implements ProjectionLayoutAtomicFileWriter {
  const FilesystemProjectionLayoutAtomicFileWriter({
    this.maxBytes = 1024 * 1024,
    this.swapPrimitive = const LinuxX64ProjectionLayoutPreservingSwap(),
  });

  final int maxBytes;
  final ProjectionLayoutPreservingSwapPrimitive swapPrimitive;

  @override
  String get replaceProtocol => projectionLayoutPreservingSwapProtocol;

  @override
  String get replaceProviderKind => swapPrimitive.providerKind;

  @override
  void requireSupported() {
    if (!swapPrimitive.isSupported) {
      throw ProjectionLayoutPreservingSwapFailure.unsupported();
    }
  }

  @override
  String recoverySlot({
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
  }) => projectionLayoutPromotionRecoverySlot(
    subject: subject,
    relativeSourcePath: relativeSourcePath,
  );

  @override
  ProjectionLayoutStagedWrite stage({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required List<int> bytes,
  }) {
    requireSupported();
    if (bytes.length > maxBytes) {
      throw ArgumentError('Invalid ProjectionLayout staging request');
    }
    _confinedSourceFile(
      contentRoot: contentRoot,
      relativeSourcePath: relativeSourcePath,
    );
    final stagingRelativePath = recoverySlot(
      subject: subject,
      relativeSourcePath: relativeSourcePath,
    );
    final staged = swapPrimitive.stage(
      contentRoot: contentRoot,
      destinationRelativePath: relativeSourcePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: stagingRelativePath,
      bytes: bytes,
      maxBytes: maxBytes,
    );
    final digest = Digest.bytes(bytes);
    if (staged.providerKind != replaceProviderKind ||
        staged.digest != digest ||
        staged.byteLength != bytes.length) {
      throw StateError('ProjectionLayout private staging verification failed');
    }
    return bindStaged(
      workspaceRoot: workspaceRoot,
      contentRoot: contentRoot,
      subject: subject,
      relativeSourcePath: relativeSourcePath,
      digest: digest,
      byteLength: bytes.length,
      sourceMetadataDigest: staged.sourceMetadataDigest,
    );
  }

  @override
  ProjectionLayoutStagedWrite bindStaged({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required Digest digest,
    required int byteLength,
    required Digest sourceMetadataDigest,
  }) {
    if (byteLength < 0 || byteLength > maxBytes) {
      throw ArgumentError('Invalid ProjectionLayout staged binding');
    }
    final destination = _confinedSourceFile(
      contentRoot: contentRoot,
      relativeSourcePath: relativeSourcePath,
    );
    final stagingRelativePath = recoverySlot(
      subject: subject,
      relativeSourcePath: relativeSourcePath,
    );
    final normalizedWorkspace = p.normalize(p.absolute(workspaceRoot));
    return ProjectionLayoutStagedWrite(
      workspaceRoot: normalizedWorkspace,
      contentRoot: p.normalize(p.absolute(contentRoot)),
      relativeSourcePath: relativeSourcePath,
      destinationPath: destination.path,
      stagingPath: p.normalize(
        p.join(normalizedWorkspace, stagingRelativePath),
      ),
      stagingRelativePath: stagingRelativePath,
      replaceProtocol: replaceProtocol,
      replaceProviderKind: replaceProviderKind,
      digest: digest,
      byteLength: byteLength,
      sourceMetadataDigest: sourceMetadataDigest,
    );
  }

  @override
  ProjectionLayoutAtomicReplaceReceipt replace(
    ProjectionLayoutStagedWrite staged, {
    required Digest expectedCurrentDigest,
  }) {
    requireSupported();
    final destination = _confinedSourceFile(
      contentRoot: staged.contentRoot,
      relativeSourcePath: staged.relativeSourcePath,
    );
    if (destination.path != staged.destinationPath) {
      throw StateError('ProjectionLayout destination changed after staging');
    }
    if (staged.replaceProtocol != replaceProtocol ||
        staged.replaceProviderKind != replaceProviderKind ||
        staged.stagingRelativePath !=
            p.relative(staged.stagingPath, from: staged.workspaceRoot)) {
      throw StateError('ProjectionLayout replacement authority changed');
    }
    final bytes = swapPrimitive.readStaging(
      workspaceRoot: staged.workspaceRoot,
      stagingRelativePath: staged.stagingRelativePath,
      maxBytes: maxBytes,
    );
    if (bytes.length != staged.byteLength ||
        Digest.bytes(bytes) != staged.digest) {
      throw StateError('ProjectionLayout staging bytes changed');
    }
    final swapped = swapPrimitive.exchange(
      contentRoot: staged.contentRoot,
      destinationRelativePath: staged.relativeSourcePath,
      workspaceRoot: staged.workspaceRoot,
      stagingRelativePath: staged.stagingRelativePath,
      expectedDestinationDigest: expectedCurrentDigest,
      expectedStagingDigest: staged.digest,
      expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
      expectedStagingMetadataDigest: staged.sourceMetadataDigest,
      maxBytes: maxBytes,
    );
    if (swapped.providerKind != replaceProviderKind ||
        swapped.installedDigest != staged.digest ||
        swapped.installedMetadataDigest != staged.sourceMetadataDigest ||
        swapped.displacedMetadataDigest != staged.sourceMetadataDigest) {
      _exchangeBackExact(staged, swapped);
      throw StateError('ProjectionLayout installed source changed during swap');
    }
    if (swapped.displacedDigest != expectedCurrentDigest) {
      _exchangeBackExact(staged, swapped);
      throw ProjectionLayoutSourceConflict(
        expectedDigest: expectedCurrentDigest,
        observedDigest: swapped.displacedDigest,
      );
    }
    return ProjectionLayoutAtomicReplaceReceipt(
      replaceProtocol: replaceProtocol,
      providerKind: replaceProviderKind,
      recoverySlot: staged.stagingRelativePath,
      candidateDigest: swapped.installedDigest,
      displacedDigest: swapped.displacedDigest,
      candidateMetadataDigest: swapped.installedMetadataDigest,
      displacedMetadataDigest: swapped.displacedMetadataDigest,
    );
  }

  void _exchangeBackExact(
    ProjectionLayoutStagedWrite staged,
    ProjectionLayoutPreservingSwapResult first,
  ) {
    final restored = swapPrimitive.exchange(
      contentRoot: staged.contentRoot,
      destinationRelativePath: staged.relativeSourcePath,
      workspaceRoot: staged.workspaceRoot,
      stagingRelativePath: staged.stagingRelativePath,
      expectedDestinationDigest: first.installedDigest,
      expectedStagingDigest: first.displacedDigest,
      expectedDestinationMetadataDigest: first.installedMetadataDigest,
      expectedStagingMetadataDigest: first.displacedMetadataDigest,
      maxBytes: maxBytes,
    );
    if (restored.providerKind != replaceProviderKind ||
        restored.installedDigest != first.displacedDigest ||
        restored.displacedDigest != first.installedDigest ||
        restored.installedMetadataDigest != first.displacedMetadataDigest ||
        restored.displacedMetadataDigest != first.installedMetadataDigest) {
      try {
        final undoAmbiguousRestore = swapPrimitive.exchange(
          contentRoot: staged.contentRoot,
          destinationRelativePath: staged.relativeSourcePath,
          workspaceRoot: staged.workspaceRoot,
          stagingRelativePath: staged.stagingRelativePath,
          expectedDestinationDigest: restored.installedDigest,
          expectedStagingDigest: restored.displacedDigest,
          expectedDestinationMetadataDigest: restored.installedMetadataDigest,
          expectedStagingMetadataDigest: restored.displacedMetadataDigest,
          maxBytes: maxBytes,
        );
        if (undoAmbiguousRestore.providerKind != replaceProviderKind ||
            undoAmbiguousRestore.installedDigest != restored.displacedDigest ||
            undoAmbiguousRestore.displacedDigest != restored.installedDigest ||
            undoAmbiguousRestore.installedMetadataDigest !=
                restored.displacedMetadataDigest ||
            undoAmbiguousRestore.displacedMetadataDigest !=
                restored.installedMetadataDigest) {
          throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
        }
      } on Object {
        throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
      }
      throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
    }
  }

  @override
  ProjectionLayoutRecoverySlotObservation inspectRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
  }) {
    requireSupported();
    _requireRecoverySlot(relativeSourcePath, recoverySlot);
    final observed = swapPrimitive.observe(
      contentRoot: contentRoot,
      destinationRelativePath: relativeSourcePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: recoverySlot,
      maxBytes: maxBytes,
    );
    if (observed.providerKind != replaceProviderKind) {
      throw StateError('ProjectionLayout recovery provider changed');
    }
    return ProjectionLayoutRecoverySlotObservation(
      replaceProtocol: replaceProtocol,
      providerKind: replaceProviderKind,
      recoverySlot: recoverySlot,
      destinationDigest: observed.destinationDigest,
      stagingDigest: observed.stagingDigest,
      destinationMetadataDigest: observed.destinationMetadataDigest,
      stagingMetadataDigest: observed.stagingMetadataDigest,
    );
  }

  @override
  ProjectionLayoutAtomicReplaceReceipt exchangeRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
    required Digest expectedDestinationDigest,
    required Digest expectedRecoveryDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedRecoveryMetadataDigest,
  }) {
    requireSupported();
    _requireRecoverySlot(relativeSourcePath, recoverySlot);
    final swapped = swapPrimitive.exchange(
      contentRoot: contentRoot,
      destinationRelativePath: relativeSourcePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: recoverySlot,
      expectedDestinationDigest: expectedDestinationDigest,
      expectedStagingDigest: expectedRecoveryDigest,
      expectedDestinationMetadataDigest: expectedDestinationMetadataDigest,
      expectedStagingMetadataDigest: expectedRecoveryMetadataDigest,
      maxBytes: maxBytes,
    );
    if (swapped.providerKind != replaceProviderKind) {
      throw StateError('ProjectionLayout recovery provider changed');
    }
    return ProjectionLayoutAtomicReplaceReceipt(
      replaceProtocol: replaceProtocol,
      providerKind: replaceProviderKind,
      recoverySlot: recoverySlot,
      candidateDigest: swapped.installedDigest,
      displacedDigest: swapped.displacedDigest,
      candidateMetadataDigest: swapped.installedMetadataDigest,
      displacedMetadataDigest: swapped.displacedMetadataDigest,
    );
  }

  void _requireRecoverySlot(String relativeSourcePath, String recoverySlot) {
    if (relativeSourcePath == recoverySlot ||
        p.isAbsolute(recoverySlot) ||
        p.normalize(recoverySlot) != recoverySlot) {
      throw ArgumentError('Invalid ProjectionLayout recovery slot');
    }
  }

  @override
  List<int> readStaged(ProjectionLayoutStagedWrite staged) =>
      swapPrimitive.readStaging(
        workspaceRoot: staged.workspaceRoot,
        stagingRelativePath: staged.stagingRelativePath,
        maxBytes: maxBytes,
      );

  File _confinedSourceFile({
    required String contentRoot,
    required String relativeSourcePath,
  }) {
    final root = p.normalize(p.absolute(contentRoot));
    final normalizedRelative = p.normalize(relativeSourcePath);
    if (p.isAbsolute(relativeSourcePath) ||
        normalizedRelative == '.' ||
        normalizedRelative == '..' ||
        normalizedRelative.startsWith('../') ||
        normalizedRelative != relativeSourcePath) {
      throw ArgumentError.value(relativeSourcePath, 'relativeSourcePath');
    }
    _requireRegularDirectoryTree(root);
    final destination = p.normalize(p.join(root, normalizedRelative));
    if (!p.isWithin(root, destination)) {
      throw FileSystemException(
        'ProjectionLayout source escapes content root',
        destination,
      );
    }
    var current = root;
    final segments = p.split(p.relative(destination, from: root));
    for (var index = 0; index < segments.length; index += 1) {
      current = p.join(current, segments[index]);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link || Link(current).existsSync()) {
        throw FileSystemException(
          'Links are forbidden in ProjectionLayout source paths',
          current,
        );
      }
      if (index < segments.length - 1 &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'ProjectionLayout source parent must be a directory',
          current,
        );
      }
    }
    _requireRegularNonLink(destination, label: 'ProjectionLayout source');
    return File(destination);
  }
}

/// Coordinates a preserving source exchange, prepared WAL, publication, and
/// durable commit under the store's single continuous authority lock.
final class ConfiguredProjectionLayoutPromotionExecutor
    implements ExperienceAuthoringPromotionExecutor {
  const ConfiguredProjectionLayoutPromotionExecutor({
    required this.configuration,
    required this.coordinator,
    required this.contentAuthority,
  });

  final LoadedWorkspaceConfiguration configuration;
  final ProjectionLayoutPromotionCoordinator coordinator;
  final ProjectionLayoutContentAuthority contentAuthority;

  @override
  ExperiencePromotionReceipt promote({
    required ExperiencePromotionApplyRequest request,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
    required Set<Digest> allowedArtifactDigests,
    required DateTime promotedAt,
    required StoredAuthoringAttempt Function(ExperiencePromotionReceipt receipt)
    successAttemptFactory,
    required StoredAuthoringAttempt rollbackAttempt,
  }) {
    final token = request.digest.value.substring('sha256:'.length);
    return coordinator.promote(
      configuration: configuration,
      subject: request.subject,
      intentId: 'promotion-${token.substring(0, 32)}',
      receiptId: ExperiencePromotionReceiptId(
        'promotion-receipt-${token.substring(0, 32)}',
      ),
      changeSet: changeSet,
      reviewPacket: reviewPacket,
      allowedArtifactDigests: allowedArtifactDigests,
      grantDigest: request.grantDigest,
      promotedAt: promotedAt,
      contentAuthority: contentAuthority,
      successAttemptFactory: successAttemptFactory,
      rollbackAttempt: rollbackAttempt,
    );
  }

  List<ExperiencePromotionReceipt> recoverPending() =>
      coordinator.recoverPending(
        configuration: configuration,
        contentAuthority: contentAuthority,
      );
}

final class ProjectionLayoutPromotionCoordinator {
  const ProjectionLayoutPromotionCoordinator({
    required this.store,
    this.loader = const BoundedWorkspaceAuthoringLoader(),
    this.compiler = const ProjectionLayoutPromotionCompiler(),
    this.fileWriter = const FilesystemProjectionLayoutAtomicFileWriter(),
  });

  final FilesystemExperienceAuthoringStore store;
  final BoundedWorkspaceAuthoringLoader loader;
  final ProjectionLayoutPromotionCompiler compiler;
  final ProjectionLayoutAtomicFileWriter fileWriter;

  ExperiencePromotionReceipt promote({
    required LoadedWorkspaceConfiguration configuration,
    required AuthoringSubjectRef subject,
    required String intentId,
    required ExperiencePromotionReceiptId receiptId,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
    required Set<Digest> allowedArtifactDigests,
    required Digest grantDigest,
    required DateTime promotedAt,
    required ProjectionLayoutContentAuthority contentAuthority,
    StoredAuthoringAttempt Function(ExperiencePromotionReceipt receipt)?
    successAttemptFactory,
    StoredAuthoringAttempt? rollbackAttempt,
  }) {
    fileWriter.requireSupported();
    return store.withTransaction((transaction) {
      try {
        _validateConfigurationSubject(configuration, subject);
        if ((successAttemptFactory == null) != (rollbackAttempt == null)) {
          throw ArgumentError(
            'Promotion effect success and rollback attempts must be paired',
          );
        }
        final existing = transaction.findPendingPromotion(intentId);
        if (existing != null) {
          _validatePendingConfiguration(configuration, existing);
          final expectedSuccess = successAttemptFactory?.call(existing.receipt);
          if (existing.grantDigest != grantDigest ||
              expectedSuccess == null ||
              rollbackAttempt == null ||
              existing.successAttempt == null ||
              existing.rollbackAttempt == null ||
              !_sameAttemptBinding(existing.successAttempt!, expectedSuccess) ||
              !_sameAttemptBinding(
                existing.rollbackAttempt!,
                rollbackAttempt,
              )) {
            throw StateError(
              'Prepared promotion belongs to a different exact request',
            );
          }
          return _applyPrepared(
            transaction: transaction,
            configuration: configuration,
            pending: existing,
            contentAuthority: contentAuthority,
          );
        }
        final stored = transaction.requireDraft(subject);
        final baseLayout = transaction.requireBaseLayout(stored);
        const LayoutDraftEngine().validateChangeSet(
          changeSet: changeSet,
          draft: stored.draft,
          baseLayout: baseLayout,
        );
        final currentCorpus = loader.loadFromConfiguration(configuration);
        final currentContent = compiler.compileCurrent(currentCorpus);
        final topology = currentContent.experienceBundle?.topology;
        if (topology == null) {
          throw StateError('Experience topology is absent');
        }
        const ExperienceReviewPacketCompiler().validatePacket(
          packet: reviewPacket,
          changeSet: changeSet,
          catalog: currentContent.catalog,
          topology: topology,
          allowedArtifactDigests: allowedArtifactDigests,
        );
        if (!reviewPacket.isPromotable) {
          throw StateError('Current review packet is not promotable');
        }
        final candidateLayout = const LayoutDraftEngine().materialize(
          draft: stored.draft,
          baseLayout: baseLayout,
        );
        if (candidateLayout.digest != changeSet.comparison.afterLayoutDigest ||
            candidateLayout.digest == baseLayout.digest) {
          throw StateError('Promotion candidate does not match the ChangeSet');
        }
        final prepared = compiler.prepare(
          corpus: currentCorpus,
          subject: subject,
          expectedBaseLayoutDigest: stored.draft.baseLayoutDigest,
          expectedSourceDigest: stored.draft.baseSourceDigest,
          candidateLayout: candidateLayout,
        );
        final previousContentSetDigest = contentAuthority
            .previewContentSetDigest(prepared.currentContent);
        final resultContentSetDigest = contentAuthority.previewContentSetDigest(
          prepared.candidateContent,
        );
        if (previousContentSetDigest != stored.draft.contentSetDigest ||
            resultContentSetDigest == previousContentSetDigest) {
          throw StateError('Content-set preview does not bind the draft base');
        }
        final history = transaction.promotionHistory(subject);
        final previousReceipt = history.lastOrNull;
        final receipt = ExperiencePromotionReceipt(
          id: receiptId,
          sequence: (previousReceipt?.sequence ?? 0) + 1,
          previousReceiptDigest: previousReceipt?.digest,
          subject: subject,
          draftId: stored.draft.id,
          draftDigest: stored.draft.digest,
          draftRevision: stored.draft.revision,
          sourceDigest: prepared.originalSourceDigest,
          resultSourceDigest: prepared.candidateSourceDigest,
          previousContentSetDigest: previousContentSetDigest,
          resultContentSetDigest: resultContentSetDigest,
          layoutDigest: prepared.candidateLayout.digest,
          changeSetId: changeSet.id,
          changeSetDigest: changeSet.digest,
          reviewPacketId: reviewPacket.id,
          reviewPacketDigest: reviewPacket.digest,
          promotedAt: promotedAt,
        );
        final successAttempt = successAttemptFactory?.call(receipt);
        final recoverySlot = fileWriter.recoverySlot(
          subject: subject,
          relativeSourcePath: prepared.relativeSourcePath,
        );
        if (transaction.pendingPromotions().any(
          (active) =>
              active.relativeSourcePath == prepared.relativeSourcePath ||
              active.recoverySlot == recoverySlot,
        )) {
          throw const ExperienceAuthoringStoreFailure(
            ExperienceAuthoringStoreErrorCode.promotionConflict,
          );
        }
        final stagedBeforeWal = fileWriter.stage(
          workspaceRoot: configuration.workspaceRoot,
          contentRoot: configuration.contentRoot,
          subject: subject,
          relativeSourcePath: prepared.relativeSourcePath,
          bytes: prepared.candidateSourceBytes,
        );
        final pending = StoredProjectionLayoutPromotion(
          intentId: intentId,
          subject: subject,
          relativeSourcePath: prepared.relativeSourcePath,
          replaceProtocol: fileWriter.replaceProtocol,
          replaceProviderKind: fileWriter.replaceProviderKind,
          recoverySlot: recoverySlot,
          configurationAuthorityDigest:
              projectionLayoutPromotionConfigurationAuthorityDigest(
                configuration,
                subject,
              ),
          sourceMetadataDigest: stagedBeforeWal.sourceMetadataDigest,
          originalSourceBlobDigest: prepared.originalSourceDigest,
          candidateSourceBlobDigest: prepared.candidateSourceDigest,
          originalCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
            prepared.currentContent,
          ),
          candidateCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
            prepared.candidateContent,
          ),
          receipt: receipt,
          grantDigest: grantDigest,
          successAttempt: successAttempt,
          rollbackAttempt: rollbackAttempt,
          preparedAt: promotedAt,
        );
        _requireStagedBinding(stagedBeforeWal, pending);
        StoredProjectionLayoutPromotion durablePending;
        try {
          durablePending = transaction.preparePromotion(
            promotion: pending,
            originalSourceBytes: prepared.originalSourceBytes,
            candidateSourceBytes: prepared.candidateSourceBytes,
          );
        } catch (error) {
          try {
            final observed = transaction.findPendingPromotion(intentId);
            if (observed == null || !_samePending(observed, pending)) rethrow;
            durablePending = observed;
          } catch (verificationError) {
            if (identical(verificationError, error)) rethrow;
            throw _AuthoringJournalOutcomeUnknown(error, verificationError);
          }
        }
        return _applyPrepared(
          transaction: transaction,
          configuration: configuration,
          pending: durablePending,
          contentAuthority: contentAuthority,
        );
      } on ExperienceAuthoringFrameLimitFailure {
        rethrow;
      } on ProjectionLayoutPromotionFailure {
        rethrow;
      } catch (error) {
        throw ProjectionLayoutPromotionFailure(
          phase: ProjectionLayoutPromotionPhase.prepare,
          cause: error,
        );
      }
    });
  }

  List<ExperiencePromotionReceipt> recoverPending({
    required LoadedWorkspaceConfiguration configuration,
    required ProjectionLayoutContentAuthority contentAuthority,
  }) {
    fileWriter.requireSupported();
    return store.withTransaction((transaction) {
      final recovered = <ExperiencePromotionReceipt>[];
      for (final pending in transaction.pendingPromotions()) {
        _validateConfigurationSubject(configuration, pending.subject);
        _validatePendingConfiguration(configuration, pending);
        try {
          _requirePendingWriterBinding(pending);
          final rollbackAttempt = pending.rollbackAttempt;
          final terminal = rollbackAttempt == null
              ? null
              : transaction.findAttempt(rollbackAttempt.requestId);
          if (terminal != null) {
            if (!_sameAttempt(terminal, rollbackAttempt!)) {
              throw StateError(
                'Promotion WAL conflicts with its terminal attempt',
              );
            }
            _resolveFailedPending(
              transaction: transaction,
              configuration: configuration,
              pending: pending,
              contentAuthority: contentAuthority,
            );
            continue;
          }
          final observed = _observePair(configuration, pending);
          final installedWithBackup =
              _isPair(
                observed,
                destination: pending.candidateSourceDigest,
                recovery: pending.originalSourceDigest,
              ) &&
              _hasExpectedMetadata(
                observed,
                pending,
                destination: true,
                recovery: true,
              );
          final installedWithoutBackup =
              _isPair(
                observed,
                destination: pending.candidateSourceDigest,
                recovery: null,
              ) &&
              _hasExpectedMetadata(
                observed,
                pending,
                destination: true,
                recovery: false,
              );
          if (installedWithBackup || installedWithoutBackup) {
            _publishCandidate(
              configuration: configuration,
              pending: pending,
              contentAuthority: contentAuthority,
            );
            final committed = _commitDurably(transaction, pending);
            recovered.add(committed.receipt);
          } else if (_isExactOriginalRecoveryState(observed, pending)) {
            _publishOriginal(
              configuration: configuration,
              pending: pending,
              contentAuthority: contentAuthority,
            );
            _rollbackDurably(transaction, pending);
          } else if (observed.destinationDigest ==
                  pending.candidateSourceDigest &&
              observed.stagingDigest != null) {
            _exchangePairExact(
              configuration: configuration,
              pending: pending,
              expectedDestination: pending.candidateSourceDigest,
              expectedRecovery: observed.stagingDigest!,
            );
            throw StateError(
              'Promotion recovery restored an external source from the slot',
            );
          } else {
            throw StateError('Promotion recovery source pair is ambiguous');
          }
        } catch (error) {
          final afterFailure = _observePair(configuration, pending);
          if (_isPair(
            afterFailure,
            destination: pending.candidateSourceDigest,
            recovery: null,
          )) {
            throw ProjectionLayoutPromotionFailure(
              phase: ProjectionLayoutPromotionPhase.recovery,
              cause: error,
              recoveryCause:
                  const ProjectionLayoutPreservingSwapFailure.outcomeUnknown(),
            );
          }
          try {
            _failDurably(transaction, pending);
          } catch (terminalError) {
            throw ProjectionLayoutPromotionFailure(
              phase: ProjectionLayoutPromotionPhase.recovery,
              cause: error,
              recoveryCause: terminalError,
            );
          }
          throw ProjectionLayoutPromotionFailure(
            phase: ProjectionLayoutPromotionPhase.recovery,
            cause: error,
          );
        }
      }
      return List<ExperiencePromotionReceipt>.unmodifiable(recovered);
    });
  }

  ExperiencePromotionReceipt _applyPrepared({
    required ExperienceAuthoringStoreTransaction transaction,
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required ProjectionLayoutContentAuthority contentAuthority,
  }) {
    _validateConfigurationSubject(configuration, pending.subject);
    _validatePendingConfiguration(configuration, pending);
    var phase = ProjectionLayoutPromotionPhase.stage;
    try {
      _requirePendingWriterBinding(pending);
      final observed = _observePair(configuration, pending);
      final originalWithCandidate = _isPair(
        observed,
        destination: pending.originalSourceDigest,
        recovery: pending.candidateSourceDigest,
      );
      final candidateWithOriginal = _isPair(
        observed,
        destination: pending.candidateSourceDigest,
        recovery: pending.originalSourceDigest,
      );
      final candidateWithoutBackup = _isPair(
        observed,
        destination: pending.candidateSourceDigest,
        recovery: null,
      );
      if (originalWithCandidate) {
        if (!_hasExpectedMetadata(
          observed,
          pending,
          destination: true,
          recovery: true,
        )) {
          throw StateError('Prepared promotion metadata is ambiguous');
        }
        final staged = _bindCandidate(
          transaction: transaction,
          configuration: configuration,
          pending: pending,
        );
        const SafeAuthoringParser().parse(
          utf8.decode(fileWriter.readStaged(staged), allowMalformed: false),
          sourceName: staged.stagingPath,
        );
        phase = ProjectionLayoutPromotionPhase.replace;
        // preparePromotion made the WAL durable before this preserving swap.
        // The validated exchange is the promotion's filesystem linearization
        // point. A later uncoordinated edit remains newer than this receipt and
        // is deliberately not overwritten by a false post-publish CAS check.
        final replaced = fileWriter.replace(
          staged,
          expectedCurrentDigest: pending.originalSourceDigest,
        );
        _requireReplaceReceipt(
          replaced,
          pending,
          expectedInstalled: pending.candidateSourceDigest,
          expectedDisplaced: pending.originalSourceDigest,
          expectedInstalledMetadata: pending.sourceMetadataDigest,
          expectedDisplacedMetadata: pending.sourceMetadataDigest,
        );
      } else if (candidateWithOriginal) {
        if (!_hasExpectedMetadata(
          observed,
          pending,
          destination: true,
          recovery: true,
        )) {
          throw StateError('Prepared promotion metadata is ambiguous');
        }
      } else if (candidateWithoutBackup) {
        if (!_hasExpectedMetadata(
          observed,
          pending,
          destination: true,
          recovery: false,
        )) {
          throw StateError('Prepared promotion metadata is ambiguous');
        }
      } else {
        throw StateError('Prepared promotion source pair is ambiguous');
      }

      final installed = _observePair(configuration, pending);
      final recoveryDigest = installed.stagingDigest;
      if (installed.destinationDigest != pending.candidateSourceDigest ||
          recoveryDigest != pending.originalSourceDigest &&
              recoveryDigest != null ||
          !_hasExpectedMetadata(
            installed,
            pending,
            destination: true,
            recovery: recoveryDigest != null,
          )) {
        throw StateError('Prepared promotion source pair is ambiguous');
      }
      _requirePair(
        configuration,
        pending,
        destination: pending.candidateSourceDigest,
        recovery: recoveryDigest,
        expectedDestinationMetadataDigest: pending.sourceMetadataDigest,
        expectedRecoveryMetadataDigest: recoveryDigest == null
            ? null
            : pending.sourceMetadataDigest,
      );
      phase = ProjectionLayoutPromotionPhase.publish;
      _publishCandidate(
        configuration: configuration,
        pending: pending,
        contentAuthority: contentAuthority,
      );
      phase = ProjectionLayoutPromotionPhase.commit;
      final committed = _commitDurably(transaction, pending);
      return committed.receipt;
    } catch (error) {
      if (error is ExperienceAuthoringStateDurabilityFailure ||
          store.hasDurabilityUncertainty) {
        final cause = error is _AuthoringJournalOutcomeUnknown
            ? error.cause
            : error;
        // A journal rename may already contain the commit even though its
        // parent fsync failed. Never restore the source against that visible
        // commit. Keep the durable prepare WAL/source pair intact so a new
        // process can classify whichever state survived the crash boundary.
        throw ProjectionLayoutPromotionFailure(
          phase: phase,
          cause: cause,
          recoveryCause:
              const ProjectionLayoutPreservingSwapFailure.outcomeUnknown(),
        );
      }
      if (error is _AuthoringJournalOutcomeUnknown) {
        throw ProjectionLayoutPromotionFailure(
          phase: phase,
          cause: error.cause,
          recoveryCause: error.verificationCause,
        );
      }
      final afterFailure = _observePair(configuration, pending);
      if (_isPair(
        afterFailure,
        destination: pending.candidateSourceDigest,
        recovery: null,
      )) {
        throw ProjectionLayoutPromotionFailure(
          phase: phase,
          cause: error,
          recoveryCause:
              const ProjectionLayoutPreservingSwapFailure.outcomeUnknown(),
        );
      }
      Object? recoveryError;
      try {
        final observed = _observePair(configuration, pending);
        if (_isPair(
          observed,
          destination: pending.candidateSourceDigest,
          recovery: pending.originalSourceDigest,
        )) {
          _exchangePairExact(
            configuration: configuration,
            pending: pending,
            expectedDestination: pending.candidateSourceDigest,
            expectedRecovery: pending.originalSourceDigest,
          );
        } else if (observed.destinationDigest ==
                pending.candidateSourceDigest &&
            observed.stagingDigest != null) {
          _exchangePairExact(
            configuration: configuration,
            pending: pending,
            expectedDestination: pending.candidateSourceDigest,
            expectedRecovery: observed.stagingDigest!,
          );
          throw StateError(
            'Promotion failure restored an external source from the slot',
          );
        }
        final restored = _observePair(configuration, pending);
        if (_isExactOriginalRecoveryState(restored, pending)) {
          // The stable private slot is intentionally retained and reused.
        } else {
          throw StateError('Promotion failure source pair is ambiguous');
        }
        _publishOriginal(
          configuration: configuration,
          pending: pending,
          contentAuthority: contentAuthority,
        );
        _rollbackDurably(transaction, pending);
      } catch (rollbackError) {
        recoveryError = rollbackError;
        try {
          _failDurably(transaction, pending);
        } catch (terminalError) {
          recoveryError = _AuthoringJournalOutcomeUnknown(
            rollbackError,
            terminalError,
          );
        }
      }
      throw ProjectionLayoutPromotionFailure(
        phase: phase,
        cause: error,
        recoveryCause: recoveryError,
      );
    }
  }

  void _requirePendingWriterBinding(StoredProjectionLayoutPromotion pending) {
    final expectedSlot = fileWriter.recoverySlot(
      subject: pending.subject,
      relativeSourcePath: pending.relativeSourcePath,
    );
    if (pending.replaceProtocol != fileWriter.replaceProtocol ||
        pending.replaceProviderKind != fileWriter.replaceProviderKind ||
        pending.recoverySlot != expectedSlot) {
      throw StateError('Promotion WAL replacement authority changed');
    }
  }

  ProjectionLayoutStagedWrite _bindCandidate({
    required ExperienceAuthoringStoreTransaction transaction,
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
  }) {
    final candidateBytes = transaction.readPromotionSourceBlob(
      pending.candidateSourceBlobDigest,
    );
    final staged = fileWriter.bindStaged(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      subject: pending.subject,
      relativeSourcePath: pending.relativeSourcePath,
      digest: pending.candidateSourceDigest,
      byteLength: candidateBytes.length,
      sourceMetadataDigest: pending.sourceMetadataDigest,
    );
    _requireStagedBinding(staged, pending);
    return staged;
  }

  void _requireStagedBinding(
    ProjectionLayoutStagedWrite staged,
    StoredProjectionLayoutPromotion pending,
  ) {
    if (staged.replaceProtocol != pending.replaceProtocol ||
        staged.replaceProviderKind != pending.replaceProviderKind ||
        staged.stagingRelativePath != pending.recoverySlot ||
        staged.relativeSourcePath != pending.relativeSourcePath ||
        staged.digest != pending.candidateSourceDigest ||
        staged.sourceMetadataDigest != pending.sourceMetadataDigest) {
      throw StateError('Promotion staging does not match its WAL');
    }
  }

  ProjectionLayoutRecoverySlotObservation _observePair(
    LoadedWorkspaceConfiguration configuration,
    StoredProjectionLayoutPromotion pending,
  ) {
    final observed = fileWriter.inspectRecoverySlot(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      relativeSourcePath: pending.relativeSourcePath,
      recoverySlot: pending.recoverySlot,
    );
    if (observed.replaceProtocol != pending.replaceProtocol ||
        observed.providerKind != pending.replaceProviderKind ||
        observed.recoverySlot != pending.recoverySlot) {
      throw StateError('Promotion recovery observation authority changed');
    }
    return observed;
  }

  bool _isPair(
    ProjectionLayoutRecoverySlotObservation observed, {
    required Digest? destination,
    required Digest? recovery,
  }) =>
      observed.destinationDigest == destination &&
      observed.stagingDigest == recovery;

  bool _hasExpectedMetadata(
    ProjectionLayoutRecoverySlotObservation observed,
    StoredProjectionLayoutPromotion pending, {
    required bool destination,
    required bool recovery,
  }) =>
      (!destination ||
          observed.destinationMetadataDigest == pending.sourceMetadataDigest) &&
      (!recovery ||
          observed.stagingMetadataDigest == pending.sourceMetadataDigest);

  bool _isExactOriginalRecoveryState(
    ProjectionLayoutRecoverySlotObservation observed,
    StoredProjectionLayoutPromotion pending,
  ) {
    if (_isPair(
      observed,
      destination: pending.originalSourceDigest,
      recovery: pending.candidateSourceDigest,
    )) {
      return _hasExpectedMetadata(
        observed,
        pending,
        destination: true,
        recovery: true,
      );
    }
    if (_isPair(
      observed,
      destination: pending.originalSourceDigest,
      recovery: null,
    )) {
      return _hasExpectedMetadata(
        observed,
        pending,
        destination: true,
        recovery: false,
      );
    }
    return false;
  }

  void _requirePair(
    LoadedWorkspaceConfiguration configuration,
    StoredProjectionLayoutPromotion pending, {
    required Digest? destination,
    required Digest? recovery,
    Digest? expectedDestinationMetadataDigest,
    Digest? expectedRecoveryMetadataDigest,
  }) {
    final observed = _observePair(configuration, pending);
    if (!_isPair(observed, destination: destination, recovery: recovery) ||
        expectedDestinationMetadataDigest != null &&
            observed.destinationMetadataDigest !=
                expectedDestinationMetadataDigest ||
        expectedRecoveryMetadataDigest != null &&
            observed.stagingMetadataDigest != expectedRecoveryMetadataDigest) {
      throw StateError('ProjectionLayout source pair changed');
    }
  }

  ProjectionLayoutAtomicReplaceReceipt _exchangePairExact({
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required Digest expectedDestination,
    required Digest expectedRecovery,
  }) {
    final before = _observePair(configuration, pending);
    final expectedDestinationMetadata = before.destinationMetadataDigest;
    final expectedRecoveryMetadata = before.stagingMetadataDigest;
    if (!_isPair(
          before,
          destination: expectedDestination,
          recovery: expectedRecovery,
        ) ||
        expectedDestinationMetadata != pending.sourceMetadataDigest ||
        expectedRecoveryMetadata == null) {
      throw StateError('ProjectionLayout source pair changed');
    }
    final swapped = fileWriter.exchangeRecoverySlot(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      relativeSourcePath: pending.relativeSourcePath,
      recoverySlot: pending.recoverySlot,
      expectedDestinationDigest: expectedDestination,
      expectedRecoveryDigest: expectedRecovery,
      expectedDestinationMetadataDigest: expectedDestinationMetadata!,
      expectedRecoveryMetadataDigest: expectedRecoveryMetadata,
    );
    try {
      _requireReplaceReceipt(
        swapped,
        pending,
        expectedInstalled: expectedRecovery,
        expectedDisplaced: expectedDestination,
        expectedInstalledMetadata: expectedRecoveryMetadata,
        expectedDisplacedMetadata: expectedDestinationMetadata,
      );
      _requirePair(
        configuration,
        pending,
        destination: expectedRecovery,
        recovery: expectedDestination,
        expectedDestinationMetadataDigest: expectedRecoveryMetadata,
        expectedRecoveryMetadataDigest: expectedDestinationMetadata,
      );
    } catch (error) {
      try {
        _restoreRecoveryExchange(
          configuration: configuration,
          pending: pending,
          first: swapped,
        );
      } catch (restoreError) {
        throw _AuthoringJournalOutcomeUnknown(error, restoreError);
      }
      rethrow;
    }
    return swapped;
  }

  void _restoreRecoveryExchange({
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required ProjectionLayoutAtomicReplaceReceipt first,
  }) {
    final restored = fileWriter.exchangeRecoverySlot(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      relativeSourcePath: pending.relativeSourcePath,
      recoverySlot: pending.recoverySlot,
      expectedDestinationDigest: first.candidateDigest,
      expectedRecoveryDigest: first.displacedDigest,
      expectedDestinationMetadataDigest: first.candidateMetadataDigest,
      expectedRecoveryMetadataDigest: first.displacedMetadataDigest,
    );
    if (restored.replaceProtocol == first.replaceProtocol &&
        restored.providerKind == first.providerKind &&
        restored.recoverySlot == first.recoverySlot &&
        restored.candidateDigest == first.displacedDigest &&
        restored.displacedDigest == first.candidateDigest &&
        restored.candidateMetadataDigest == first.displacedMetadataDigest &&
        restored.displacedMetadataDigest == first.candidateMetadataDigest) {
      return;
    }
    try {
      final undoAmbiguousRestore = fileWriter.exchangeRecoverySlot(
        workspaceRoot: configuration.workspaceRoot,
        contentRoot: configuration.contentRoot,
        relativeSourcePath: pending.relativeSourcePath,
        recoverySlot: pending.recoverySlot,
        expectedDestinationDigest: restored.candidateDigest,
        expectedRecoveryDigest: restored.displacedDigest,
        expectedDestinationMetadataDigest: restored.candidateMetadataDigest,
        expectedRecoveryMetadataDigest: restored.displacedMetadataDigest,
      );
      if (undoAmbiguousRestore.candidateDigest != restored.displacedDigest ||
          undoAmbiguousRestore.displacedDigest != restored.candidateDigest ||
          undoAmbiguousRestore.candidateMetadataDigest !=
              restored.displacedMetadataDigest ||
          undoAmbiguousRestore.displacedMetadataDigest !=
              restored.candidateMetadataDigest) {
        throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
      }
    } on Object {
      throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
    }
    throw const ProjectionLayoutPreservingSwapFailure.outcomeUnknown();
  }

  void _requireReplaceReceipt(
    ProjectionLayoutAtomicReplaceReceipt receipt,
    StoredProjectionLayoutPromotion pending, {
    required Digest expectedInstalled,
    required Digest expectedDisplaced,
    required Digest expectedInstalledMetadata,
    required Digest expectedDisplacedMetadata,
  }) {
    if (receipt.replaceProtocol != pending.replaceProtocol ||
        receipt.providerKind != pending.replaceProviderKind ||
        receipt.recoverySlot != pending.recoverySlot ||
        receipt.candidateDigest != expectedInstalled ||
        receipt.displacedDigest != expectedDisplaced ||
        receipt.candidateMetadataDigest != expectedInstalledMetadata ||
        receipt.displacedMetadataDigest != expectedDisplacedMetadata) {
      throw StateError('ProjectionLayout replacement receipt is ambiguous');
    }
  }

  void _publishCandidate({
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required ProjectionLayoutContentAuthority contentAuthority,
  }) {
    final candidate = _loadAndValidateContent(
      configuration: configuration,
      expectedDigest: pending.candidateCompiledCorpusDigest,
    );
    _publishExact(
      contentAuthority,
      candidate,
      pending.receipt.resultContentSetDigest,
    );
  }

  void _publishOriginal({
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required ProjectionLayoutContentAuthority contentAuthority,
  }) {
    final original = _loadAndValidateContent(
      configuration: configuration,
      expectedDigest: pending.originalCompiledCorpusDigest,
    );
    _publishExact(
      contentAuthority,
      original,
      pending.receipt.previousContentSetDigest,
    );
  }

  HostWorkspaceContent _loadAndValidateContent({
    required LoadedWorkspaceConfiguration configuration,
    required Digest expectedDigest,
  }) {
    final corpus = loader.loadFromConfiguration(configuration);
    final content = compiler.compileCurrent(corpus);
    if (projectionLayoutPromotionContentDigest(content) != expectedDigest) {
      throw StateError('Reloaded content differs from the promotion WAL');
    }
    return content;
  }

  void _publishExact(
    ProjectionLayoutContentAuthority authority,
    HostWorkspaceContent content,
    Digest expectedDigest,
  ) {
    if (authority.previewContentSetDigest(content) != expectedDigest ||
        authority.publish(content) != expectedDigest) {
      throw StateError('Published content-set digest differs from the WAL');
    }
  }

  ({ExperiencePromotionReceipt receipt, bool replayed}) _commitDurably(
    ExperienceAuthoringStoreTransaction transaction,
    StoredProjectionLayoutPromotion pending,
  ) {
    try {
      if (pending.successAttempt != null) {
        final attempt = transaction.finalizePromotionEffect(
          intentId: pending.intentId,
          outcome: StoredPromotionFinalization.committed,
        );
        if (!_sameAttempt(attempt, pending.successAttempt!)) {
          throw StateError('Promotion commit returned a different attempt');
        }
        return (receipt: pending.receipt, replayed: false);
      }
      return (
        receipt: transaction.commitPromotion(intentId: pending.intentId),
        replayed: false,
      );
    } catch (error) {
      try {
        final completed = transaction.findCompletedPromotion(pending.intentId);
        final terminal = pending.successAttempt == null
            ? null
            : transaction.findAttempt(pending.successAttempt!.requestId);
        if (completed != null &&
            completed.digest == pending.receipt.digest &&
            (pending.successAttempt == null ||
                terminal != null &&
                    _sameAttempt(terminal, pending.successAttempt!))) {
          return (receipt: completed, replayed: true);
        }
        if (transaction.findPendingPromotion(pending.intentId) != null) {
          rethrow;
        }
        throw StateError('Promotion commit outcome conflicts with its WAL');
      } catch (verificationError) {
        if (identical(verificationError, error)) rethrow;
        throw _AuthoringJournalOutcomeUnknown(error, verificationError);
      }
    }
  }

  void _rollbackDurably(
    ExperienceAuthoringStoreTransaction transaction,
    StoredProjectionLayoutPromotion pending,
  ) {
    try {
      if (pending.rollbackAttempt != null) {
        final attempt = transaction.finalizePromotionEffect(
          intentId: pending.intentId,
          outcome: StoredPromotionFinalization.rolledBack,
        );
        if (!_sameAttempt(attempt, pending.rollbackAttempt!)) {
          throw StateError('Promotion rollback returned a different attempt');
        }
      } else {
        transaction.rollbackPromotion(intentId: pending.intentId);
      }
    } catch (error) {
      try {
        final observed = transaction.findPendingPromotion(pending.intentId);
        final terminal = pending.rollbackAttempt == null
            ? null
            : transaction.findAttempt(pending.rollbackAttempt!.requestId);
        if (observed == null &&
            (pending.rollbackAttempt == null ||
                terminal != null &&
                    _sameAttempt(terminal, pending.rollbackAttempt!))) {
          return;
        }
        rethrow;
      } catch (verificationError) {
        if (identical(verificationError, error)) rethrow;
        throw _AuthoringJournalOutcomeUnknown(error, verificationError);
      }
    }
  }

  void _failDurably(
    ExperienceAuthoringStoreTransaction transaction,
    StoredProjectionLayoutPromotion pending,
  ) {
    if (pending.rollbackAttempt == null) return;
    try {
      final attempt = transaction.finalizePromotionEffect(
        intentId: pending.intentId,
        outcome: StoredPromotionFinalization.failed,
      );
      if (!_sameAttempt(attempt, pending.rollbackAttempt!)) {
        throw StateError('Promotion failure returned a different attempt');
      }
    } catch (error) {
      try {
        final terminal = transaction.findAttempt(
          pending.rollbackAttempt!.requestId,
        );
        if (transaction.findPendingPromotion(pending.intentId) != null &&
            terminal != null &&
            _sameAttempt(terminal, pending.rollbackAttempt!)) {
          return;
        }
        rethrow;
      } catch (verificationError) {
        if (identical(verificationError, error)) rethrow;
        throw _AuthoringJournalOutcomeUnknown(error, verificationError);
      }
    }
  }

  void _resolveFailedPending({
    required ExperienceAuthoringStoreTransaction transaction,
    required LoadedWorkspaceConfiguration configuration,
    required StoredProjectionLayoutPromotion pending,
    required ProjectionLayoutContentAuthority contentAuthority,
  }) {
    _requirePendingWriterBinding(pending);
    final observed = _observePair(configuration, pending);
    if (_isPair(
      observed,
      destination: pending.candidateSourceDigest,
      recovery: pending.originalSourceDigest,
    )) {
      _exchangePairExact(
        configuration: configuration,
        pending: pending,
        expectedDestination: pending.candidateSourceDigest,
        expectedRecovery: pending.originalSourceDigest,
      );
    } else if (observed.destinationDigest == pending.candidateSourceDigest &&
        observed.stagingDigest != null) {
      _exchangePairExact(
        configuration: configuration,
        pending: pending,
        expectedDestination: pending.candidateSourceDigest,
        expectedRecovery: observed.stagingDigest!,
      );
      throw StateError(
        'Failed promotion restored an external source from the slot',
      );
    }
    final restored = _observePair(configuration, pending);
    if (_isExactOriginalRecoveryState(restored, pending)) {
      // The stable private slot is intentionally retained and reused.
    } else {
      throw StateError('Failed promotion source pair is ambiguous');
    }
    _publishOriginal(
      configuration: configuration,
      pending: pending,
      contentAuthority: contentAuthority,
    );
    try {
      transaction.resolveFailedPromotion(intentId: pending.intentId);
    } catch (error) {
      try {
        final terminal = transaction.findAttempt(
          pending.rollbackAttempt!.requestId,
        );
        if (transaction.findPendingPromotion(pending.intentId) == null &&
            terminal != null &&
            _sameAttempt(terminal, pending.rollbackAttempt!)) {
          return;
        }
        rethrow;
      } catch (verificationError) {
        if (identical(verificationError, error)) rethrow;
        throw _AuthoringJournalOutcomeUnknown(error, verificationError);
      }
    }
  }

  bool _samePending(
    StoredProjectionLayoutPromotion left,
    StoredProjectionLayoutPromotion right,
  ) =>
      left.intentId == right.intentId &&
      left.receipt.digest == right.receipt.digest &&
      left.grantDigest == right.grantDigest &&
      left.relativeSourcePath == right.relativeSourcePath &&
      left.replaceProtocol == right.replaceProtocol &&
      left.replaceProviderKind == right.replaceProviderKind &&
      left.recoverySlot == right.recoverySlot &&
      left.configurationAuthorityDigest == right.configurationAuthorityDigest &&
      left.sourceMetadataDigest == right.sourceMetadataDigest &&
      left.originalSourceBlobDigest == right.originalSourceBlobDigest &&
      left.candidateSourceBlobDigest == right.candidateSourceBlobDigest &&
      left.originalCompiledCorpusDigest == right.originalCompiledCorpusDigest &&
      left.candidateCompiledCorpusDigest == right.candidateCompiledCorpusDigest;

  void _validateConfigurationSubject(
    LoadedWorkspaceConfiguration configuration,
    AuthoringSubjectRef subject,
  ) {
    if (p.normalize(p.absolute(configuration.workspaceRoot)) !=
            p.normalize(p.absolute(store.workspaceStore.workspaceRoot)) ||
        configuration.workspaceId != subject.workspaceId.value ||
        !configuration.applications.containsKey(subject.applicationId.value)) {
      throw StateError('Promotion WAL belongs to another configuration');
    }
  }

  void _validatePendingConfiguration(
    LoadedWorkspaceConfiguration configuration,
    StoredProjectionLayoutPromotion pending,
  ) {
    if (pending.configurationAuthorityDigest !=
        projectionLayoutPromotionConfigurationAuthorityDigest(
          configuration,
          pending.subject,
        )) {
      throw StateError('Promotion WAL configuration authority changed');
    }
  }
}

final class _AuthoringJournalOutcomeUnknown implements Exception {
  const _AuthoringJournalOutcomeUnknown(this.cause, this.verificationCause);

  final Object cause;
  final Object verificationCause;
}

bool _sameAttempt(StoredAuthoringAttempt left, StoredAuthoringAttempt right) =>
    left.digest == right.digest &&
    left.requestId == right.requestId &&
    left.family == right.family;

bool _sameAttemptBinding(
  StoredAuthoringAttempt left,
  StoredAuthoringAttempt right,
) =>
    left.family == right.family &&
    left.requestId == right.requestId &&
    left.requestDigest == right.requestDigest &&
    left.payloadDigest == right.payloadDigest &&
    left.subject == right.subject &&
    left.effect == right.effect &&
    left.operation == right.operation &&
    left.grantId == right.grantId &&
    left.grantDigest == right.grantDigest &&
    left.isError == right.isError;

void _requireRegularDirectoryTree(String rootPath) {
  final root = p.normalize(p.absolute(rootPath));
  var current = p.rootPrefix(root);
  for (final segment in p.split(root)) {
    if (segment == p.rootPrefix(root) || segment.isEmpty) continue;
    current = p.join(current, segment);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link || Link(current).existsSync()) {
      throw FileSystemException('Content root cannot contain links', current);
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException('Content root must be a directory', current);
    }
  }
}

void _requireRegularNonLink(String path, {required String label}) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.file || Link(path).existsSync()) {
    throw FileSystemException('$label must be a regular non-link file', path);
  }
}
