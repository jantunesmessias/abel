import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

final class ConsumerApplicationConfiguration {
  ConsumerApplicationConfiguration({
    required this.id,
    required this.root,
    required this.resolvedRoot,
    required this.target,
    required this.displayName,
  });

  final String id;
  final String root;
  final String resolvedRoot;
  final String target;
  final String displayName;
}

/// Inputs already interpreted from consumer configuration, ordered after the
/// selected profile and before any effects.
final class KitPlanRequest {
  KitPlanRequest({
    required this.profileId,
    required List<KitSelection> overlays,
    required this.startupPolicy,
  }) : overlays = List<KitSelection>.unmodifiable(overlays);

  final String? profileId;
  final List<KitSelection> overlays;
  final String startupPolicy;

  ResolvedKitPlan resolve({
    required ModuleCatalog catalog,
    List<KitSelection> defaults = const <KitSelection>[],
    Map<String, Object?> configurationSchemas = const <String, Object?>{},
    KitPlanResolver resolver = const KitPlanResolver(),
  }) => resolver.resolve(
    catalog: catalog,
    profileId: profileId,
    defaults: defaults,
    overlays: overlays,
    configurationSchemas: configurationSchemas,
    startupPolicy: startupPolicy,
  );
}

final class LoadedWorkspaceConfiguration {
  LoadedWorkspaceConfiguration({
    required this.schemaVersion,
    required this.workspaceRoot,
    required this.configPath,
    required this.localConfigPath,
    required this.contentRoot,
    required this.workspaceId,
    required this.workspaceDisplayName,
    required Map<String, ConsumerApplicationConfiguration> applications,
    required List<LaunchProfile> launchProfiles,
    required Map<String, Object?> document,
    required Map<String, Object?> localDocument,
    required this.layout,
    required this.kitPlanRequest,
  }) : applications =
           Map<String, ConsumerApplicationConfiguration>.unmodifiable(
             Map<String, ConsumerApplicationConfiguration>.fromEntries(
               applications.entries.toList()
                 ..sort((left, right) => left.key.compareTo(right.key)),
             ),
           ),
       launchProfiles = List<LaunchProfile>.unmodifiable(launchProfiles),
       document = _immutableJsonMap(document, 'consumer configuration'),
       localDocument = _immutableJsonMap(
         localDocument,
         'local consumer configuration',
       );

  final int schemaVersion;
  final String workspaceRoot;
  final String configPath;
  final String localConfigPath;
  final String contentRoot;
  final String workspaceId;
  final String workspaceDisplayName;
  final Map<String, ConsumerApplicationConfiguration> applications;
  final List<LaunchProfile> launchProfiles;
  final Map<String, Object?> document;
  final Map<String, Object?> localDocument;
  final ConsumerLayout layout;
  final KitPlanRequest kitPlanRequest;

  Digest get documentDigest => Digest.semantic(document);
  Digest? get localDocumentDigest =>
      localDocument.isEmpty ? null : Digest.semantic(localDocument);
}

/// Filesystem boundary for the consumer configuration and ignored local
/// overlays. No downstream module needs to reopen these files.
final class WorkspaceConfigurationLoader {
  const WorkspaceConfigurationLoader({
    this.parser = const SafeAuthoringParser(),
  });

  final SafeAuthoringParser parser;

