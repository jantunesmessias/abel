import '../digest.dart';

abstract base class OpaqueId {
  const OpaqueId(this.value);

  final String value;

  static void validate(String value, String kind) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value)) {
      throw FormatException(
        '$kind ID is not a valid opaque identifier: $value',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is OpaqueId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class WorkspaceId extends OpaqueId {
  factory WorkspaceId(String value) {
    OpaqueId.validate(value, 'Workspace');
    return WorkspaceId._(value);
  }

  const WorkspaceId._(super.value);
}

final class ApplicationId extends OpaqueId {
  factory ApplicationId(String value) {
    OpaqueId.validate(value, 'Application');
    return ApplicationId._(value);
  }

  const ApplicationId._(super.value);
}

final class JourneyId extends OpaqueId {
  factory JourneyId(String value) {
    OpaqueId.validate(value, 'Journey');
    return JourneyId._(value);
  }

  const JourneyId._(super.value);
}

final class ScenarioId extends OpaqueId {
  factory ScenarioId(String value) {
    OpaqueId.validate(value, 'Scenario');
    return ScenarioId._(value);
  }

  const ScenarioId._(super.value);
}

final class TransitionId extends OpaqueId {
  factory TransitionId(String value) {
    OpaqueId.validate(value, 'Transition');
    return TransitionId._(value);
  }

  const TransitionId._(super.value);
}

final class ScenarioExecutionBindingId extends OpaqueId {
  factory ScenarioExecutionBindingId(String value) {
    OpaqueId.validate(value, 'ScenarioExecutionBinding');
    return ScenarioExecutionBindingId._(value);
  }

  const ScenarioExecutionBindingId._(super.value);
}

final class ReviewGuideId extends OpaqueId {
  factory ReviewGuideId(String value) {
    OpaqueId.validate(value, 'ReviewGuide');
    return ReviewGuideId._(value);
  }

  const ReviewGuideId._(super.value);
}

final class DistributionDescriptor {
  DistributionDescriptor({
    required this.id,
    required this.displayName,
    required this.coreCompatibility,
    required this.defaultLayout,
    List<String> commandAliases = const <String>[],
  }) : commandAliases = List<String>.unmodifiable(commandAliases) {
    OpaqueId.validate(id, 'Distribution');
    _catalogNonEmpty(displayName, 'displayName');
    if (!RegExp(r'^\^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(coreCompatibility)) {
      throw FormatException('Invalid coreCompatibility: $coreCompatibility');
    }
    _validateAliases(this.commandAliases);
  }

  static const int schemaVersion = 1;

  final String id;
  final String displayName;
  final String coreCompatibility;
  final ConsumerLayout defaultLayout;
  final List<String> commandAliases;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'displayName': displayName,
    'coreCompatibility': coreCompatibility,
    'defaultLayout': defaultLayout.toJson(),
    'commandAliases': commandAliases,
  };

  factory DistributionDescriptor.fromJson(Object? value) {
    final json = _catalogObject(value, 'DistributionDescriptor');
    _catalogOnly(json, const <String>{
      'schemaVersion',
      'id',
      'displayName',
      'coreCompatibility',
      'defaultLayout',
      'commandAliases',
    }, 'DistributionDescriptor');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Invalid DistributionDescriptor version');
    }
    return DistributionDescriptor(
      id: _catalogString(json, 'id', 'DistributionDescriptor'),
      displayName: _catalogString(
        json,
        'displayName',
        'DistributionDescriptor',
      ),
      coreCompatibility: _catalogString(
        json,
        'coreCompatibility',
        'DistributionDescriptor',
      ),
      defaultLayout: ConsumerLayout.fromJson(json['defaultLayout']),
      commandAliases: _catalogStringList(
        json['commandAliases'],
        'DistributionDescriptor.commandAliases',
      ),
    );
  }
}

final class ConsumerLayout {
  ConsumerLayout({
    required this.configFile,
    required this.contentRoot,
    required this.localConfigFile,
    required this.toolingEntrypoint,
    this.configEnvironmentVariable = 'DEVEX_CONFIG',
    List<String> commandAliases = const <String>['devex'],
  }) : commandAliases = List<String>.unmodifiable(commandAliases) {
    for (final path in <String>[
      configFile,
      contentRoot,
      localConfigFile,
      toolingEntrypoint,
    ]) {
      _validateRelativePath(path);
    }
    if (!RegExp(
      r'^[A-Z][A-Z0-9_]{2,127}$',
    ).hasMatch(configEnvironmentVariable)) {
      throw FormatException(
        'Invalid config environment variable: $configEnvironmentVariable',
      );
    }
    _validateAliases(this.commandAliases);
  }

  static final ConsumerLayout devexDefault = ConsumerLayout(
    configFile: 'devex.yaml',
    contentRoot: '.devex',
    localConfigFile: 'devex.local.yaml',
    toolingEntrypoint: 'tool/devex_main.dart',
  );

  final String configFile;
  final String configEnvironmentVariable;
  final String contentRoot;
  final String localConfigFile;
  final String toolingEntrypoint;
  final List<String> commandAliases;

  Map<String, Object?> toJson() => <String, Object?>{
    'configFile': configFile,
    'configEnvironmentVariable': configEnvironmentVariable,
    'contentRoot': contentRoot,
    'localConfigFile': localConfigFile,
    'toolingEntrypoint': toolingEntrypoint,
    'commandAliases': commandAliases,
  };

  factory ConsumerLayout.fromJson(Object? value) {
    final json = _catalogObject(value, 'ConsumerLayout');
    _catalogOnly(json, const <String>{
      'configFile',
      'configEnvironmentVariable',
      'contentRoot',
      'localConfigFile',
      'toolingEntrypoint',
      'commandAliases',
    }, 'ConsumerLayout');
    return ConsumerLayout(
      configFile: _catalogString(json, 'configFile', 'ConsumerLayout'),
      configEnvironmentVariable: _catalogString(
        json,
        'configEnvironmentVariable',
        'ConsumerLayout',
      ),
      contentRoot: _catalogString(json, 'contentRoot', 'ConsumerLayout'),
      localConfigFile: _catalogString(
        json,
        'localConfigFile',
        'ConsumerLayout',
      ),
      toolingEntrypoint: _catalogString(
        json,
        'toolingEntrypoint',
        'ConsumerLayout',
      ),
      commandAliases: _catalogStringList(
        json['commandAliases'],
        'ConsumerLayout.commandAliases',
      ),
    );
  }

  static void _validateRelativePath(String value) {
    final segments = value.replaceAll(r'\', '/').split('/');
    if (value.isEmpty ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value) ||
        segments.contains('..')) {
      throw FormatException(
        'ConsumerLayout path must be workspace-relative: $value',
      );
    }
  }
}

void _validateAliases(List<String> aliases) {
  if (aliases.toSet().length != aliases.length ||
      aliases.any(
        (alias) => !RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(alias),
      )) {
    throw const FormatException('Command aliases are invalid or duplicated');
  }
}

Map<String, Object?> _catalogObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

String _catalogString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

List<String> _catalogStringList(Object? value, String path) {
  if (value is! List<Object?> ||
      value.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain non-empty strings');
  }
  return value.cast<String>();
}

String? _catalogOptionalString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

String _catalogBoundedString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) {
  final value = _catalogString(json, key, path);
  if (value.length > maxLength) {
    throw FormatException('$path.$key exceeds $maxLength characters');
  }
  return value;
}

