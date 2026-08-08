import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../workspace/workspace_catalog_loader.dart';
import 'host_workspace_service.dart';

final class HostContextBuilderService {
  const HostContextBuilderService({
    required this.workspace,
    required this.workspaceRoot,
    required this.sourceBacked,
  });

  final HostWorkspaceService workspace;
  final String workspaceRoot;
  final bool sourceBacked;

  ContextBuilderDescription describe() => ContextBuilderDescription(
    contentSetDigest: workspace.contentSetIdentity.contentSetDigest,
    supportedCategories: <ContextCategory>{
      if (sourceBacked) ContextCategory.sources,
      ContextCategory.images,
      ContextCategory.evidence,
      ContextCategory.history,
      ContextCategory.changes,
    },
    maximumBudgets: ExperienceContextBuilder.maximumBudgets,
  );

  ContextBuildResult build(ContextBuildRequest request) {
    final before = workspace.contentSetIdentity;
    if (request.expectedContentSetDigest != before.contentSetDigest) {
      throw StateError('Context content set changed; describe it again');
    }
    final bundle = workspace.experienceBundle;
    if (bundle == null) {
      throw StateError('Context Builder requires Experience topology');
    }
    final documents = sourceBacked
        ? _loadAndFence(before, bundle)
        : const <AuthoringDocument>[];
    final result = const ExperienceContextBuilder().build(
      request: request,
      currentContentSetDigest: before.contentSetDigest,
      inputs: ExperienceContextBuildInputs(
        catalog: workspace.snapshot.catalog,
        topology: bundle.topology,
        layouts: bundle.layouts,
        documents: documents,
        motion: workspace.motionManifest,
        scenarioLab: workspace.scenarioLabManifest,
      ),
    );
    final after = workspace.contentSetIdentity;
    if (after.contentSetDigest != before.contentSetDigest ||
        after.revision != before.revision) {
      throw StateError('Context content set changed while exporting');
    }
    return ContextBuildResult(bundle: result);
  }

  List<AuthoringDocument> _loadAndFence(
    ExperienceContentSetIdentity identity,
    ExperienceTopologyBundle expectedBundle,
  ) {
    final loaded = const WorkspaceCatalogLoader().load(
      startPath: workspaceRoot,
    );
    final catalog = const CatalogCompiler().compile(
      loaded.documents,
      layout: loaded.layout,
    );
    const topologyCompiler = ExperienceTopologyCompiler();
    final compiled = topologyCompiler.compile(
      loaded.documents,
      catalog: catalog,
    );
    final bundle = ExperienceTopologyBundle(
      catalog: catalog,
      topology: compiled.topology,
      layouts: compiled.layouts,
    );
    const facetCompiler = ScenarioFacetCompiler();
    final facets = facetCompiler.hasAuthoring(loaded.documents)
        ? facetCompiler.compile(loaded.documents, catalog: catalog)
        : null;
    const labCompiler = ScenarioLabCompiler();
    final lab = labCompiler.hasAuthoring(loaded.documents)
        ? labCompiler.compile(loaded.documents, catalog: catalog)
        : null;
    const motionCompiler = MotionManifestCompiler();
    final motion = motionCompiler.hasAuthoring(loaded.documents)
        ? motionCompiler.compile(
            loaded.documents,
            catalog: catalog,
            topology: compiled.topology,
          )
        : null;
    if (catalog.digest != identity.catalogDigest ||
        bundle.digest != expectedBundle.digest ||
        bundle.digest != identity.experienceTopologyBundleDigest ||
        facets?.digest != identity.scenarioFacetManifestDigest ||
        lab?.digest != identity.scenarioLabManifestDigest ||
        motion?.digest != identity.motionManifestDigest) {
      throw StateError('Context source changed; refresh the content set first');
    }
    return loaded.documents;
  }
}