  /// Loads only the ignored local document for a process that does not need
  /// catalog authoring (for example the isolated Gateway sidecar).
  Map<String, Object?> loadLocalConfiguration({
    required String workspaceRoot,
    String relativePath = 'workspace.local.yaml',
  }) {
    final root = Directory(workspaceRoot).absolute.resolveSymbolicLinksSync();
    final relative = _validatedRelativePath(relativePath, 'relativePath');
    final localPath = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, localPath)) {
      throw FileSystemException('Local config escapes workspace', localPath);
    }
    return _immutableJsonMap(
      _loadLocalDocument(localPath),
      'local consumer configuration',
    );
  }

  LoadedWorkspaceConfiguration load({
    required String startPath,
    String? explicitConfigPath,
    String? localConfigRelativePath,
    Map<String, String>? environment,
    String? profileOverride,
    KitSelection? startupSelection,
    String? startupPolicyOverride,
  }) {
    final start = Directory(startPath).absolute;
    final configuredPath =
        explicitConfigPath ??
        (environment ?? Platform.environment)[ConsumerLayout
            .standard
            .configEnvironmentVariable];
    final unresolvedConfig = configuredPath == null || configuredPath.isEmpty
        ? _discoverConfig(start)
        : File(_absoluteFrom(start.path, configuredPath));
    if (!unresolvedConfig.existsSync()) {
      throw FileSystemException('Abel config not found', unresolvedConfig.path);
    }
    if (Link(unresolvedConfig.path).existsSync()) {
      throw FileSystemException(
        'Abel config cannot be a symlink',
        unresolvedConfig.path,
      );
    }
    final configPath = unresolvedConfig.resolveSymbolicLinksSync();
    final config = File(configPath);
    final workspaceRoot = config.parent.resolveSymbolicLinksSync();
    final document = parser.parseObject(
      config.readAsStringSync(),
      sourceName: configPath,
    );
    final version = document['schemaVersion'];
    if (version != 2) {
      throw FormatException('$configPath: schemaVersion must equal 2');
    }
    const schemaVersion = 2;
    _validateMainDocument(document, configPath);

    final relativeConfig = p.relative(configPath, from: workspaceRoot);
    final localRelative = localConfigRelativePath == null
        ? p.setExtension(relativeConfig, '.local.yaml')
        : _validatedRelativePath(
            localConfigRelativePath,
            'localConfigRelativePath',
          );
    final localPath = p.normalize(p.join(workspaceRoot, localRelative));
    if (!p.isWithin(workspaceRoot, localPath)) {
      throw FileSystemException('Local config escapes workspace', localPath);
    }
    final localDocument = _loadLocalDocument(localPath);

    final content = _object(document['content'], configPath, r'$.content');
    final contentRootValue = _string(content, 'root', configPath, r'$.content');
    final contentRoot = _resolveInsideWorkspace(
      workspaceRoot,
      contentRootValue,
      path: r'$.content.root',
      requireStrictRelative: true,
      mustExist: true,
    );
    final workspace = _object(
      document['workspace'],
      configPath,
      r'$.workspace',
    );
    final workspaceId = _string(workspace, 'id', configPath, r'$.workspace');
    final workspaceDisplayName =
        _optionalString(workspace, 'displayName', configPath, r'$.workspace') ??
        workspaceId;
    final applicationObjects = _object(
      document['applications'],
      configPath,
      r'$.applications',
    );
    final applications = <String, ConsumerApplicationConfiguration>{};
    for (final entry in applicationObjects.entries) {
      final path = r'$.applications.' + entry.key;
      final application = _object(entry.value, configPath, path);
      final root = _string(application, 'root', configPath, path);
      applications[entry.key] = ConsumerApplicationConfiguration(
        id: entry.key,
        root: root,
        resolvedRoot: _resolveInsideWorkspace(
          workspaceRoot,
          root,
          path: '$path.root',
          requireStrictRelative: true,
          mustExist: false,
        ),
        target:
            _optionalString(application, 'target', configPath, path) ?? 'local',
        displayName:
            _optionalString(application, 'displayName', configPath, path) ??
            entry.key,
      );
    }
    final launchProfiles = _parseLaunchProfiles(
      document['launchProfiles'],
      applications: applications,
      workspaceRoot: workspaceRoot,
      source: configPath,
    );

    final mainKit = _parseKit(
      _object(document['kit'], configPath, r'$.kit'),
      configPath,
      r'$.kit',
      modulesRequired: true,
    );
    final localKit = localDocument['schemaVersion'] == 2
        ? _parseKit(
            _object(localDocument['kit'], localPath, r'$.kit'),
            localPath,
            r'$.kit',
            modulesRequired: false,
          )
        : const _ParsedKitLayer();
    final effectiveProfile =
        profileOverride ?? localKit.profileId ?? mainKit.profileId;
    if (effectiveProfile != null) {
      OpaqueId.validate(effectiveProfile, 'KitProfile');
    }
    final startupPolicy =
        startupPolicyOverride ??
        localKit.startupPolicy ??
        mainKit.startupPolicy ??
        'fail-required-v1';
    OpaqueId.validate(startupPolicy, 'StartupPolicy');
    final overlays = <KitSelection>[
      ?mainKit.selection,
      ?localKit.selection,
      ?startupSelection,
    ];

    return LoadedWorkspaceConfiguration(
      schemaVersion: schemaVersion,
      workspaceRoot: workspaceRoot,
      configPath: configPath,
      localConfigPath: localPath,
      contentRoot: contentRoot,
      workspaceId: workspaceId,
      workspaceDisplayName: workspaceDisplayName,
      applications: applications,
      launchProfiles: launchProfiles,
      document: document,
      localDocument: localDocument,
      layout: ConsumerLayout(
        configFile: relativeConfig,
        contentRoot: p.relative(contentRoot, from: workspaceRoot),
        localConfigFile: localRelative,
        toolingEntrypoint: 'tool/target_main.dart',
      ),
      kitPlanRequest: KitPlanRequest(
        profileId: effectiveProfile,
        overlays: overlays,
        startupPolicy: startupPolicy,
      ),
    );
  }

  File _discoverConfig(Directory start) {
    var current = start;
    while (true) {
      final candidate = File(p.join(current.path, 'workspace.yaml'));
      if (candidate.existsSync()) return candidate;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return File(p.join(start.path, 'workspace.yaml'));
  }

  Map<String, Object?> _loadLocalDocument(String localPath) {
    final file = File(localPath);
    if (!file.existsSync()) return const <String, Object?>{};
    if (Link(localPath).existsSync()) {
      throw FileSystemException('Local config cannot be a symlink', localPath);
    }
    final document = parser.parseObject(
      file.readAsStringSync(),
      sourceName: localPath,
    );
    final version = document['schemaVersion'];
    if (version == 1) {
      _only(
        document,
        const <String>{'schemaVersion', 'gateway'},
        localPath,
        r'$',
      );
      final gateway = _object(document['gateway'], localPath, r'$.gateway');
      _only(
        gateway,
        const <String>{'upstreams', 'providers'},
        localPath,
        r'$.gateway',
      );
      return document;
    }
    if (version == 2) {
      _only(document, const <String>{'schemaVersion', 'kit'}, localPath, r'$');
      _object(document['kit'], localPath, r'$.kit');
      return document;
    }
    throw FormatException('$localPath: schemaVersion must equal 1 or 2');
  }

  void _validateMainDocument(Map<String, Object?> document, String source) {
    _only(
      document,
      <String>{
        'schemaVersion',
        'distribution',
        'content',
        'workspace',
        'applications',
        'launchProfiles',
        'kit',
      },
      source,
      r'$',
    );
    for (final key in <String>['content', 'workspace', 'applications']) {
      if (!document.containsKey(key)) {
        throw FormatException('$source: missing \$.$key');
      }
    }
    if (!document.containsKey('kit')) {
      throw FormatException(
        r'$source: missing $.kit'.replaceFirst(r'$source', source),
      );
    }
    final distribution = document['distribution'];
    if (distribution != null) {
      final value = _object(distribution, source, r'$.distribution');
      _only(value, const <String>{'id'}, source, r'$.distribution');
      final id = _string(value, 'id', source, r'$.distribution');
      OpaqueId.validate(id, 'Distribution');
    }
    final content = _object(document['content'], source, r'$.content');
    _only(content, const <String>{'root'}, source, r'$.content');
    _string(content, 'root', source, r'$.content');
    final workspace = _object(document['workspace'], source, r'$.workspace');
    _only(
      workspace,
      const <String>{'id', 'displayName'},
      source,
      r'$.workspace',
    );
    final workspaceId = _string(workspace, 'id', source, r'$.workspace');
    OpaqueId.validate(workspaceId, 'Workspace');
    _optionalString(workspace, 'displayName', source, r'$.workspace');
    final applications = _object(
      document['applications'],
      source,
      r'$.applications',
    );
    for (final entry in applications.entries) {
      OpaqueId.validate(entry.key, 'Application');
      final path = r'$.applications.' + entry.key;
      final application = _object(entry.value, source, path);
      _only(
        application,
        const <String>{'root', 'target', 'displayName'},
        source,
        path,
      );
      _string(application, 'root', source, path);
      _optionalString(application, 'target', source, path);
      _optionalString(application, 'displayName', source, path);
    }
    if (document['launchProfiles'] != null) {
      _object(document['launchProfiles'], source, r'$.launchProfiles');
    }
  }

  List<LaunchProfile> _parseLaunchProfiles(
    Object? value, {
    required Map<String, ConsumerApplicationConfiguration> applications,
    required String workspaceRoot,
    required String source,
  }) {
    if (value == null) return const <LaunchProfile>[];
    final profiles = _object(value, source, r'$.launchProfiles');
    final output = <LaunchProfile>[];
    for (final entry in profiles.entries) {
      OpaqueId.validate(entry.key, 'LaunchProfile');
      final path = r'$.launchProfiles.' + entry.key;
      final profile = _object(entry.value, source, path);
      _only(
        profile,
        const <String>{
          'applicationId',
          'platform',
          'command',
          'arguments',
          'workingDirectory',
          'overlay',
          'bootstrapPolicy',
        },
        source,
        path,
      );
      final applicationId = _string(profile, 'applicationId', source, path);
      if (!applications.containsKey(applicationId)) {
        throw FormatException(
          '$source: $path.applicationId references unknown Application '
          '$applicationId',
        );
      }
      final platformName = _string(profile, 'platform', source, path);
      final TargetPlatform platform;
      try {
        platform = TargetPlatform.values.byName(platformName);
      } on ArgumentError {
        throw FormatException(
          '$source: $path.platform must be web or androidEmulator',
        );
      }
      final rawArguments = profile['arguments'];
      if (rawArguments is! List<Object?> ||
          rawArguments.any((argument) => argument is! String)) {
        throw FormatException('$source: $path.arguments must be a string list');
      }
      final workingDirectory = _string(
        profile,
        'workingDirectory',
        source,
        path,
      );
      _resolveInsideWorkspace(
        workspaceRoot,
        workingDirectory,
        path: '$path.workingDirectory',
        requireStrictRelative: true,
        mustExist: true,
      );
      final rawOverlay = profile['overlay'];
      final overlay = rawOverlay == null
          ? const <String, String>{}
          : _stringMap(rawOverlay, source, '$path.overlay');
      final rawBootstrap = profile['bootstrapPolicy'];
      final bootstrap = <String, BootstrapDependencyPolicy>{};
      if (rawBootstrap != null) {
        final dependencies = _stringMap(
          rawBootstrap,
          source,
          '$path.bootstrapPolicy',
        );
        for (final dependency in dependencies.entries) {
          try {
            bootstrap[dependency.key] = BootstrapDependencyPolicy.values.byName(
              dependency.value,
            );
          } on ArgumentError {
            throw FormatException(
              '$source: $path.bootstrapPolicy.${dependency.key} has '
              'unsupported value ${dependency.value}',
            );
          }
        }
      }
      output.add(
        LaunchProfile(
          id: entry.key,
          applicationId: ApplicationId(applicationId),
          platform: platform,
          command: _string(profile, 'command', source, path),
          arguments: rawArguments.cast<String>(),
          workingDirectory: workingDirectory,
          overlay: RuntimeConfigurationOverlay(overlay),
          bootstrapPolicy: ApplicationBootstrapPolicy(bootstrap),
        ),
      );
    }
    output.sort((left, right) => left.id.compareTo(right.id));
    return output;
  }

  _ParsedKitLayer _parseKit(
    Map<String, Object?> kit,
    String source,
    String path, {
    required bool modulesRequired,
  }) {
    _only(
      kit,
      const <String>{'profile', 'modules', 'providerBindings', 'startupPolicy'},
      source,
      path,
    );
    final profileId = _optionalString(kit, 'profile', source, path);
    if (profileId != null) OpaqueId.validate(profileId, 'KitProfile');
    final startupPolicy = _optionalString(kit, 'startupPolicy', source, path);
    if (startupPolicy != null) {
      OpaqueId.validate(startupPolicy, 'StartupPolicy');
    }
    final rawModules = kit['modules'];
    if (modulesRequired && rawModules == null) {
      throw FormatException('$source: missing $path.modules');
    }
    final modules = <KitModuleSelection>[];
    if (rawModules != null) {
      final moduleObjects = _object(rawModules, source, '$path.modules');
      for (final entry in moduleObjects.entries) {
        final modulePath = '$path.modules.${entry.key}';
        final module = _object(entry.value, source, modulePath);
        _only(
          module,
          const <String>{'enabled', 'settings'},
          source,
          modulePath,
        );
        final enabled = module['enabled'];
        if (enabled is! bool) {
          throw FormatException('$source: $modulePath.enabled must be boolean');
        }
        final settings = module['settings'] == null
            ? const <String, Object?>{}
            : _object(module['settings'], source, '$modulePath.settings');
        _rejectLiteralSecrets(settings, source, '$modulePath.settings');
        modules.add(
          KitModuleSelection(
            moduleId: ModuleId(entry.key),
            enabled: enabled,
            settings: settings,
          ),
        );
      }
    }
    final bindings = <ProviderBinding>[];
    final rawBindings = kit['providerBindings'];
    if (rawBindings != null) {
      if (rawBindings is! List<Object?>) {
        throw FormatException('$source: $path.providerBindings must be a list');
      }
      for (var index = 0; index < rawBindings.length; index += 1) {
        final bindingPath = '$path.providerBindings[$index]';
        final value = _object(rawBindings[index], source, bindingPath);
        _only(
          value,
          const <String>{
            'capability',
            'providerModuleIds',
            'selectionPolicy',
            'applicationId',
            'settings',
          },
          source,
          bindingPath,
        );
        final settings = value['settings'] == null
            ? const <String, Object?>{}
            : _object(value['settings'], source, '$bindingPath.settings');
        _rejectLiteralSecrets(settings, source, '$bindingPath.settings');
        bindings.add(
          ProviderBinding.fromJson(<String, Object?>{
            ...value,
            'settings': settings,
          }),
        );
      }
    }
    final selection = modules.isEmpty && bindings.isEmpty
        ? null
        : KitSelection(modules: modules, providerBindings: bindings);
    return _ParsedKitLayer(
      profileId: profileId,
      selection: selection,
      startupPolicy: startupPolicy,
    );
  }

  void _rejectLiteralSecrets(Object? value, String source, String path) {
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        final childPath = '$path.${entry.key}';
        final words = entry.key
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match.group(1)}_${match.group(2)}',
            )
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'));
        final last = words.isEmpty ? '' : words.last;
        final sensitive = const <String>{
          'secret',
          'password',
          'token',
          'apikey',
          'privatekey',
          'credential',
        }.contains(last);
        if (sensitive && !_isSecretReference(entry.value)) {
          throw FormatException(
            '$source: literal secret forbidden at $childPath; use secretRef',
          );
        }
        _rejectLiteralSecrets(entry.value, source, childPath);
      }
    } else if (value is List<Object?>) {
      for (var index = 0; index < value.length; index += 1) {
        _rejectLiteralSecrets(value[index], source, '$path[$index]');
      }
    }
  }

  bool _isSecretReference(Object? value) =>
      value is Map<String, Object?> &&
      value.length == 1 &&
      value['secretRef'] is String &&
      (value['secretRef']! as String).isNotEmpty;

  String _resolveInsideWorkspace(
    String workspaceRoot,
    String value, {
    required String path,
    required bool requireStrictRelative,
    required bool mustExist,
  }) {
    if (requireStrictRelative) _validatedRelativePath(value, path);
    final candidate = _absoluteFrom(workspaceRoot, value);
    if (!p.isWithin(workspaceRoot, candidate) && candidate != workspaceRoot) {
      throw FileSystemException('$path escapes workspace', candidate);
    }
    if (mustExist ||
        FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      final resolved = Directory(candidate).resolveSymbolicLinksSync();
      if (!p.isWithin(workspaceRoot, resolved) && resolved != workspaceRoot) {
        throw FileSystemException(
          '$path resolves outside workspace',
          candidate,
        );
      }
      return resolved;
    }
    return candidate;
  }

  String _validatedRelativePath(String value, String name) {
    if (value.isEmpty ||
        p.isAbsolute(value) ||
        value.contains(r'\') ||
        p.split(value).contains('..')) {
      throw FormatException('$name must be a confined relative path');
    }
    return p.normalize(value);
  }

  String _absoluteFrom(String root, String value) => p.isAbsolute(value)
      ? p.normalize(value)
      : p.normalize(p.join(root, value));

  Map<String, Object?> _object(Object? value, String source, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$source: $path must be an object');
    }
    return value;
  }

  String _string(
    Map<String, Object?> value,
    String key,
    String source,
    String path,
  ) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('$source: $path.$key must be a non-empty string');
    }
    return result;
  }

  String? _optionalString(
    Map<String, Object?> value,
    String key,
    String source,
    String path,
  ) {
    final result = value[key];
    if (result == null) return null;
    if (result is! String || result.isEmpty) {
      throw FormatException('$source: $path.$key must be a non-empty string');
    }
    return result;
  }

  Map<String, String> _stringMap(Object? value, String source, String path) {
    final object = _object(value, source, path);
    if (object.values.any((item) => item is! String)) {
      throw FormatException('$source: $path must contain only string values');
    }
    return object.cast<String, String>();
  }

  void _only(
    Map<String, Object?> value,
    Set<String> allowed,
    String source,
    String path,
  ) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('$source: unknown field $path.$key');
      }
    }
  }
}

final class _ParsedKitLayer {
  const _ParsedKitLayer({this.profileId, this.selection, this.startupPolicy});

  final String? profileId;
  final KitSelection? selection;
  final String? startupPolicy;
}

Map<String, Object?> _immutableJsonMap(
  Map<String, Object?> value,
  String path,
) {
  Object? copy(Object? item, String itemPath) {
    if (item == null || item is String || item is bool || item is num) {
      return item;
    }
    if (item is List<Object?>) {
      return List<Object?>.unmodifiable(<Object?>[
        for (var index = 0; index < item.length; index += 1)
          copy(item[index], '$itemPath[$index]'),
      ]);
    }
    if (item is Map<String, Object?>) {
      final keys = item.keys.toList()..sort();
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final key in keys) key: copy(item[key], '$itemPath.$key'),
      });
    }
    throw FormatException('$itemPath is not a JSON value');
  }

  return copy(value, path)! as Map<String, Object?>;
}