List<Object?> _catalogList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  if (value.length > maxItems) {
    throw FormatException('$path.$key exceeds $maxItems items');
  }
  return value;
}

void _catalogVerifyDigest(
  Map<String, Object?> json,
  Digest actual,
  String path,
) {
  final declared = _catalogString(json, 'digest', path);
  if (declared != actual.value) {
    throw FormatException('$path digest mismatch');
  }
}

bool _catalogDuplicates(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}

List<T> _catalogSorted<T>(
  Iterable<T> values,
  String Function(T) key,
  String path,
) {
  final result = List<T>.of(values)
    ..sort((left, right) => key(left).compareTo(key(right)));
  if (_catalogDuplicates(result.map(key))) {
    throw ArgumentError('$path IDs must be unique');
  }
  return List<T>.unmodifiable(result);
}

void _catalogOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

void _catalogNonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name);
}

final class Workspace {
  const Workspace({required this.id, required this.displayName});

  final WorkspaceId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory Workspace.fromJson(Object? value) {
    final json = _catalogObject(value, 'Workspace');
    _catalogOnly(json, const <String>{'id', 'displayName'}, 'Workspace');
    return Workspace(
      id: WorkspaceId(_catalogString(json, 'id', 'Workspace')),
      displayName: _catalogBoundedString(
        json,
        'displayName',
        'Workspace',
        maxLength: 512,
      ),
    );
  }
}

