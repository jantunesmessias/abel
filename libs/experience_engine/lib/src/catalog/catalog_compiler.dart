import 'package:experience_contracts/experience_contracts.dart';

import 'authoring_parser.dart';

final class CatalogCompileException implements Exception {
  CatalogCompileException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues);

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

final class CatalogCompiler {
  const CatalogCompiler();

  CatalogManifest compile(
    Iterable<AuthoringDocument> source, {
    DistributionDescriptor? distribution,
    ConsumerLayout? layout,
  }) {
    final documents = source
        .where((document) => document.schemaVersion == 1)
        .toList(growable: false);
    final issues = <String>[];
    final keys = <String>{};
    for (final document in documents) {
      final key = '${document.kind.name}:${document.id}';
      if (!keys.add(key)) issues.add('duplicate document $key');
      _validateSpecShape(document, issues);
    }

    final workspaceDocuments = documents
        .where((document) => document.kind == AuthoringKind.workspace)
        .toList(growable: false);
    if (workspaceDocuments.length != 1) {
      issues.add('catalog requires exactly one Workspace document');
    }

    Workspace? workspace;
    if (workspaceDocuments.length == 1) {
      final document = workspaceDocuments.single;
      workspace = Workspace(
        id: _id(() => WorkspaceId(document.id), issues, document),
        displayName: _string(document, 'displayName', issues) ?? document.id,
      );
    }

    final applications = <Application>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.application,
    )) {
      applications.add(
        Application(
          id: _id(() => ApplicationId(document.id), issues, document),
          workspaceId: _id(
            () => WorkspaceId(
              _string(document, 'workspaceId', issues) ?? 'invalid',
            ),
            issues,
            document,
          ),
          displayName: _string(document, 'displayName', issues) ?? document.id,
          root: _string(document, 'root', issues) ?? '.',
          target: _string(document, 'target', issues) ?? 'local',
        ),
      );
    }

    final scenarios = <Scenario>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.scenario,
    )) {
      scenarios.add(
        Scenario(
          id: _id(() => ScenarioId(document.id), issues, document),
          applicationId: _id(
            () => ApplicationId(
              _string(document, 'applicationId', issues) ?? 'invalid',
            ),
            issues,
            document,
          ),
          title: _string(document, 'title', issues) ?? document.id,
          description: _optionalString(document, 'description', issues),
          sourceReferences: _sourceReferences(document, issues),
        ),
      );
    }

    final journeys = <Journey>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.journey,
    )) {
      journeys.add(
        Journey(
          id: _id(() => JourneyId(document.id), issues, document),
          applicationId: _id(
            () => ApplicationId(
              _string(document, 'applicationId', issues) ?? 'invalid',
            ),
            issues,
            document,
          ),
          title: _string(document, 'title', issues) ?? document.id,
          scenarioIds: _stringList(document, 'scenarioIds', issues)
              .map((value) => _id(() => ScenarioId(value), issues, document))
              .toList(growable: false),
        ),
      );
    }

    final transitions = <Transition>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.transition,
    )) {
      transitions.add(
        Transition(
          id: _id(() => TransitionId(document.id), issues, document),
          journeyId: _id(
            () =>
                JourneyId(_string(document, 'journeyId', issues) ?? 'invalid'),
            issues,
            document,
          ),
          from: _id(
            () => ScenarioId(_string(document, 'from', issues) ?? 'invalid'),
            issues,
            document,
          ),
          to: _id(
            () => ScenarioId(_string(document, 'to', issues) ?? 'invalid'),
            issues,
            document,
          ),
          label: _optionalString(document, 'label', issues),
        ),
      );
    }

    final executionBindings = <ScenarioExecutionBinding>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.scenarioExecutionBinding,
    )) {
      final launchProfileId = _optionalString(
        document,
        'launchProfileId',
        issues,
      );
      final checkpointId = _optionalString(document, 'checkpointId', issues);
      try {
        executionBindings.add(
          ScenarioExecutionBinding(
            id: _id(
              () => ScenarioExecutionBindingId(document.id),
              issues,
              document,
            ),
            scenarioId: _id(
              () => ScenarioId(
                _string(document, 'scenarioId', issues) ?? 'invalid',
              ),
              issues,
              document,
            ),
            targetId: _string(document, 'targetId', issues) ?? 'invalid',
            launchProfileId: launchProfileId,
            checkpointId: checkpointId,
            gatewayPresetId: _optionalString(
              document,
              'gatewayPresetId',
              issues,
            ),
          ),
        );
      } on ArgumentError catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      } on FormatException catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      }
    }

    final reviewGuides = <ReviewGuide>[];
    for (final document in documents.where(
      (document) => document.kind == AuthoringKind.reviewGuide,
    )) {
      try {
        reviewGuides.add(
          ReviewGuide(
            id: _id(() => ReviewGuideId(document.id), issues, document),
            applicationId: _id(
              () => ApplicationId(
                _string(document, 'applicationId', issues) ?? 'invalid',
              ),
              issues,
              document,
            ),
            title: _string(document, 'title', issues) ?? document.id,
            steps: _reviewGuideSteps(document, issues),
          ),
        );
      } on ArgumentError catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      } on FormatException catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      }
    }

    if (workspace != null) {
      for (final application in applications) {
        if (application.workspaceId != workspace.id) {
          issues.add(
            'Application ${application.id} references unknown Workspace ${application.workspaceId}',
          );
        }
      }
    }
    final applicationIds = applications.map((value) => value.id).toSet();
    final scenarioIds = scenarios.map((value) => value.id).toSet();
    final journeyIds = journeys.map((value) => value.id).toSet();
    final scenarioById = <ScenarioId, Scenario>{
      for (final scenario in scenarios) scenario.id: scenario,
    };
    final journeyById = <JourneyId, Journey>{
      for (final journey in journeys) journey.id: journey,
    };
    for (final scenario in scenarios) {
      if (!applicationIds.contains(scenario.applicationId)) {
        issues.add(
          'Scenario ${scenario.id} references unknown Application ${scenario.applicationId}',
        );
      }
    }
    for (final journey in journeys) {
      if (!applicationIds.contains(journey.applicationId)) {
        issues.add(
          'Journey ${journey.id} references unknown Application ${journey.applicationId}',
        );
      }
      for (final scenarioId in journey.scenarioIds) {
        final scenario = scenarioById[scenarioId];
        if (scenario == null ||
            scenario.applicationId != journey.applicationId) {
          issues.add(
            'Journey ${journey.id} references an unknown or cross-Application Scenario $scenarioId',
          );
        }
      }
    }
    for (final transition in transitions) {
      final journey = journeyById[transition.journeyId];
      if (!journeyIds.contains(transition.journeyId) || journey == null) {
        issues.add(
          'Transition ${transition.id} references unknown Journey ${transition.journeyId}',
        );
      }
      final from = scenarioById[transition.from];
      final to = scenarioById[transition.to];
      if (journey == null ||
          from == null ||
          to == null ||
          from.applicationId != journey.applicationId ||
          to.applicationId != journey.applicationId ||
          !journey.scenarioIds.contains(transition.from) ||
          !journey.scenarioIds.contains(transition.to)) {
        issues.add(
          'Transition ${transition.id} references an unknown or cross-Journey Scenario',
        );
      }
    }
    final bindingIds = executionBindings.map((value) => value.id).toSet();
    final bindingById = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
      for (final binding in executionBindings) binding.id: binding,
    };
    final gatewayPresetIds = documents
        .where((document) => document.kind == AuthoringKind.gatewayPreset)
        .map((document) => document.id)
        .toSet();
    for (final binding in executionBindings) {
      if (!scenarioIds.contains(binding.scenarioId)) {
        issues.add(
          'ScenarioExecutionBinding ${binding.id} references an unknown Scenario',
        );
      }
      if (binding.gatewayPresetId != null &&
          !gatewayPresetIds.contains(binding.gatewayPresetId)) {
        issues.add(
          'ScenarioExecutionBinding ${binding.id} references an unknown GatewayPreset',
        );
      }
    }
    for (final guide in reviewGuides) {
      if (!applicationIds.contains(guide.applicationId)) {
        issues.add('ReviewGuide ${guide.id} references an unknown Application');
      }
      for (final step in guide.steps) {
        if (!scenarioIds.contains(step.scenarioId) ||
            !bindingIds.contains(step.bindingId)) {
          issues.add(
            'ReviewGuide ${guide.id} step ${step.id} has an unknown ref',
          );
          continue;
        }
        final binding = bindingById[step.bindingId]!;
        final scenario = scenarioById[step.scenarioId]!;
        if (binding.scenarioId != step.scenarioId ||
            scenario.applicationId != guide.applicationId) {
          issues.add(
            'ReviewGuide ${guide.id} step ${step.id} crosses its granted Scenario/Application',
          );
        }
      }
    }
    if (issues.isNotEmpty || workspace == null) {
      throw CatalogCompileException(issues);
    }

    applications.sort((left, right) => left.id.value.compareTo(right.id.value));
    scenarios.sort((left, right) => left.id.value.compareTo(right.id.value));
    journeys.sort((left, right) => left.id.value.compareTo(right.id.value));
    transitions.sort((left, right) => left.id.value.compareTo(right.id.value));
    executionBindings.sort(
      (left, right) => left.id.value.compareTo(right.id.value),
    );
    reviewGuides.sort((left, right) => left.id.value.compareTo(right.id.value));
    return CatalogManifest(
      distribution: distribution ?? _defaultDistribution(),
      layout: layout ?? ConsumerLayout.standard,
      workspace: workspace,
      applications: applications,
      journeys: journeys,
      scenarios: scenarios,
      transitions: transitions,
      executionBindings: executionBindings,
      reviewGuides: reviewGuides,
    );
  }

  T _id<T>(
    T Function() create,
    List<String> issues,
    AuthoringDocument document,
  ) {
    try {
      return create();
    } on FormatException catch (error) {
      issues.add('${document.sourceName}: ${error.message}');
      return createInvalid<T>();
    }
  }

  T createInvalid<T>() {
    if (T == WorkspaceId) return WorkspaceId('invalid') as T;
    if (T == ApplicationId) return ApplicationId('invalid') as T;
    if (T == JourneyId) return JourneyId('invalid') as T;
    if (T == ScenarioId) return ScenarioId('invalid') as T;
    if (T == TransitionId) return TransitionId('invalid') as T;
    if (T == ScenarioExecutionBindingId) {
      return ScenarioExecutionBindingId('invalid') as T;
    }
    if (T == ReviewGuideId) return ReviewGuideId('invalid') as T;
    throw StateError('Unsupported ID type $T');
  }

  String? _string(AuthoringDocument document, String key, List<String> issues) {
    final value = document.spec[key];
    if (value is String && value.trim().isNotEmpty) return value;
    issues.add('${document.sourceName}: spec.$key must be a non-empty string');
    return null;
  }

  String? _optionalString(
    AuthoringDocument document,
    String key,
    List<String> issues,
  ) {
    final value = document.spec[key];
    if (value == null) return null;
    if (value is String) return value;
    issues.add('${document.sourceName}: spec.$key must be a string');
    return null;
  }

  List<String> _stringList(
    AuthoringDocument document,
    String key,
    List<String> issues,
  ) {
    final value = document.spec[key];
    if (value is List<Object?> && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    issues.add('${document.sourceName}: spec.$key must be an array of strings');
    return const <String>[];
  }

  List<SourceReference> _sourceReferences(
    AuthoringDocument document,
    List<String> issues,
  ) {
    final value = document.spec['sourceReferences'];
    if (value == null) return const <SourceReference>[];
    if (value is! List<Object?>) {
      issues.add(
        '${document.sourceName}: spec.sourceReferences must be an array',
      );
      return const <SourceReference>[];
    }
    final output = <SourceReference>[];
    for (final item in value) {
      if (item is! Map<String, Object?> ||
          item['repository'] is! String ||
          item['path'] is! String) {
        issues.add('${document.sourceName}: invalid sourceReference');
        continue;
      }
      output.add(
        SourceReference(
          repository: item['repository']! as String,
          path: item['path']! as String,
          symbol: item['symbol'] as String?,
        ),
      );
    }
    return output;
  }

  List<ReviewGuideStep> _reviewGuideSteps(
    AuthoringDocument document,
    List<String> issues,
  ) {
    final value = document.spec['steps'];
    if (value is! List<Object?>) {
      issues.add('${document.sourceName}: spec.steps must be an array');
      return const <ReviewGuideStep>[];
    }
    final output = <ReviewGuideStep>[];
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        issues.add('${document.sourceName}: invalid ReviewGuide step');
        continue;
      }
      const fields = <String>{
        'id',
        'instruction',
        'observationCriteria',
        'scenarioId',
        'bindingId',
      };
      if (item.length != fields.length ||
          item.keys.any((key) => !fields.contains(key)) ||
          item.values.any((entry) => entry is! String)) {
        issues.add('${document.sourceName}: invalid ReviewGuide step shape');
        continue;
      }
      try {
        output.add(
          ReviewGuideStep(
            id: item['id']! as String,
            instruction: item['instruction']! as String,
            observationCriteria: item['observationCriteria']! as String,
            scenarioId: ScenarioId(item['scenarioId']! as String),
            bindingId: ScenarioExecutionBindingId(item['bindingId']! as String),
          ),
        );
      } on ArgumentError catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      } on FormatException catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      }
    }
    return output;
  }

  DistributionDescriptor _defaultDistribution() => DistributionDescriptor(
    id: 'full-local',
    displayName: 'Abel',
    coreCompatibility: '^0.1.0',
    defaultLayout: ConsumerLayout.standard,
  );

  void _validateSpecShape(AuthoringDocument document, List<String> issues) {
    final allowed = switch (document.kind) {
      AuthoringKind.workspace => const <String>{'displayName'},
      AuthoringKind.application => const <String>{
        'workspaceId',
        'displayName',
        'root',
        'target',
      },
      AuthoringKind.journey => const <String>{
        'applicationId',
        'title',
        'scenarioIds',
      },
      AuthoringKind.scenario => const <String>{
        'applicationId',
        'title',
        'description',
        'sourceReferences',
      },
      AuthoringKind.transition => const <String>{
        'journeyId',
        'from',
        'to',
        'label',
      },
      AuthoringKind.gatewayScope => const <String>{'displayName', 'routeIds'},
      AuthoringKind.gatewayPreset => const <String>{
        'scopeId',
        'description',
        'routeIds',
        'initialState',
        'backendMode',
      },
      AuthoringKind.gatewayRoute => const <String>{
        'scopeId',
        'method',
        'pathTemplate',
        'requiredQuery',
        'appliesTo',
        'policy',
        'fixtureId',
        'upstreamProfileId',
        'faultProfile',
      },
      AuthoringKind.gatewayFixture => const <String>{
        'status',
        'headers',
        'bodyFile',
        'mediaType',
      },
      AuthoringKind.scenarioExecutionBinding => const <String>{
        'scenarioId',
        'targetId',
        'launchProfileId',
        'checkpointId',
        'gatewayPresetId',
      },
      AuthoringKind.reviewGuide => const <String>{
        'applicationId',
        'title',
        'steps',
      },
      AuthoringKind.board => const <String>{
        'applicationId',
        'title',
        'projectionIds',
      },
      AuthoringKind.experienceProjection => const <String>{
        'boardId',
        'applicationId',
        'title',
        'journeyId',
        'projectionKind',
        'nodeInstanceIds',
        'edgeInstanceIds',
      },
      AuthoringKind.nodeInstance => const <String>{
        'projectionId',
        'scenarioId',
        'comparisonRole',
      },
      AuthoringKind.edgeInstance => const <String>{
        'projectionId',
        'transitionId',
        'fromNodeId',
        'toNodeId',
      },
      AuthoringKind.projectionLayout => const <String>{
        'projectionId',
        'nodeFrames',
        'groups',
        'lanes',
        'annotations',
        'camera',
      },
      AuthoringKind.scenarioKindDefinition ||
      AuthoringKind.experienceSurface ||
      AuthoringKind.scenarioState ||
      AuthoringKind.ownershipArea ||
      AuthoringKind.scenarioTag ||
      AuthoringKind.experienceComponent ||
      AuthoringKind.scenarioFixture ||
      AuthoringKind.formFactor ||
      AuthoringKind.presentationFrame ||
      AuthoringKind.scenarioFacet ||
      AuthoringKind.appAdapterCapability ||
      AuthoringKind.scenarioControl ||
      AuthoringKind.scenarioLabOperation ||
      AuthoringKind.scenarioScript ||
      AuthoringKind.automatedAcceptanceCriterion ||
      AuthoringKind.requiredEvidence ||
      AuthoringKind.scenarioComparisonBinding ||
      AuthoringKind.visualComparisonPolicy ||
      AuthoringKind.semanticComparisonPolicy ||
      AuthoringKind.humanApprovalRequirement ||
      AuthoringKind.supplementalArtifact ||
      AuthoringKind.scenarioLabPlan ||
      AuthoringKind.motionSequence => const <String>{},
    };
    for (final key in document.spec.keys) {
      if (!allowed.contains(key)) {
        issues.add('${document.sourceName}: unknown field spec.$key');
      }
    }
  }
}