final class Application {
  const Application({
    required this.id,
    required this.workspaceId,
    required this.displayName,
    required this.root,
    required this.target,
  });

  final ApplicationId id;
  final WorkspaceId workspaceId;
  final String displayName;
  final String root;
  final String target;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'workspaceId': workspaceId.value,
    'displayName': displayName,
    'root': root,
    'target': target,
  };

  factory Application.fromJson(Object? value) {
    final json = _catalogObject(value, 'Application');
    _catalogOnly(json, const <String>{
      'id',
      'workspaceId',
      'displayName',
      'root',
      'target',
    }, 'Application');
    return Application(
      id: ApplicationId(_catalogString(json, 'id', 'Application')),
      workspaceId: WorkspaceId(
        _catalogString(json, 'workspaceId', 'Application'),
      ),
      displayName: _catalogBoundedString(
        json,
        'displayName',
        'Application',
        maxLength: 512,
      ),
      root: _catalogBoundedString(json, 'root', 'Application'),
      target: _catalogBoundedString(
        json,
        'target',
        'Application',
        maxLength: 256,
      ),
    );
  }
}

final class Journey {
  Journey({
    required this.id,
    required this.applicationId,
    required this.title,
    required List<ScenarioId> scenarioIds,
  }) : scenarioIds = List<ScenarioId>.unmodifiable(scenarioIds);

  final JourneyId id;
  final ApplicationId applicationId;
  final String title;
  final List<ScenarioId> scenarioIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'title': title,
    'scenarioIds': <String>[for (final id in scenarioIds) id.value],
  };

  factory Journey.fromJson(Object? value) {
    final json = _catalogObject(value, 'Journey');
    _catalogOnly(json, const <String>{
      'id',
      'applicationId',
      'title',
      'scenarioIds',
    }, 'Journey');
    final scenarioIds = _catalogStringList(
      json['scenarioIds'],
      'Journey.scenarioIds',
    );
    if (scenarioIds.length > 100000 || _catalogDuplicates(scenarioIds)) {
      throw const FormatException(
        'Journey.scenarioIds must be unique and bounded',
      );
    }
    return Journey(
      id: JourneyId(_catalogString(json, 'id', 'Journey')),
      applicationId: ApplicationId(
        _catalogString(json, 'applicationId', 'Journey'),
      ),
      title: _catalogBoundedString(json, 'title', 'Journey', maxLength: 2048),
      scenarioIds: <ScenarioId>[for (final id in scenarioIds) ScenarioId(id)],
    );
  }
}

final class Scenario {
  Scenario({
    required this.id,
    required this.applicationId,
    required this.title,
    this.description,
    List<SourceReference> sourceReferences = const <SourceReference>[],
  }) : sourceReferences = List<SourceReference>.unmodifiable(sourceReferences);

  final ScenarioId id;
  final ApplicationId applicationId;
  final String title;
  final String? description;
  final List<SourceReference> sourceReferences;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'title': title,
    if (description != null) 'description': description,
    'sourceReferences': <Object?>[
      for (final reference in sourceReferences) reference.toJson(),
    ],
  };

  factory Scenario.fromJson(Object? value) {
    final json = _catalogObject(value, 'Scenario');
    _catalogOnly(json, const <String>{
      'id',
      'applicationId',
      'title',
      'description',
      'sourceReferences',
    }, 'Scenario');
    return Scenario(
      id: ScenarioId(_catalogString(json, 'id', 'Scenario')),
      applicationId: ApplicationId(
        _catalogString(json, 'applicationId', 'Scenario'),
      ),
      title: _catalogBoundedString(json, 'title', 'Scenario', maxLength: 2048),
      description: _catalogOptionalString(
        json,
        'description',
        'Scenario',
        maxLength: 16384,
      ),
      sourceReferences: _catalogList(
        json,
        'sourceReferences',
        'Scenario',
        maxItems: 1000,
      ).map(SourceReference.fromJson).toList(growable: false),
    );
  }
}

final class Transition {
  const Transition({
    required this.id,
    required this.journeyId,
    required this.from,
    required this.to,
    this.label,
  });

  final TransitionId id;
  final JourneyId journeyId;
  final ScenarioId from;
  final ScenarioId to;
  final String? label;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'journeyId': journeyId.value,
    'from': from.value,
    'to': to.value,
    if (label != null) 'label': label,
  };

  factory Transition.fromJson(Object? value) {
    final json = _catalogObject(value, 'Transition');
    _catalogOnly(json, const <String>{
      'id',
      'journeyId',
      'from',
      'to',
      'label',
    }, 'Transition');
    return Transition(
      id: TransitionId(_catalogString(json, 'id', 'Transition')),
      journeyId: JourneyId(_catalogString(json, 'journeyId', 'Transition')),
      from: ScenarioId(_catalogString(json, 'from', 'Transition')),
      to: ScenarioId(_catalogString(json, 'to', 'Transition')),
      label: _catalogOptionalString(
        json,
        'label',
        'Transition',
        maxLength: 2048,
      ),
    );
  }
}

final class SourceReference {
  const SourceReference({
    required this.repository,
    required this.path,
    this.symbol,
  });

  final String repository;
  final String path;
  final String? symbol;

  Map<String, Object?> toJson() => <String, Object?>{
    'repository': repository,
    'path': path,
    if (symbol != null) 'symbol': symbol,
  };

  factory SourceReference.fromJson(Object? value) {
    final json = _catalogObject(value, 'SourceReference');
    _catalogOnly(json, const <String>{
      'repository',
      'path',
      'symbol',
    }, 'SourceReference');
    return SourceReference(
      repository: _catalogBoundedString(
        json,
        'repository',
        'SourceReference',
        maxLength: 512,
      ),
      path: _catalogBoundedString(json, 'path', 'SourceReference'),
      symbol: _catalogOptionalString(
        json,
        'symbol',
        'SourceReference',
        maxLength: 1024,
      ),
    );
  }
}

final class Projection {
  Projection({required this.id, required List<ScenarioId> scenarioIds})
    : scenarioIds = List<ScenarioId>.unmodifiable(scenarioIds);

  final String id;
  final List<ScenarioId> scenarioIds;
}

final class LayoutPosition {
  const LayoutPosition({
    required this.scenarioId,
    required this.x,
    required this.y,
  });

  final ScenarioId scenarioId;
  final double x;
  final double y;
}

final class Layout {
  Layout({required this.id, required List<LayoutPosition> positions})
    : positions = List<LayoutPosition>.unmodifiable(positions);

  final String id;
  final List<LayoutPosition> positions;
}

final class ScenarioExecutionBinding {
  ScenarioExecutionBinding({
    required this.id,
    required this.scenarioId,
    required this.targetId,
    this.launchProfileId,
    this.checkpointId,
    this.gatewayPresetId,
  }) {
    OpaqueId.validate(targetId, 'ExecutionTarget');
    if ((launchProfileId == null) == (checkpointId == null)) {
      throw ArgumentError(
        'ScenarioExecutionBinding requires exactly one launchProfileId or checkpointId',
      );
    }
    if (launchProfileId != null) {
      OpaqueId.validate(launchProfileId!, 'LaunchProfile');
    }
    if (checkpointId != null) OpaqueId.validate(checkpointId!, 'Checkpoint');
  }

  final ScenarioExecutionBindingId id;
  final ScenarioId scenarioId;
  final String targetId;
  final String? launchProfileId;
  final String? checkpointId;
  final String? gatewayPresetId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'targetId': targetId,
    if (launchProfileId != null) 'launchProfileId': launchProfileId,
    if (checkpointId != null) 'checkpointId': checkpointId,
    if (gatewayPresetId != null) 'gatewayPresetId': gatewayPresetId,
  };

  factory ScenarioExecutionBinding.fromJson(Object? value) {
    final json = _catalogObject(value, 'ScenarioExecutionBinding');
    _catalogOnly(json, const <String>{
      'id',
      'scenarioId',
      'targetId',
      'launchProfileId',
      'checkpointId',
      'gatewayPresetId',
    }, 'ScenarioExecutionBinding');
    return ScenarioExecutionBinding(
      id: ScenarioExecutionBindingId(
        _catalogString(json, 'id', 'ScenarioExecutionBinding'),
      ),
      scenarioId: ScenarioId(
        _catalogString(json, 'scenarioId', 'ScenarioExecutionBinding'),
      ),
      targetId: _catalogBoundedString(
        json,
        'targetId',
        'ScenarioExecutionBinding',
        maxLength: 256,
      ),
      launchProfileId: _catalogOptionalString(
        json,
        'launchProfileId',
        'ScenarioExecutionBinding',
        maxLength: 256,
      ),
      checkpointId: _catalogOptionalString(
        json,
        'checkpointId',
        'ScenarioExecutionBinding',
        maxLength: 256,
      ),
      gatewayPresetId: _catalogOptionalString(
        json,
        'gatewayPresetId',
        'ScenarioExecutionBinding',
        maxLength: 256,
      ),
    );
  }
}

final class ReviewGuideStep {
  ReviewGuideStep({
    required this.id,
    required this.instruction,
    required this.observationCriteria,
    required this.scenarioId,
    required this.bindingId,
  }) {
    OpaqueId.validate(id, 'ReviewGuideStep');
    _catalogNonEmpty(instruction, 'instruction');
    _catalogNonEmpty(observationCriteria, 'observationCriteria');
    final infrastructureTerms = RegExp(
      r'\b(?:https?|endpoint|json|swagger|openapi|gatewaypreset|route|api)\b',
      caseSensitive: false,
    );
    if (infrastructureTerms.hasMatch(instruction) ||
        infrastructureTerms.hasMatch(observationCriteria)) {
      throw FormatException(
        'ReviewGuideStep narrative cannot expose infrastructure terminology',
      );
    }
  }

  final String id;
  final String instruction;
  final String observationCriteria;
  final ScenarioId scenarioId;
  final ScenarioExecutionBindingId bindingId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'instruction': instruction,
    'observationCriteria': observationCriteria,
    'scenarioId': scenarioId.value,
    'bindingId': bindingId.value,
  };

  factory ReviewGuideStep.fromJson(Object? value) {
    final json = _catalogObject(value, 'ReviewGuideStep');
    _catalogOnly(json, const <String>{
      'id',
      'instruction',
      'observationCriteria',
      'scenarioId',
      'bindingId',
    }, 'ReviewGuideStep');
    return ReviewGuideStep(
      id: _catalogString(json, 'id', 'ReviewGuideStep'),
      instruction: _catalogBoundedString(
        json,
        'instruction',
        'ReviewGuideStep',
        maxLength: 4096,
      ),
      observationCriteria: _catalogBoundedString(
        json,
        'observationCriteria',
        'ReviewGuideStep',
        maxLength: 4096,
      ),
      scenarioId: ScenarioId(
        _catalogString(json, 'scenarioId', 'ReviewGuideStep'),
      ),
      bindingId: ScenarioExecutionBindingId(
        _catalogString(json, 'bindingId', 'ReviewGuideStep'),
      ),
    );
  }
}

final class ReviewGuide {
  ReviewGuide({
    required this.id,
    required this.applicationId,
    required this.title,
    required List<ReviewGuideStep> steps,
  }) : steps = List<ReviewGuideStep>.unmodifiable(steps) {
    _catalogNonEmpty(title, 'title');
    if (steps.isEmpty ||
        steps.map((step) => step.id).toSet().length != steps.length) {
      throw ArgumentError('ReviewGuide steps must be non-empty and unique');
    }
  }

  final ReviewGuideId id;
  final ApplicationId applicationId;
  final String title;
  final List<ReviewGuideStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'title': title,
    'steps': <Object?>[for (final step in steps) step.toJson()],
  };

  factory ReviewGuide.fromJson(Object? value) {
    final json = _catalogObject(value, 'ReviewGuide');
    _catalogOnly(json, const <String>{
      'id',
      'applicationId',
      'title',
      'steps',
    }, 'ReviewGuide');
    return ReviewGuide(
      id: ReviewGuideId(_catalogString(json, 'id', 'ReviewGuide')),
      applicationId: ApplicationId(
        _catalogString(json, 'applicationId', 'ReviewGuide'),
      ),
      title: _catalogBoundedString(
        json,
        'title',
        'ReviewGuide',
        maxLength: 2048,
      ),
      steps: _catalogList(
        json,
        'steps',
        'ReviewGuide',
        maxItems: 10000,
      ).map(ReviewGuideStep.fromJson).toList(growable: false),
    );
  }
}

final class CatalogManifest {
  CatalogManifest({
    required this.distribution,
    required this.layout,
    required this.workspace,
    required List<Application> applications,
    required List<Journey> journeys,
    required List<Scenario> scenarios,
    required List<Transition> transitions,
    List<ScenarioExecutionBinding> executionBindings =
        const <ScenarioExecutionBinding>[],
    List<ReviewGuide> reviewGuides = const <ReviewGuide>[],
  }) : applications = _catalogSorted(
         applications,
         (value) => value.id.value,
         'CatalogManifest.applications',
       ),
       journeys = _catalogSorted(
         journeys,
         (value) => value.id.value,
         'CatalogManifest.journeys',
       ),
       scenarios = _catalogSorted(
         scenarios,
         (value) => value.id.value,
         'CatalogManifest.scenarios',
       ),
       transitions = _catalogSorted(
         transitions,
         (value) => value.id.value,
         'CatalogManifest.transitions',
       ),
       executionBindings = _catalogSorted(
         executionBindings,
         (value) => value.id.value,
         'CatalogManifest.executionBindings',
       ),
       reviewGuides = _catalogSorted(
         reviewGuides,
         (value) => value.id.value,
         'CatalogManifest.reviewGuides',
       ) {
    _validateCatalogManifest(this);
  }

  static const int schemaVersion = 1;

  final DistributionDescriptor distribution;
  final ConsumerLayout layout;
  final Workspace workspace;
  final List<Application> applications;
  final List<Journey> journeys;
  final List<Scenario> scenarios;
  final List<Transition> transitions;
  final List<ScenarioExecutionBinding> executionBindings;
  final List<ReviewGuide> reviewGuides;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'CatalogManifest',
    'distribution': distribution.toJson(),
    'layout': layout.toJson(),
    'workspace': workspace.toJson(),
    'applications': <Object?>[for (final value in applications) value.toJson()],
    'journeys': <Object?>[for (final value in journeys) value.toJson()],
    'scenarios': <Object?>[for (final value in scenarios) value.toJson()],
    'transitions': <Object?>[for (final value in transitions) value.toJson()],
    'executionBindings': <Object?>[
      for (final value in executionBindings) value.toJson(),
    ],
    'reviewGuides': <Object?>[for (final value in reviewGuides) value.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory CatalogManifest.fromJson(Object? value) {
    final json = _catalogObject(value, 'CatalogManifest');
    _catalogOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'distribution',
      'layout',
      'workspace',
      'applications',
      'journeys',
      'scenarios',
      'transitions',
      'executionBindings',
      'reviewGuides',
      'digest',
    }, 'CatalogManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'CatalogManifest') {
      throw const FormatException(
        'CatalogManifest has invalid schemaVersion or kind',
      );
    }
    final manifest = CatalogManifest(
      distribution: DistributionDescriptor.fromJson(json['distribution']),
      layout: ConsumerLayout.fromJson(json['layout']),
      workspace: Workspace.fromJson(json['workspace']),
      applications: _catalogList(
        json,
        'applications',
        'CatalogManifest',
        maxItems: 10000,
      ).map(Application.fromJson).toList(growable: false),
      journeys: _catalogList(
        json,
        'journeys',
        'CatalogManifest',
        maxItems: 50000,
      ).map(Journey.fromJson).toList(growable: false),
      scenarios: _catalogList(
        json,
        'scenarios',
        'CatalogManifest',
        maxItems: 100000,
      ).map(Scenario.fromJson).toList(growable: false),
      transitions: _catalogList(
        json,
        'transitions',
        'CatalogManifest',
        maxItems: 500000,
      ).map(Transition.fromJson).toList(growable: false),
      executionBindings: _catalogList(
        json,
        'executionBindings',
        'CatalogManifest',
        maxItems: 100000,
      ).map(ScenarioExecutionBinding.fromJson).toList(growable: false),
      reviewGuides: _catalogList(
        json,
        'reviewGuides',
        'CatalogManifest',
        maxItems: 20000,
      ).map(ReviewGuide.fromJson).toList(growable: false),
    );
    _catalogVerifyDigest(json, manifest.digest, 'CatalogManifest');
    return manifest;
  }
}

void _validateCatalogManifest(CatalogManifest manifest) {
  final applicationIds = manifest.applications.map((item) => item.id).toSet();
  final scenarioIds = manifest.scenarios.map((item) => item.id).toSet();
  final journeyIds = manifest.journeys.map((item) => item.id).toSet();
  final bindingById = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
    for (final binding in manifest.executionBindings) binding.id: binding,
  };
  final scenarioById = <ScenarioId, Scenario>{
    for (final scenario in manifest.scenarios) scenario.id: scenario,
  };

  for (final application in manifest.applications) {
    if (application.workspaceId != manifest.workspace.id) {
      throw ArgumentError(
        'Application ${application.id} references an unknown Workspace',
      );
    }
  }
  for (final scenario in manifest.scenarios) {
    if (!applicationIds.contains(scenario.applicationId)) {
      throw ArgumentError(
        'Scenario ${scenario.id} references an unknown Application',
      );
    }
  }
  for (final journey in manifest.journeys) {
    if (!applicationIds.contains(journey.applicationId) ||
        journey.scenarioIds.any((id) => !scenarioIds.contains(id))) {
      throw ArgumentError('Journey ${journey.id} has an unknown reference');
    }
  }
  for (final transition in manifest.transitions) {
    if (!journeyIds.contains(transition.journeyId) ||
        !scenarioIds.contains(transition.from) ||
        !scenarioIds.contains(transition.to)) {
      throw ArgumentError(
        'Transition ${transition.id} has an unknown reference',
      );
    }
  }
  for (final binding in manifest.executionBindings) {
    if (!scenarioIds.contains(binding.scenarioId)) {
      throw ArgumentError(
        'ScenarioExecutionBinding ${binding.id} has an unknown Scenario',
      );
    }
  }
  for (final guide in manifest.reviewGuides) {
    if (!applicationIds.contains(guide.applicationId)) {
      throw ArgumentError('ReviewGuide ${guide.id} has an unknown Application');
    }
    for (final step in guide.steps) {
      final binding = bindingById[step.bindingId];
      final scenario = scenarioById[step.scenarioId];
      if (binding == null ||
          scenario == null ||
          binding.scenarioId != step.scenarioId ||
          scenario.applicationId != guide.applicationId) {
        throw ArgumentError(
          'ReviewGuide ${guide.id} step ${step.id} has an invalid binding',
        );
      }
    }
  }
}
