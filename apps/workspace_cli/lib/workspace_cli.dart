import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import 'src/kit_plan_loader.dart';

final class CliResult {
  const CliResult({required this.exitCode, this.stdout = '', this.stderr = ''});

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class WorkspaceCli {
  WorkspaceCli({String? workspaceDirectory})
    : workspaceDirectory = workspaceDirectory ?? Directory.current.path;

  static const String version = '0.1.0-dev';

  final String workspaceDirectory;
  final Map<DevelopmentSupervisor, List<StreamSubscription<ProcessSignal>>>
  _developmentRuns =
      <DevelopmentSupervisor, List<StreamSubscription<ProcessSignal>>>{};

  Future<void> closeDevelopmentRuns() async {
    for (final supervisor in _developmentRuns.keys.toList(growable: false)) {
      await _stopDevelopment(supervisor);
    }
  }

  Future<CliResult> run(List<String> arguments) async {
    final requestedCommand = _requestedTopLevelCommand(arguments);
    Set<String>? enabledModuleIds;
    if (_conditionalCommandModules.containsKey(requestedCommand)) {
      try {
        final loaded = const CliKitPlanLoader().load(
          workspaceDirectory: workspaceDirectory,
          explicitConfigPath: _rawOption(
            arguments,
            'config',
            abbreviation: 'c',
          ),
          profileOverride: _rawOption(arguments, 'profile'),
          allowMissingWorkspace: true,
        );
        enabledModuleIds = loaded.plan.enabledModules
            .map((module) => module.moduleId.value)
            .toSet();
      } on Object catch (error) {
        return _failure(
          requestedCommand!,
          '$error',
          json: arguments.contains('--json'),
        );
      }
    }
    final parser = _parser(enabledModuleIds: enabledModuleIds);
    final ArgResults parsed;
    try {
      parsed = parser.parse(arguments);
    } on FormatException catch (error) {
      return CliResult(
        exitCode: 2,
        stderr: '${error.message}\nUsage:\n${parser.usage}\n',
      );
    }
    final command = parsed.command;
    if (command == null) {
      return CliResult(exitCode: 2, stderr: 'Usage:\n${parser.usage}\n');
    }
    final json = parsed.flag('json');
    if (command.name == 'version') {
      return _success(
        command: 'version',
        result: <String, Object?>{'coreVersion': version},
        human: 'workspace $version',
        json: json,
      );
    }
    if (command.name == 'doctor') {
      return _doctor(json: json);
    }
    if (command.name == 'modules') {
      return _modules(command, json: json);
    }
    if (command.name == 'session') {
      return _session(command, json: json);
    }
    if (command.name == 'gateway') {
      return _gateway(command, json: json);
    }
    if (command.name == 'init' ||
        command.name == 'adoption-report' ||
        command.name == 'detach') {
      return _adoption(command, json: json);
    }
    if (command.name == 'evidence') {
      return _evidence(command, json: json);
    }
    if (command.name == 'distribution') {
      return _distribution(command, json: json);
    }
    if (command.name == 'target') {
      return _target(command, json: json);
    }
    if (command.name == 'probe') {
      return _probe(command, json: json);
    }
    if (command.name == 'retention') {
      return _retention(command, json: json);
    }
    if (command.name == 'source') {
      return _source(command, json: json);
    }
    if (command.name == 'plan') {
      return _impactPlan(command, json: json);
    }
    if (command.name == 'context') {
      return _context(command, json: json);
    }
    if (command.name == 'gate') {
      return _gate(command, json: json);
    }
    if (command.name == 'plugin') {
      return _plugin(command, json: json);
    }
    if (command.name == 'mcp') {
      return _mcp(command, json: json);
    }
    if (command.name == 'auth') {
      return _hostedAuth(command, json: json);
    }
    if (command.name == 'workspace') {
      return _hostedWorkspace(command, json: json);
    }
    if (command.name == 'publish') {
      return _hostedPublish(command, json: json);
    }
    if (command.name == 'release' && command.command?.name != 'build') {
      return _releaseV2(command, json: json);
    }
    try {
      return await _runCatalogCommand(command, json: json);
    } on EvidencePreconditionException catch (error) {
      return _preconditionFailure(
        command.name == 'release' ? 'release build' : command.name!,
        error.message,
        json: json,
        freshness: error.freshness,
      );
    } on AuthoringParseException catch (error) {
      return _failure(command.name!, error.toString(), json: json);
    } on CatalogCompileException catch (error) {
      return _failure(command.name!, error.toString(), json: json);
    } on GatewayCompileException catch (error) {
      return _failure(command.name!, error.toString(), json: json);
    } on FormatException catch (error) {
      return _failure(command.name!, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        command.name!,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on Object catch (error) {
      final output = MachineOutput(
        command: command.name!,
        ok: false,
        correlationId: null,
        effectiveContext: const <String, Object?>{},
        result: null,
        failures: <PlatformFailure>[
          PlatformFailure(
            code: 'INTERNAL_ERROR',
            category: FailureCategory.internal,
            message: '$error',
            recoverability: Recoverability.none,
          ),
        ],
        diagnostics: const <MachineDiagnostic>[],
      );
      return CliResult(
        exitCode: 70,
        stderr: json ? '${jsonEncode(output.toJson())}\n' : 'Internal error\n',
      );
    }
  }

  ArgParser _parser({Set<String>? enabledModuleIds}) {
    ArgParser catalogCommand() => ArgParser()
      ..addOption('config', abbr: 'c', help: 'Explicit consumer config path.')
      ..addOption('profile', help: 'Override the configured Kit profile.');
    final dev = catalogCommand()
      ..addFlag(
        'plan-only',
        negatable: false,
        help: 'Resolve and persist the launch plan without starting services.',
      )
      ..addFlag(
        'no-open',
        negatable: false,
        help: 'Do not open the Studio URL in the system browser.',
      )
      ..addOption(
        'studio-assets',
        help: 'Explicit packaged Studio web asset directory.',
      )
      ..addOption(
        'studio-dev-origin',
        help: 'External loopback Flutter Studio origin used for hot reload.',
      )
      ..addOption('host-port', defaultsTo: '0')
      ..addOption('studio-port', defaultsTo: '0')
      ..addOption('headless-studio-origin', defaultsTo: 'http://127.0.0.1');
    final capture = catalogCommand()
      ..addOption('input', abbr: 'i', help: 'Lossless PNG capture file.')
      ..addOption(
        'source-snapshot',
        help: 'Optional SourceSnapshot JSON for reproducible source identity.',
      )
      ..addOption('launch-profile', defaultsTo: 'unspecified')
      ..addOption('target', defaultsTo: 'unspecified')
      ..addOption(
        'platform',
        allowed: const <String>['web', 'androidEmulator'],
        defaultsTo: 'web',
      )
      ..addOption('renderer', defaultsTo: 'unspecified')
      ..addOption(
        'fidelity',
        allowed: RuntimeFidelity.values.map((value) => value.name),
        defaultsTo: RuntimeFidelity.structural.name,
      )
      ..addOption(
        'classification',
        allowed: ArtifactClassification.values.map((value) => value.name),
        defaultsTo: ArtifactClassification.internal.name,
      );
    ArgParser gatewayConnection({bool session = true}) => ArgParser()
      ..addOption('host')
      ..addOption('token')
      ..addOption('studio-origin')
      ..addOption('config', abbr: 'c')
      ..addOption('gateway-session', mandatory: session);
    final gatewayRun = gatewayConnection(session: false)
      ..addOption('owner-session', mandatory: true)
      ..addOption('plan', help: 'Canonical CompiledGatewayPlan JSON file.');
    final gatewayApply = gatewayConnection()
      ..addOption('plan', help: 'Canonical CompiledGatewayPlan JSON file.');
    final gatewayVerify = gatewayConnection()
      ..addOption('method', defaultsTo: 'GET')
      ..addOption('path', mandatory: true)
      ..addMultiOption(
        'query',
        help: 'Required query entry in key=value form; repeatable.',
      )
      ..addOption('body', help: 'Optional request body file, maximum 256 KiB.');
    final gatewayTraffic = gatewayConnection()
      ..addOption('after-sequence', defaultsTo: '0')
      ..addOption('limit', defaultsTo: '1000');
    ArgParser gatewayLocal({required bool providerMandatory}) => ArgParser()
      ..addOption('config', abbr: 'c')
      ..addOption('local-config', defaultsTo: 'workspace.local.yaml')
      ..addOption('provider', mandatory: providerMandatory);
    final gateway = ArgParser()
      ..addCommand('run', gatewayRun)
      ..addCommand('status', gatewayConnection())
      ..addCommand('apply-preset', gatewayApply)
      ..addCommand('verify', gatewayVerify)
      ..addCommand('traffic', gatewayTraffic)
      ..addCommand('reset', gatewayConnection())
      ..addCommand('stop', gatewayConnection())
      ..addCommand('sync', gatewayLocal(providerMandatory: true))
      ..addCommand('doctor', gatewayLocal(providerMandatory: false));
    ArgParser adoptionMutation() => ArgParser()
      ..addFlag('dry-run', negatable: false)
      ..addFlag('apply', negatable: false)
      ..addOption('distribution', defaultsTo: 'full-local')
      ..addOption('workspace-id', defaultsTo: 'workspace')
      ..addOption('display-name', defaultsTo: 'Workspace')
      ..addOption('application-id', defaultsTo: 'app');
    final collectTests = ArgParser()
      ..addOption(
        'runner',
        allowed: DartTestRunner.values.map((value) => value.name),
        defaultsTo: DartTestRunner.dart.name,
      )
      ..addMultiOption('target', help: 'Relative Dart/Flutter test target.')
      ..addOption('timeout-seconds', defaultsTo: '300');
    final collectPreviews = ArgParser()
      ..addOption('config', abbr: 'c')
      ..addOption('profile')
      ..addOption('application', mandatory: true)
      ..addOption('scenario')
      ..addOption('variant')
      ..addFlag('synthetic-data-confirmed', negatable: false)
      ..addOption('output');
    ArgParser evidenceComparison() => ArgParser()
      ..addOption('expected', mandatory: true)
      ..addOption('actual', mandatory: true)
      ..addOption('policy', mandatory: true)
      ..addOption('output');
    ArgParser distributionLocation() =>
        ArgParser()..addOption('install-root', mandatory: true);
    final distributionInstall = distributionLocation()
      ..addOption('bundle', mandatory: true);
    final distributionCompose = ArgParser()
      ..addOption('base-bundle', mandatory: true)
      ..addOption('workspace', mandatory: true)
      ..addOption('specification', mandatory: true)
      ..addOption('output', mandatory: true);
    final distribution = ArgParser()
      ..addCommand('compose-consumer', distributionCompose)
      ..addCommand('install', distributionInstall)
      ..addCommand('status', distributionLocation())
      ..addCommand('rollback', distributionLocation())
      ..addCommand(
        'verify-bundle',
        ArgParser()..addOption('bundle', mandatory: true),
      );
    ArgParser androidBase({bool serial = true}) => ArgParser()
      ..addOption('sdk-root')
      ..addOption('serial', mandatory: serial);
    ArgParser androidMutation({bool serial = true}) =>
        androidBase(serial: serial)
          ..addFlag('dry-run', negatable: false)
          ..addFlag('apply', negatable: false);
    ArgParser androidPairing() => androidMutation()
      ..addOption(
        'strategy',
        allowed: AndroidGatewayRouteStrategy.values.map((value) => value.name),
        defaultsTo: AndroidGatewayRouteStrategy.adbReverse.name,
      )
      ..addOption('host-port', mandatory: true)
      ..addOption('target-port', mandatory: true)
      ..addFlag('tls', negatable: false);
    final android = ArgParser()
      ..addCommand('discover', androidBase(serial: false))
      ..addCommand(
        'start',
        androidMutation(serial: false)
          ..addOption('avd', mandatory: true)
          ..addOption('port', mandatory: true)
          ..addFlag('headless', defaultsTo: true),
      )
      ..addCommand('managed-status', androidBase(serial: false))
      ..addCommand('stop', androidMutation(serial: false))
      ..addCommand('tls-install', androidMutation(serial: false))
      ..addCommand('tls-verify', androidBase(serial: false))
      ..addCommand('tls-remove', androidMutation(serial: false))
      ..addCommand('bootstrap', androidPairing())
      ..addCommand('update', androidPairing())
      ..addCommand('remove', androidMutation(serial: false))
      ..addCommand('verify', androidBase(serial: false))
      ..addCommand('install', androidBase()..addOption('apk', mandatory: true))
      ..addCommand(
        'launch',
        androidBase()
          ..addOption('package', mandatory: true)
          ..addOption('activity', mandatory: true)
          ..addOption(
            'strategy',
            allowed: AndroidGatewayRouteStrategy.values.map(
              (value) => value.name,
            ),
            defaultsTo: AndroidGatewayRouteStrategy.adbReverse.name,
          )
          ..addOption('host-port', mandatory: true)
          ..addOption('target-port', mandatory: true)
          ..addFlag('tls', negatable: false)
          ..addMultiOption('overlay'),
      )
      ..addCommand(
        'reset',
        androidBase()..addOption('package', mandatory: true),
      )
      ..addCommand('capture', androidBase())
      ..addCommand(
        'evidence',
        androidBase()
          ..addOption('catalog-digest', mandatory: true)
          ..addOption(
            'evidence-workspace',
            defaultsTo: '.',
            help: 'Workspace that owns the evidence CAS and release state.',
          )
          ..addOption('containment-report', mandatory: true)
          ..addOption('package', mandatory: true)
          ..addOption('launch-profile', defaultsTo: 'android')
          ..addOption('source-revision')
          ..addMultiOption('input-digest', help: 'Input KEY=sha256:...')
          ..addOption(
            'backend-mode',
            allowed: BackendMode.values.map((value) => value.name),
            defaultsTo: BackendMode.none.name,
          )
          ..addFlag('screenshot', defaultsTo: true)
          ..addFlag('semantics', defaultsTo: true)
          ..addFlag('logcat', defaultsTo: true)
          ..addFlag('screen-recording', defaultsTo: false)
          ..addFlag('performance-trace', defaultsTo: false)
          ..addFlag('synthetic-data-confirmed', negatable: false)
          ..addOption('duration-seconds', defaultsTo: '3')
          ..addOption('output'),
      );
    ArgParser applyMode() => ArgParser()
      ..addFlag('dry-run', negatable: false)
      ..addFlag('apply', negatable: false);
    final retention = ArgParser()
      ..addCommand('status')
      ..addCommand('gc', applyMode());
    final probe = ArgParser()
      ..addCommand(
        'run',
        ArgParser()
          ..addOption('plan', mandatory: true)
          ..addOption('gateway-plan', mandatory: true)
          ..addOption('origin', mandatory: true)
          ..addMultiOption('parameter')
          ..addMultiOption('stable-parameter'),
      );
    final source = ArgParser()
      ..addCommand(
        'inspect',
        ArgParser()
          ..addOption(
            'adapter',
            allowed: const <String>['filesystem', 'git'],
            defaultsTo: 'filesystem',
          )
          ..addOption('root', defaultsTo: '.')
          ..addOption('repository-id', defaultsTo: 'workspace')
          ..addOption('revision')
          ..addOption('output'),
      )
      ..addCommand(
        'diff',
        ArgParser()
          ..addOption('base', mandatory: true)
          ..addOption('current', mandatory: true)
          ..addOption('output'),
      );
    final impactPlan = ArgParser()
      ..addOption('change-set', mandatory: true)
      ..addOption('bindings', mandatory: true)
      ..addOption('output');
    final context = ArgParser()
      ..addCommand(
        'export',
        ArgParser()
          ..addOption('snapshot', mandatory: true)
          ..addOption('root', defaultsTo: '.')
          ..addMultiOption('path')
          ..addOption('output', mandatory: true),
      );
    final gate = ArgParser()
      ..addOption('impact-plan', mandatory: true)
      ..addMultiOption('subject');
    final plugin = ArgParser()
      ..addCommand(
        'list',
        ArgParser()..addOption('plugin-root', mandatory: true),
      )
      ..addCommand(
        'invoke',
        ArgParser()
          ..addOption('manifest', mandatory: true)
          ..addOption('plugin-root', mandatory: true)
          ..addOption('capability', mandatory: true)
          ..addOption('arguments', mandatory: true)
          ..addMultiOption('grant')
          ..addOption('preview-digest'),
      );
    final release = ArgParser()
      ..addCommand('build', catalogCommand())
      ..addCommand(
        'bundle',
        ArgParser()
          ..addOption('directory', mandatory: true)
          ..addOption('output', mandatory: true),
      )
      ..addCommand(
        'verify-bundle',
        ArgParser()..addOption('bundle', mandatory: true),
      )
      ..addCommand(
        'seal',
        ArgParser()
          ..addOption('bundle', mandatory: true)
          ..addOption('impact-plan', mandatory: true)
          ..addMultiOption('snapshot')
          ..addOption('policy', defaultsTo: 'source-impact-v1')
          ..addOption('output', mandatory: true),
      );
    ArgParser authLocation() => ArgParser()..addOption('credential-file');
    final auth = ArgParser()
      ..addCommand(
        'login',
        authLocation()
          ..addOption('issuer', mandatory: true)
          ..addOption('client-id', mandatory: true)
          ..addOption('hosted-url', mandatory: true)
          ..addOption('tenant', mandatory: true)
          ..addFlag('open-browser', defaultsTo: true),
      )
      ..addCommand('logout', authLocation())
      ..addCommand('status', authLocation());
    final workspace = ArgParser()
      ..addCommand(
        'link',
        ArgParser()
          ..addOption('hosted-url', mandatory: true)
          ..addOption('tenant', mandatory: true)
          ..addOption('workspace-id', mandatory: true),
      )
      ..addCommand(
        'push',
        ArgParser()
          ..addOption('change-set', mandatory: true)
          ..addOption('credential-file'),
      )
      ..addCommand(
        'pull',
        ArgParser()
          ..addOption('after', defaultsTo: '0')
          ..addOption('limit', defaultsTo: '500')
          ..addOption('output')
          ..addOption('credential-file'),
      );
    final publish = ArgParser()
      ..addOption('release', mandatory: true)
      ..addOption('release-digest', mandatory: true)
      ..addOption('expected-digest', mandatory: true)
      ..addOption('credential-file');
    ArgParser moduleQuery({bool module = false}) => ArgParser()
      ..addOption('config', abbr: 'c')
      ..addOption('profile')
      ..addOption('module', mandatory: module);
    final modules = ArgParser()
      ..addCommand('list', moduleQuery())
      ..addCommand('explain', moduleQuery(module: true))
      ..addCommand('doctor', moduleQuery());
    final parser = ArgParser()
      ..addFlag('json', negatable: false)
      ..addCommand('version')
      ..addCommand('doctor')
      ..addCommand('modules', modules)
      ..addCommand('init', adoptionMutation())
      ..addCommand(
        'adoption-report',
        ArgParser()..addOption('distribution', defaultsTo: 'full-local'),
      )
      ..addCommand('detach', adoptionMutation())
      ..addCommand('distribution', distribution);

    bool enabled(String moduleId) =>
        enabledModuleIds == null || enabledModuleIds.contains(moduleId);
    bool anyEnabled(Iterable<String> moduleIds) => moduleIds.any(enabled);

    final evidence = ArgParser();
    if (enabled('evidence.auto-preview')) {
      evidence.addCommand('collect-previews', collectPreviews);
    }
    if (enabled('evidence.tests')) {
      evidence
        ..addCommand('collect-tests', collectTests)
        ..addCommand('compare-visual', evidenceComparison())
        ..addCommand('compare-semantics', evidenceComparison());
    }
    if (enabled('artifact-store.local')) {
      evidence
        ..addCommand(
          'import-artifact',
          ArgParser()
            ..addOption('input', mandatory: true)
            ..addOption(
              'media-type',
              mandatory: true,
              help:
                  'Closed media profile: '
                  '${ScenarioLabSupplementalArtifactMediaType.values.map((value) => value.value).join(', ')}.',
            )
            ..addOption(
              'classification',
              mandatory: true,
              help:
                  'Artifact classification: '
                  '${ArtifactClassification.values.map((value) => value.name).join(', ')}.',
            )
            ..addOption('source-id', mandatory: true)
            ..addOption('import-policy', mandatory: true)
            ..addOption(
              'config',
              abbr: 'c',
              help: 'Explicit consumer config path.',
            )
            ..addOption(
              'profile',
              help: 'Override the configured Kit profile.',
            ),
        )
        ..addCommand(
          'export-artifact',
          ArgParser()
            ..addOption('digest', mandatory: true)
            ..addOption('output', mandatory: true),
        );
    }
    if (anyEnabled(const <String>[
      'evidence.auto-preview',
      'evidence.tests',
      'artifact-store.local',
    ])) {
      parser.addCommand('evidence', evidence);
    }
    if (enabled('target.android')) {
      parser.addCommand('target', ArgParser()..addCommand('android', android));
    }
    if (enabled('gateway.interceptor')) {
      parser
        ..addCommand('probe', probe)
        ..addCommand('gateway', gateway);
    }
    if (enabled('source.impact')) {
      parser
        ..addCommand('source', source)
        ..addCommand('plan', impactPlan)
        ..addCommand('context', context)
        ..addCommand('gate', gate);
    }
    if (enabled('artifact-store.local')) {
      parser.addCommand('retention', retention);
    }
    if (enabled('plugins.external')) {
      parser.addCommand('plugin', plugin);
    }
    if (enabled('automation.mcp')) {
      parser.addCommand(
        'mcp',
        ArgParser()..addCommand(
          'serve',
          ArgParser()
            ..addOption(
              'config',
              abbr: 'c',
              help: 'Explicit consumer config path.',
            )
            ..addOption(
              'profile',
              help: 'Override the configured Kit profile.',
            ),
        ),
      );
    }
    if (enabled('hosted.collaboration')) {
      parser
        ..addCommand('auth', auth)
        ..addCommand('workspace', workspace)
        ..addCommand('publish', publish);
    }
    if (enabled('catalog')) {
      parser
        ..addCommand('validate', catalogCommand())
        ..addCommand('explain', catalogCommand())
        ..addCommand('compile', catalogCommand())
        ..addCommand('dev', dev);
    }
    if (enabled('capture.app-adapter')) {
      parser.addCommand('capture', capture);
    }
    if (enabled('release.local')) {
      parser.addCommand('release', release);
    }
    if (enabled('sessions.local')) {
      parser.addCommand(
        'session',
        ArgParser()..addCommand(
          'start',
          ArgParser()
            ..addOption('host')
            ..addOption('token')
            ..addOption('studio-origin')
            ..addOption('launch-profile')
            ..addOption('target-origin'),
        ),
      );
    }
    return parser;
  }

  static const Map<String, Set<String>> _conditionalCommandModules =
      <String, Set<String>>{
        'validate': <String>{'catalog'},
        'explain': <String>{'catalog'},
        'compile': <String>{'catalog'},
        'dev': <String>{'catalog'},
        'capture': <String>{'capture.app-adapter'},
        'session': <String>{'sessions.local'},
        'gateway': <String>{'gateway.interceptor'},
        'probe': <String>{'gateway.interceptor'},
        'evidence': <String>{
          'evidence.auto-preview',
          'evidence.tests',
          'artifact-store.local',
        },
        'target': <String>{'target.android'},
        'migrate': <String>{'source.impact'},
        'retention': <String>{'artifact-store.local'},
        'source': <String>{'source.impact'},
        'plan': <String>{'source.impact'},
        'context': <String>{'source.impact'},
        'gate': <String>{'source.impact'},
        'plugin': <String>{'plugins.external'},
        'mcp': <String>{'automation.mcp'},
        'auth': <String>{'hosted.collaboration'},
        'workspace': <String>{'hosted.collaboration'},
        'publish': <String>{'hosted.collaboration'},
        'release': <String>{'release.local'},
      };

  String? _requestedTopLevelCommand(List<String> arguments) {
    for (final argument in arguments) {
      if (argument == '--json') continue;
      if (!argument.startsWith('-')) return argument;
    }
    return null;
  }

  String? _rawOption(
    List<String> arguments,
    String name, {
    String? abbreviation,
  }) {
    final longPrefix = '--$name=';
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument.startsWith(longPrefix)) {
        return argument.substring(longPrefix.length);
      }
      if (argument == '--$name' ||
          (abbreviation != null && argument == '-$abbreviation')) {
        if (index + 1 < arguments.length) return arguments[index + 1];
        return null;
      }
    }
    return null;
  }

  CliResult _modules(ArgResults command, {required bool json}) {
    final operation = command.command;
    final commandName = 'modules ${operation?.name ?? ''}'.trim();
    try {
      if (operation == null ||
          !const <String>{
            'list',
            'explain',
            'doctor',
          }.contains(operation.name)) {
        throw const FormatException(
          'Usage: workspace modules <list|explain|doctor>',
        );
      }
      final loaded = const CliKitPlanLoader().load(
        workspaceDirectory: workspaceDirectory,
        explicitConfigPath: operation.option('config'),
        profileOverride: operation.option('profile'),
        allowMissingWorkspace: true,
      );
      final enabled = <ModuleId, ResolvedModule>{
        for (final module in loaded.plan.enabledModules)
          module.moduleId: module,
      };
      Map<String, Object?> moduleJson(ModuleDescriptor descriptor) {
        final resolved = enabled[descriptor.id];
        return <String, Object?>{
          'id': descriptor.id.value,
          'version': descriptor.version,
          'packaged': true,
          'enabled': resolved != null,
          'ready': false,
          'authorized': false,
          'provides': descriptor.provides
              .map((capability) => capability.key)
              .toList(growable: false),
          'requires': descriptor.requires
              .map((requirement) => requirement.capability.key)
              .toList(growable: false),
          'optionalRequires': descriptor.optionalRequires
              .map((requirement) => requirement.capability.key)
              .toList(growable: false),
          'surfaces':
              descriptor.surfaces
                  .map((surface) => surface.name)
                  .toList(growable: false)
                ..sort(),
          'effects':
              descriptor.effects
                  .map((effect) => effect.name)
                  .toList(growable: false)
                ..sort(),
          'resourceRequirements':
              descriptor.resourceRequirements
                  .map((resource) => resource.name)
                  .toList(growable: false)
                ..sort(),
          if (resolved != null) 'settings': resolved.settings,
        };
      }

      final common = <String, Object?>{
        'distributionId': loaded.catalog.distributionId,
        'catalogDigest': loaded.catalog.digest.value,
        'profileId': loaded.plan.profileId,
        'planDigest': loaded.plan.digest.value,
        'workspaceConfigured': loaded.configuration != null,
      };
      if (operation.name == 'explain') {
        final id = ModuleId(operation.option('module')!);
        final descriptor = loaded.catalog.modules
            .where((module) => module.id == id)
            .firstOrNull;
        if (descriptor == null) {
          throw FormatException('Module ${id.value} is not packaged');
        }
        final result = <String, Object?>{
          ...common,
          'module': moduleJson(descriptor),
          'selectionSource': enabled.containsKey(id)
              ? 'profile-and-overlays'
              : 'not-selected',
          'precedence': const <String>[
            'kernel',
            'distribution',
            'profile',
            'workspace',
            'local',
            'startup',
          ],
        };
        return _success(
          command: commandName,
          result: result,
          human:
              '${id.value}: ${enabled.containsKey(id) ? 'enabled' : 'disabled'} '
              'by ${loaded.plan.profileId}',
          json: json,
          effectiveContext: common,
        );
      }
      final modulesJson = <Object?>[
        for (final descriptor in loaded.catalog.modules) moduleJson(descriptor),
      ];
      final result = <String, Object?>{
        ...common,
        'modules': modulesJson,
        'diagnostics': loaded.plan.diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(growable: false),
        if (operation.name == 'doctor' &&
            enabled.containsKey(ModuleId('evidence.auto-preview')))
          'runtimeLimitations': _autoPreviewRuntimeLimitations,
      };
      final enabledCount = enabled.length;
      return _success(
        command: commandName,
        result: result,
        human: operation.name == 'doctor'
            ? 'Kit plan valid: $enabledCount modules, ${loaded.plan.profileId}'
            : '$enabledCount of ${loaded.catalog.modules.length} modules enabled '
                  'by ${loaded.plan.profileId}',
        json: json,
        effectiveContext: common,
      );
    } on KitPlanResolutionException catch (error) {
      return _failure(commandName, error.issues.join('; '), json: json);
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    }
  }

  static const List<Map<String, Object?>>
  _autoPreviewRuntimeLimitations = <Map<String, Object?>>[
    <String, Object?>{
      'code': 'preview.fidelity.structural',
      'message':
          'flutter-test provides structural fidelity only, never host-native.',
    },
    <String, Object?>{
      'code': 'preview.detector.workspace-regression',
      'message':
          'Flutter 3.47.0 Previewer fails for the Pub Workspace consumer; use the verified controlled preview runner while the interactive flow remains blocked.',
    },
    <String, Object?>{
      'code': 'preview.export.runner-owned',
      'message':
          'Widget Previewer is interactive; the controlled preview runner, not Previewer, exports PNG Evidence.',
    },
    <String, Object?>{
      'code': 'preview.sandbox.host-dependent',
      'message':
          'Portable network and memory containment depends on a sandbox proved by the host.',
    },
    <String, Object?>{
      'code': 'preview.native.not-proved',
      'message':
          'AutoPreview does not prove native plugins, OS behavior, permissions, or keyboard behavior.',
    },
  ];

  Future<CliResult> _collectPreviewEvidence(
    ArgResults operation, {
    required String commandName,
    required bool json,
  }) async {
    final loadedPlan = const CliKitPlanLoader().load(
      workspaceDirectory: workspaceDirectory,
      explicitConfigPath: operation.option('config'),
      profileOverride: operation.option('profile'),
    );
    if (!loadedPlan.plan.enabledModules.any(
      (module) => module.moduleId.value == 'evidence.auto-preview',
    )) {
      throw StateError(
        'Command unavailable: module evidence.auto-preview is disabled in '
        '${loadedPlan.plan.profileId}',
      );
    }
    final previewModule = loadedPlan.plan.enabledModules.singleWhere(
      (module) => module.moduleId.value == 'evidence.auto-preview',
    );
    final renderer = previewModule.settings['renderer'] as String;
    final capturePolicyId = previewModule.settings['capturePolicy'] as String;
    if (renderer != 'flutter-test') {
      throw FormatException('Unsupported AutoPreview renderer $renderer');
    }
    if (capturePolicyId != 'static-v1') {
      throw FormatException(
        'Unsupported AutoPreview capture policy $capturePolicyId',
      );
    }
    final configuration = loadedPlan.configuration!;
    final applicationId = operation.option('application')!;
    final application = configuration.applications[applicationId];
    if (application == null) {
      throw FormatException('Unknown Application $applicationId');
    }
    final loadedCatalog = const WorkspaceCatalogLoader().loadFromConfiguration(
      configuration,
    );
    final catalog = const CatalogCompiler().compile(
      loadedCatalog.documents,
      layout: loadedCatalog.layout,
    );
    final scan = await const PreviewSourceScanner().scan(
      applicationRoot: application.resolvedRoot,
    );
    final compiled = const PreviewManifestCompiler().compile(
      candidates: scan.candidates,
      catalog: catalog,
      flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
    );
    final scenarioFilter = operation.option('scenario');
    final variantFilter = operation.option('variant');
    final descriptors = compiled.descriptors
        .where((descriptor) {
          return descriptor.variant.applicationId.value == applicationId &&
              (scenarioFilter == null ||
                  descriptor.scenarioId.value == scenarioFilter) &&
              (variantFilter == null ||
                  descriptor.variant.id.value == variantFilter);
        })
        .toList(growable: false);
    if (descriptors.isEmpty) {
      throw const FormatException(
        'No AutoPreview matches the selected Application/Scenario/Variant',
      );
    }
    final previewManifest = PreviewManifest(
      catalogDigest: compiled.catalogDigest,
      flutterCompatibility: compiled.flutterCompatibility,
      descriptors: descriptors,
    );
    final registry = await const EphemeralPreviewRegistryWriter().write(
      applicationRoot: application.resolvedRoot,
      planDigest: loadedPlan.plan.digest,
      manifest: previewManifest,
      scan: scan,
    );
    final toolchain = await _previewToolchain(application.resolvedRoot);
    final toolchainDigest = Digest.semantic(toolchain);
    final inputDigests = _previewInputDigests(application.resolvedRoot)
      ..['plan'] = loadedPlan.plan.digest
      ..['previewManifest'] = previewManifest.digest;
    final fingerprint = ExecutionFingerprint(
      catalogDigest: catalog.digest,
      launchProfileId: 'preview-${loadedPlan.plan.profileId}',
      targetId: 'preview.$renderer',
      platform: loadedPlan.catalog.platform,
      renderer: renderer,
      runtimeFidelity: RuntimeFidelity.structural,
      backendMode: BackendMode.none,
      networkContainment: NetworkContainment.unconstrained,
      bootstrapAssessment: BootstrapAssessment.controlled,
      toolchain: toolchain,
      capabilities: const <String>{'evidence.visual.preview'},
      inputDigests: inputDigests,
      policies: <String, String>{'capture': capturePolicyId},
    );
    final store = FileSystemWorkspaceStore(
      workspaceRoot: configuration.workspaceRoot,
    );
    final run = await PreviewCaptureRunner(store: store).run(
      applicationRoot: application.resolvedRoot,
      previewManifest: previewManifest,
      registry: registry,
      fingerprint: fingerprint,
      planDigest: loadedPlan.plan.digest,
      toolchainDigest: toolchainDigest,
      policies: <String, PreviewStabilizationPolicy>{
        capturePolicyId: PreviewStabilizationPolicy(id: capturePolicyId),
      },
      syntheticDataConfirmed: operation.flag('synthetic-data-confirmed'),
      inputDigests: inputDigests,
    );
    final repository = LocalEvidenceRepository(store: store);
    final evidence = PreviewEvidenceProvider(
      store: store,
      repository: repository,
    ).persist(run: run, fingerprint: fingerprint);
    final result = <String, Object?>{
      'applicationId': applicationId,
      'profileId': loadedPlan.plan.profileId,
      'planDigest': loadedPlan.plan.digest.value,
      'previewManifest': previewManifest.toJson(),
      'captureManifest': run.manifest.toJson(),
      'report': run.report.toJson(),
      'evidence': evidence.toJson(),
    };
    final output = operation.option('output');
    if (output != null) {
      _writeCanonicalDocument(output, result);
      result['output'] = _absoluteWorkspacePath(output);
    }
    if (run.report.failedItems > 0) {
      return _policyDenied(
        commandName,
        '${run.report.failedItems} AutoPreview capture(s) were not collected.',
        result: result,
        json: json,
      );
    }
    return _success(
      command: commandName,
      result: result,
      human:
          '${run.report.collectedItems} AutoPreview capture(s) collected as '
          'structural Evidence',
      json: json,
      effectiveContext: <String, Object?>{
        'workspaceRoot': configuration.workspaceRoot,
        'applicationRoot': application.resolvedRoot,
        'profileId': loadedPlan.plan.profileId,
        'planDigest': loadedPlan.plan.digest.value,
        'runtimeFidelity': RuntimeFidelity.structural.name,
      },
    );
  }

  Future<Map<String, String>> _previewToolchain(String workingDirectory) async {
    final result = await Process.run('flutter', const <String>[
      '--version',
      '--machine',
    ], workingDirectory: workingDirectory).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw const FormatException('Flutter toolchain inspection failed');
    }
    final value = jsonDecode(result.stdout as String);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Flutter toolchain response is invalid');
    }
    String field(String name) {
      final item = value[name];
      if (item is! String || item.isEmpty) {
        throw FormatException('Flutter toolchain is missing $name');
      }
      return item;
    }

    return <String, String>{
      'flutter': field('frameworkVersion'),
      'dart': field('dartSdkVersion'),
      'engine': field('engineRevision'),
      'workspace': version,
    };
  }

  Map<String, Digest> _previewInputDigests(String applicationRoot) {
    final root = Directory(applicationRoot).resolveSymbolicLinksSync();
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync() || Link(pubspec.path).existsSync()) {
      throw FileSystemException(
        'Flutter Application pubspec is unavailable',
        pubspec.path,
      );
    }
    final files = <String, String>{};
    final lib = Directory(p.join(root, 'lib'));
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Links are forbidden in preview source',
          entity.path,
        );
      }
      if (entity is File && p.extension(entity.path) == '.dart') {
        files[p.relative(entity.path, from: root)] = Digest.bytes(
          entity.readAsBytesSync(),
        ).value;
      }
    }
    final result = <String, Digest>{
      'application.pubspec': Digest.bytes(pubspec.readAsBytesSync()),
      'application.lib': Digest.semantic(<String, Object?>{'files': files}),
    };
    final workspaceReference = File(
      p.join(root, '.dart_tool', 'pub', 'workspace_ref.json'),
    );
    File? lock;
    if (workspaceReference.existsSync() &&
        !Link(workspaceReference.path).existsSync()) {
      final reference = jsonDecode(workspaceReference.readAsStringSync());
      if (reference is Map<String, Object?> &&
          reference['workspaceRoot'] is String) {
        final candidate = Directory(
          p.normalize(
            p.join(
              workspaceReference.parent.path,
              reference['workspaceRoot']! as String,
            ),
          ),
        );
        if (candidate.existsSync()) {
          final resolved = candidate.resolveSymbolicLinksSync();
          if (resolved == root || p.isWithin(resolved, root)) {
            lock = File(p.join(resolved, 'pubspec.lock'));
          }
        }
      }
    }
    lock ??= File(p.join(root, 'pubspec.lock'));
    if (lock.existsSync() && !Link(lock.path).existsSync()) {
      result['pubspec.lock'] = Digest.bytes(lock.readAsBytesSync());
    }
    return result;
  }

  Future<CliResult> _hostedAuth(
    ArgResults command, {
    required bool json,
  }) async {
    final operation = command.command;
    final commandName = 'auth ${operation?.name ?? ''}'.trim();
    try {
      if (operation == null) {
        throw const FormatException(
          'Usage: workspace auth <login|logout|status>',
        );
      }
      final credentials = _HostedCredentialStore(
        _credentialPath(operation.option('credential-file')),
      );
      if (operation.name == 'status') {
        final value = credentials.read();
        if (value == null) {
          return _preconditionFailure(
            commandName,
            'No hosted authentication is configured.',
            json: json,
          );
        }
        final expired = !value.expiresAt.isAfter(DateTime.now().toUtc());
        if (expired) {
          return _preconditionFailure(
            commandName,
            'Hosted authentication has expired.',
            json: json,
          );
        }
        return _success(
          command: commandName,
          result: value.redactedJson(),
          human: 'Authenticated as ${value.subject} for ${value.tenantId}',
          json: json,
        );
      }
      if (operation.name == 'logout') {
        final removed = credentials.delete();
        return _success(
          command: commandName,
          result: <String, Object?>{'removed': removed},
          human: removed
              ? 'Hosted authentication removed'
              : 'Already logged out',
          json: json,
        );
      }
      if (operation.name != 'login') {
        throw const FormatException(
          'Usage: workspace auth <login|logout|status>',
        );
      }
      final issuer = _secureHostedUri(operation.option('issuer')!, 'issuer');
      final hostedUrl = _secureHostedUri(
        operation.option('hosted-url')!,
        'hosted-url',
      );
      final transport = DartIoOidcHttpTransport(
        allowedOrigins: <String>{issuer.origin},
      );
      final discovery = await transport.getJson(
        issuer.resolve('.well-known/openid-configuration'),
      );
      Uri endpoint(String key) {
        final raw = discovery[key];
        if (raw is! String) {
          throw FormatException('OIDC discovery is missing $key');
        }
        final uri = _secureHostedUri(raw, key);
        if (uri.origin != issuer.origin) {
          throw FormatException('$key must use the configured issuer origin');
        }
        return uri;
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri.parse(
        'http://127.0.0.1:${server.port}/oauth/callback',
      );
      final authenticator = OidcPkceAuthenticator(
        configuration: OidcConfiguration(
          issuer: issuer,
          authorizationEndpoint: endpoint('authorization_endpoint'),
          tokenEndpoint: endpoint('token_endpoint'),
          jwksUri: endpoint('jwks_uri'),
          clientId: operation.option('client-id')!,
          allowedAlgorithms: const <String>{'RS256', 'PS256', 'ES256'},
        ),
        transport: transport,
        clock: SystemClock(),
      );
      final login = authenticator.beginLogin(redirectUri: redirectUri);
      if (operation.flag('open-browser')) {
        final result = await Process.run('xdg-open', <String>[
          login.authorizationUri.toString(),
        ]);
        if (result.exitCode != 0) {
          await server.close(force: true);
          throw const FormatException('Could not open the system browser');
        }
      } else if (!json) {
        stdout.writeln('Open: ${login.authorizationUri}');
      }
      final callback = await server.first.timeout(const Duration(minutes: 5));
      final error = callback.uri.queryParameters['error'];
      final state = callback.uri.queryParameters['state'];
      final code = callback.uri.queryParameters['code'];
      callback.response
        ..statusCode = error == null ? 200 : 400
        ..headers.contentType = ContentType.html
        ..write(
          error == null
              ? '<!doctype html><title>Abel</title>Authentication complete. You may close this window.'
              : '<!doctype html><title>Abel</title>Authentication failed.',
        );
      await callback.response.close();
      await server.close(force: true);
      if (error != null || state == null || code == null) {
        throw FormatException(
          'OIDC authorization failed${error == null ? '' : ': $error'}',
        );
      }
      final result = await authenticator.completeLogin(
        state: state,
        code: code,
      );
      final record = _HostedCredential(
        hostedUrl: hostedUrl,
        tenantId: operation.option('tenant')!,
        issuer: result.identity.issuer,
        subject: result.identity.subject,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresAt: result.accessTokenExpiresAt,
      );
      credentials.write(record);
      return _success(
        command: commandName,
        result: record.redactedJson(),
        human: 'Authenticated as ${record.subject} for ${record.tenantId}',
        json: json,
      );
    } on TimeoutException {
      return _preconditionFailure(
        commandName,
        'OIDC login timed out.',
        json: json,
      );
    } on OidcAuthenticationException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(commandName, error.message, json: json);
    }
  }

  Future<CliResult> _hostedWorkspace(
    ArgResults command, {
    required bool json,
  }) async {
    final operation = command.command;
    final commandName = 'workspace ${operation?.name ?? ''}'.trim();
    try {
      if (operation == null) {
        throw const FormatException(
          'Usage: workspace workspace <link|push|pull>',
        );
      }
      final linkStore = _HostedLinkStore(
        p.join(workspaceDirectory, '.experience', 'hosted-link.json'),
      );
      if (operation.name == 'link') {
        final link = _HostedLink(
          hostedUrl: _secureHostedUri(
            operation.option('hosted-url')!,
            'hosted-url',
          ),
          tenantId: operation.option('tenant')!,
          workspaceId: operation.option('workspace-id')!,
          localWorkspaceId: p.basename(workspaceDirectory),
          linkedAt: DateTime.now().toUtc(),
        );
        linkStore.write(link);
        return _success(
          command: commandName,
          result: link.toJson(),
          human: 'Workspace linked to ${link.workspaceId}',
          json: json,
        );
      }
      final link = linkStore.read();
      final credential = _HostedCredentialStore(
        _credentialPath(operation.option('credential-file')),
      ).read();
      if (credential == null ||
          credential.tenantId != link.tenantId ||
          credential.hostedUrl != link.hostedUrl ||
          !credential.expiresAt.isAfter(DateTime.now().toUtc())) {
        return _preconditionFailure(
          commandName,
          'Hosted authentication is missing, expired, or does not match the workspace link.',
          json: json,
        );
      }
      final client = _HostedApiClient(credential);
      try {
        if (operation.name == 'push') {
          final change = WorkspaceChangeSet.fromJson(
            _readJsonDocument(operation.option('change-set')!),
          );
          if (change.tenantId != link.tenantId ||
              change.workspaceId != link.workspaceId) {
            throw const FormatException(
              'change set does not match the hosted workspace link',
            );
          }
          final response = await client.post(
            '/v1/workspaces/${Uri.encodeComponent(link.workspaceId)}/push',
            change.toJson(),
          );
          return _hostedResponse(
            commandName,
            response,
            successMessage: 'Workspace push completed',
            json: json,
          );
        }
        if (operation.name == 'pull') {
          final after = int.tryParse(operation.option('after')!);
          final limit = int.tryParse(operation.option('limit')!);
          if (after == null ||
              after < 0 ||
              limit == null ||
              limit < 1 ||
              limit > 1000) {
            throw const FormatException('pull cursor or limit is invalid');
          }
          final response = await client.get(
            '/v1/workspaces/${Uri.encodeComponent(link.workspaceId)}/events',
            <String, String>{'after': '$after', 'limit': '$limit'},
          );
          final output = operation.option('output');
          if (response.statusCode == 200 && output != null) {
            _writeCanonicalDocument(output, response.body);
          }
          return _hostedResponse(
            commandName,
            response,
            successMessage: 'Workspace changes pulled',
            json: json,
          );
        }
        throw const FormatException(
          'Usage: workspace workspace <link|push|pull>',
        );
      } finally {
        client.close();
      }
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on SocketException catch (error) {
      return CliResult(
        exitCode: 5,
        stderr: 'Hosted service unavailable: ${error.message}\n',
      );
    }
  }

  Future<CliResult> _hostedPublish(
    ArgResults command, {
    required bool json,
  }) async {
    const commandName = 'publish';
    try {
      final link = _HostedLinkStore(
        p.join(workspaceDirectory, '.experience', 'hosted-link.json'),
      ).read();
      final credential = _HostedCredentialStore(
        _credentialPath(command.option('credential-file')),
      ).read();
      if (credential == null ||
          credential.tenantId != link.tenantId ||
          credential.hostedUrl != link.hostedUrl ||
          !credential.expiresAt.isAfter(DateTime.now().toUtc())) {
        return _preconditionFailure(
          commandName,
          'Hosted authentication is missing, expired, or mismatched.',
          json: json,
        );
      }
      final releaseDocument = _readJsonDocument(command.option('release')!);
      Release.fromJson(
        releaseDocument,
        expectedDigest: Digest(command.option('release-digest')!),
      );
      final client = _HostedApiClient(credential);
      try {
        final response = await client.post(
          '/v1/workspaces/${Uri.encodeComponent(link.workspaceId)}/publish',
          <String, Object?>{
            'expectedDigest': command.option('expected-digest'),
            'releaseDigest': command.option('release-digest'),
            'release': releaseDocument,
          },
        );
        return _hostedResponse(
          commandName,
          response,
          successMessage: 'Release published',
          json: json,
        );
      } finally {
        client.close();
      }
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on SocketException catch (error) {
      return CliResult(
        exitCode: 5,
        stderr: 'Hosted service unavailable: ${error.message}\n',
      );
    }
  }

  CliResult _hostedResponse(
    String command,
    _HostedApiResponse response, {
    required String successMessage,
    required bool json,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _success(
        command: command,
        result: response.body,
        human: successMessage,
        json: json,
      );
    }
    final code = response.body['code'];
    final message = response.body['message'] ?? code ?? 'Hosted request failed';
    final exit = response.statusCode == 409 || response.statusCode == 403
        ? 4
        : 5;
    if (!json) return CliResult(exitCode: exit, stderr: '$message\n');
    final output = MachineOutput(
      command: command,
      ok: false,
      correlationId: null,
      effectiveContext: const <String, Object?>{},
      result: response.body,
      failures: <PlatformFailure>[
        PlatformFailure(
          code: code is String ? code : 'CONTROL_PLANE_FAILED',
          category: exit == 4
              ? FailureCategory.policyDenied
              : FailureCategory.transportFailure,
          message: '$message',
          recoverability: Recoverability.userAction,
        ),
      ],
      diagnostics: const <MachineDiagnostic>[],
    );
    return CliResult(
      exitCode: exit,
      stderr: '${jsonEncode(output.toJson())}\n',
    );
  }

  String _credentialPath(String? explicit) {
    if (explicit != null) return p.absolute(explicit);
    final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
    final userDirectory = Platform.environment['HOME'];
    if (xdgConfig == null && userDirectory == null) {
      throw const FormatException(
        'XDG_CONFIG_HOME or HOME is required for hosted auth',
      );
    }
    final configRoot = xdgConfig ?? p.join(userDirectory!, '.config');
    return p.join(configRoot, 'workspace', 'hosted-auth.json');
  }

  Uri _secureHostedUri(String value, String name) {
    final uri = Uri.parse(value);
    final loopback =
        uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
    if (!uri.isAbsolute ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw FormatException('$name must be HTTPS (or loopback HTTP)');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }

  Future<CliResult> _source(ArgResults command, {required bool json}) async {
    final operation = command.command;
    final commandName = 'source ${operation?.name ?? ''}'.trim();
    try {
      if (operation?.name == 'inspect') {
        final root = _absoluteWorkspacePath(operation!.option('root')!);
        final repositoryId = operation.option('repository-id')!;
        final snapshot = operation.option('adapter') == 'git'
            ? await const GitSourceAdapter().inspect(
                root: root,
                repositoryId: repositoryId,
                revision: operation.option('revision'),
              )
            : const FilesystemSourceAdapter().inspect(
                root: root,
                repositoryId: repositoryId,
              );
        final output = operation.option('output');
        if (output != null) _writeCanonicalDocument(output, snapshot.toJson());
        return _success(
          command: commandName,
          result: <String, Object?>{
            'snapshot': snapshot.toJson(),
            if (output != null) 'output': _absoluteWorkspacePath(output),
          },
          human:
              'Source snapshot ${snapshot.digest.value} (${snapshot.completeness.name})',
          json: json,
          effectiveContext: <String, Object?>{
            'root': root,
            'adapter': operation.option('adapter'),
          },
        );
      }
      if (operation?.name == 'diff') {
        final base = SourceSnapshot.fromJson(
          _readJsonDocument(operation!.option('base')!),
        );
        final current = SourceSnapshot.fromJson(
          _readJsonDocument(operation.option('current')!),
        );
        final changes = const SourceImpactEngine().diff(base, current);
        final output = operation.option('output');
        if (output != null) _writeCanonicalDocument(output, changes.toJson());
        return _success(
          command: commandName,
          result: <String, Object?>{
            'changeSet': changes.toJson(),
            if (output != null) 'output': _absoluteWorkspacePath(output),
          },
          human:
              'Source diff ${changes.digest.value}: ${changes.changes.length} change(s)',
          json: json,
        );
      }
      throw const FormatException(
        'Usage: workspace source <inspect|diff> [options]',
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _impactPlan(
    ArgResults command, {
    required bool json,
  }) async {
    const commandName = 'plan';
    try {
      final changes = ChangeSet.fromJson(
        _readJsonDocument(command.option('change-set')!),
      );
      final rawBindings = _readJsonDocument(command.option('bindings')!);
      final bindingValues =
          rawBindings is Map<String, Object?> &&
              rawBindings['bindings'] is List<Object?>
          ? rawBindings['bindings']! as List<Object?>
          : throw const FormatException(
              'Bindings document must contain a bindings array',
            );
      final bindings = bindingValues
          .map(SourceBinding.fromJson)
          .toList(growable: false);
      final plan = const SourceImpactEngine().plan(changes, bindings);
      final output = command.option('output');
      if (output != null) _writeCanonicalDocument(output, plan.toJson());
      return _success(
        command: commandName,
        result: <String, Object?>{
          'impactPlan': plan.toJson(),
          if (output != null) 'output': _absoluteWorkspacePath(output),
        },
        human:
            'Impact ${plan.digest.value}: ${plan.impacted.length} impacted, complete=${plan.complete}',
        json: json,
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _context(ArgResults command, {required bool json}) async {
    const commandName = 'context export';
    final operation = command.command;
    try {
      if (operation?.name != 'export') {
        throw const FormatException(
          'Usage: workspace context export [options]',
        );
      }
      final snapshot = SourceSnapshot.fromJson(
        _readJsonDocument(operation!.option('snapshot')!),
      );
      final bundle = const LocalContextBundleExporter().export(
        snapshot: snapshot,
        root: _absoluteWorkspacePath(operation.option('root')!),
        paths: operation.multiOption('path'),
      );
      final output = operation.option('output')!;
      _writeCanonicalDocument(output, bundle.toJson());
      return _success(
        command: commandName,
        result: <String, Object?>{
          'contextDigest': bundle.digest.value,
          'files': bundle.files.length,
          'redactions': bundle.redactions,
          'output': _absoluteWorkspacePath(output),
        },
        human:
            'Context bundle ${bundle.digest.value}: ${bundle.files.length} file(s)',
        json: json,
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _gate(ArgResults command, {required bool json}) async {
    const commandName = 'gate';
    try {
      final plan = ImpactPlan.fromJson(
        _readJsonDocument(command.option('impact-plan')!),
      );
      final subjects = command.multiOption('subject').toSet();
      final reusable = plan.reusableSubjects.toSet();
      final passed =
          plan.complete && (subjects.isEmpty || reusable.containsAll(subjects));
      final result = <String, Object?>{
        'passed': passed,
        'impactPlanDigest': plan.digest.value,
        'complete': plan.complete,
        'requestedSubjects': subjects.toList()..sort(),
        'reusableSubjects': plan.reusableSubjects,
        'impacted': <Object?>[for (final item in plan.impacted) item.toJson()],
      };
      if (!passed) {
        return _policyDenied(
          commandName,
          'Source impact cannot prove that the requested evidence is reusable.',
          result: result,
          json: json,
        );
      }
      return _success(
        command: commandName,
        result: result,
        human: 'Source impact gate passed',
        json: json,
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _plugin(ArgResults command, {required bool json}) async {
    final operation = command.command;
    final commandName = 'plugin ${operation?.name ?? ''}'.trim();
    try {
      if (operation?.name == 'list') {
        final plugins = const LocalPluginRegistry().discover(
          _absoluteWorkspacePath(operation!.option('plugin-root')!),
        );
        return _success(
          command: commandName,
          result: <String, Object?>{
            'plugins': <Object?>[
              for (final plugin in plugins)
                <String, Object?>{
                  'manifest': plugin.manifest.toJson(),
                  'manifestDigest': plugin.manifestDigest.value,
                  'directory': plugin.directory,
                },
            ],
          },
          human: 'Discovered ${plugins.length} plugin(s)',
          json: json,
        );
      }
      if (operation?.name != 'invoke') {
        throw const FormatException(
          'Usage: workspace plugin <list|invoke> [options]',
        );
      }
      final manifest = PluginManifest.fromJson(
        _readJsonDocument(operation!.option('manifest')!),
      );
      final arguments = _readJsonDocument(operation.option('arguments')!);
      if (arguments is! Map<String, Object?>) {
        throw const FormatException('Plugin arguments must be an object');
      }
      final preview = operation.option('preview-digest');
      final invoked =
          await PluginProcessHost(
            pluginRoot: _absoluteWorkspacePath(
              operation.option('plugin-root')!,
            ),
          ).invoke(
            manifest: manifest,
            capability: operation.option('capability')!,
            arguments: arguments,
            grants: operation.multiOption('grant').toSet(),
            previewDigest: preview == null ? null : Digest(preview),
          );
      return _success(
        command: commandName,
        result: <String, Object?>{
          'pluginId': invoked.pluginId,
          'capability': invoked.capability,
          'protocolVersion': invoked.protocolVersion,
          'result': invoked.result,
        },
        human: 'Plugin ${invoked.pluginId} completed ${invoked.capability}',
        json: json,
      );
    } on PluginInvocationException catch (error) {
      return _policyDenied(
        commandName,
        error.message,
        result: null,
        json: json,
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _mcp(ArgResults command, {required bool json}) async {
    final operation = command.command;
    if (operation?.name != 'serve') {
      return _failure('mcp', 'Usage: workspace mcp serve', json: json);
    }
    final LocalExperienceMcpBackend backend;
    final LoadedWorkspaceConfiguration configuration;
    try {
      final loaded = const CliKitPlanLoader().load(
        workspaceDirectory: workspaceDirectory,
        explicitConfigPath: operation!.option('config'),
        profileOverride: operation.option('profile'),
      );
      final loadedConfiguration = loaded.configuration;
      if (loadedConfiguration == null) {
        throw const FormatException('Workspace configuration is required');
      }
      configuration = loadedConfiguration;
      backend = LocalExperienceMcpBackend.create(
        configuration: loadedConfiguration,
        plan: loaded.plan,
      );
    } on Object {
      return _failure(
        'mcp',
        'MCP Experience backend is unavailable',
        json: json,
      );
    }
    await ReadOnlyMcpServer(
      workspaceRoot: configuration.workspaceRoot,
      experienceBackend: backend,
    ).serve(stdin, stdout);
    return const CliResult(exitCode: 0);
  }

  Future<CliResult> _releaseV2(ArgResults command, {required bool json}) async {
    final operation = command.command;
    final commandName = 'release ${operation?.name ?? ''}'.trim();
    try {
      switch (operation?.name) {
        case 'bundle':
          final built = const DeterministicEvidenceBundleRepository().build(
            releaseDirectory: _absoluteWorkspacePath(
              operation!.option('directory')!,
            ),
            outputPath: _absoluteWorkspacePath(operation.option('output')!),
          );
          return _success(
            command: commandName,
            result: <String, Object?>{
              'path': built.path,
              'archiveDigest': built.archiveDigest.value,
              'manifestDigest': built.manifest.digest.value,
              'releaseDigest': built.manifest.releaseDigest.value,
              'attested': built.manifest.attested,
              'size': built.size,
            },
            human: 'Built ${built.path} (${built.archiveDigest.value})',
            json: json,
          );
        case 'verify-bundle':
          final verified = const DeterministicEvidenceBundleRepository().verify(
            _absoluteWorkspacePath(operation!.option('bundle')!),
          );
          return _success(
            command: commandName,
            result: <String, Object?>{
              'path': verified.path,
              'archiveDigest': verified.archiveDigest.value,
              'manifest': verified.manifest.toJson(),
              'size': verified.size,
            },
            human: 'Verified ${verified.archiveDigest.value} offline',
            json: json,
          );
        case 'seal':
          final verified = const DeterministicEvidenceBundleRepository().verify(
            _absoluteWorkspacePath(operation!.option('bundle')!),
          );
          final impact = ImpactPlan.fromJson(
            _readJsonDocument(operation.option('impact-plan')!),
          );
          final snapshotPaths = operation.multiOption('snapshot');
          if (snapshotPaths.isEmpty) {
            throw const FormatException(
              'release seal requires at least one --snapshot',
            );
          }
          final snapshots = <SourceSnapshot>[
            for (final path in snapshotPaths)
              SourceSnapshot.fromJson(_readJsonDocument(path)),
          ];
          if (!impact.complete) {
            return _policyDenied(
              commandName,
              'Release seal refuses an incomplete source impact plan.',
              result: <String, Object?>{
                'impactPlanDigest': impact.digest.value,
              },
              json: json,
            );
          }
          if (snapshots.any(
                (snapshot) =>
                    snapshot.completeness != SnapshotCompleteness.complete,
              ) ||
              !snapshots
                  .map((snapshot) => snapshot.digest)
                  .contains(impact.currentSnapshotDigest)) {
            return _policyDenied(
              commandName,
              'Release seal requires complete snapshots including the ImpactPlan current snapshot.',
              result: <String, Object?>{
                'currentSnapshotDigest': impact.currentSnapshotDigest.value,
              },
              json: json,
            );
          }
          final seal = ReleaseSeal(
            releaseDigest: verified.manifest.releaseDigest,
            bundleArchiveDigest: verified.archiveDigest,
            impactPlanDigest: impact.digest,
            sourceSnapshotDigests: snapshots
                .map((snapshot) => snapshot.digest)
                .toList(growable: false),
            policyId: operation.option('policy')!,
          );
          final output = operation.option('output')!;
          _writeCanonicalDocument(output, seal.toJson());
          return _success(
            command: commandName,
            result: <String, Object?>{
              'seal': seal.toJson(),
              'output': _absoluteWorkspacePath(output),
              'attestation': 'absent',
            },
            human:
                'Sealed Release ${seal.releaseDigest.value} by integrity policy; no attestation or approval was created',
            json: json,
          );
        default:
          throw const FormatException(
            'Usage: workspace release <build|bundle|verify-bundle|seal> [options]',
          );
      }
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    }
  }

  Future<CliResult> _probe(ArgResults command, {required bool json}) async {
    final operation = command.command;
    const commandName = 'probe run';
    if (operation?.name != 'run') {
      return _failure(
        'probe',
        'Usage: workspace probe run --plan <json> --gateway-plan <json> --origin <loopback-origin>',
        json: json,
      );
    }
    HttpContractProbeTransport? transport;
    try {
      final probePlan = ContractProbePlan.fromJson(
        _readJsonFile(operation!.option('plan')!, 'ContractProbePlan'),
      );
      final gatewayPlan = CompiledGatewayPlan.fromJson(
        _readJsonFile(operation.option('gateway-plan')!, 'CompiledGatewayPlan'),
      );
      transport = HttpContractProbeTransport(
        origin: Uri.parse(operation.option('origin')!),
      );
      final report =
          await ContractProbeExecutor(
            store: probePlan.artifactRetention == ProbeArtifactRetention.cas
                ? FileSystemWorkspaceStore(workspaceRoot: workspaceDirectory)
                : null,
          ).execute(
            plan: probePlan,
            gatewayPlan: gatewayPlan,
            transport: transport,
            manualParameters: _keyValueOptions(
              operation.multiOption('parameter'),
              'parameter',
            ),
            stableParameters: _keyValueOptions(
              operation.multiOption('stable-parameter'),
              'stable-parameter',
            ),
          );
      if (!report.success) {
        final failure = PlatformFailure(
          code: 'PROBE_FAILED',
          category: FailureCategory.consumerFailure,
          message: 'Contract probe stopped after a non-success response.',
          recoverability: Recoverability.userAction,
        );
        if (!json) {
          return CliResult(exitCode: 5, stderr: '${failure.message}\n');
        }
        final output = MachineOutput(
          command: commandName,
          ok: false,
          correlationId: null,
          effectiveContext: <String, Object?>{
            'presetId': report.presetId.value,
          },
          result: report.toJson(),
          failures: <PlatformFailure>[failure],
          diagnostics: const <MachineDiagnostic>[],
        );
        return CliResult(
          exitCode: 5,
          stderr: '${jsonEncode(output.toJson())}\n',
        );
      }
      return _success(
        command: commandName,
        result: report.toJson(),
        human: 'Contract probe passed ${report.executions.length} step(s)',
        json: json,
        effectiveContext: <String, Object?>{
          'presetId': report.presetId.value,
          'artifactRetention': probePlan.artifactRetention.name,
        },
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    } on SocketException catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    } on TimeoutException {
      return _preconditionFailure(
        commandName,
        'Contract probe timed out',
        json: json,
      );
    } finally {
      transport?.close();
    }
  }

  Future<CliResult> _retention(ArgResults command, {required bool json}) async {
    final operation = command.command;
    if (operation == null ||
        !const <String>{'status', 'gc'}.contains(operation.name)) {
      return _failure(
        'retention',
        'Usage: workspace retention <status|gc>',
        json: json,
      );
    }
    final commandName = 'retention ${operation.name}';
    try {
      final apply = operation.name == 'gc' && _mutationMode(operation);
      final report = LocalRetentionService(
        workspaceRoot: workspaceDirectory,
      ).run(apply: apply);
      return _success(
        command: commandName,
        result: report.toJson(),
        human:
            'Retention ${report.mode}: ${report.deletedBlobs} blob(s), ${report.deletedTemporaryFiles} temporary file(s)',
        json: json,
        effectiveContext: <String, Object?>{'quotaBytes': report.quotaBytes},
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    }
  }

  Object? _readJsonFile(String path, String label) {
    final file = File(
      p.isAbsolute(path) ? path : p.join(workspaceDirectory, path),
    );
    if (!file.existsSync() || Link(file.path).existsSync()) {
      throw FileSystemException(
        '$label file is absent or a symlink',
        file.path,
      );
    }
    final length = file.lengthSync();
    if (length < 1 || length > 16 * 1024 * 1024) {
      throw FormatException('$label file exceeds the 16 MiB limit');
    }
    return jsonDecode(file.readAsStringSync());
  }

  Future<CliResult> _target(ArgResults command, {required bool json}) async {
    final family = command.command;
    final operation = family?.command;
    if (family?.name != 'android' || operation == null) {
      return _failure(
        'target',
        'Usage: workspace target android <discover|bootstrap|update|remove|verify|install|launch|reset|capture>',
        json: json,
      );
    }
    final commandName = 'target android ${operation.name}';
    try {
      final sdkRoot =
          operation.option('sdk-root') ??
          Platform.environment['ANDROID_SDK_ROOT'] ??
          Platform.environment['ANDROID_HOME'];
      if (sdkRoot == null || sdkRoot.isEmpty) {
        throw const FormatException(
          '--sdk-root or ANDROID_SDK_ROOT is required',
        );
      }
      final provider = AndroidTargetProvider(sdkRoot: sdkRoot);
      final managed = AndroidManagedEmulatorService(
        workspaceRoot: workspaceDirectory,
        provider: provider,
      );
      final service = AndroidBootstrapService(
        workspaceRoot: workspaceDirectory,
        provider: provider,
        managedTargetResolver: managed.ownedTarget,
      );
      final tls = WorkspaceTlsService(
        workspaceRoot: workspaceDirectory,
        provider: provider,
      );
      final serial = operation.option('serial');
      Future<AndroidTargetDescriptor> inspectTarget(String value) async {
        final owned = await managed.ownedTarget();
        return provider.inspect(
          value,
          ownership: owned?.serial == value
              ? AndroidTargetOwnership.managed
              : AndroidTargetOwnership.attached,
        );
      }

      switch (operation.name) {
        case 'discover':
          final owned = await managed.ownedTarget();
          final targets = await provider.discover(
            managedSerials: <String>{if (owned != null) owned.serial},
          );
          return _success(
            command: commandName,
            result: <String, Object?>{
              'targets': <Object?>[
                for (final target in targets) target.toJson(),
              ],
            },
            human: '${targets.length} Android emulator target(s)',
            json: json,
            effectiveContext: <String, Object?>{'sdkRoot': sdkRoot},
          );
        case 'start':
          final report = await managed.start(
            avdName: operation.option('avd')!,
            port: _boundedInteger(
              operation.option('port')!,
              'port',
              minimum: 5554,
              maximum: 5682,
            ),
            apply: _mutationMode(operation),
            headless: operation.flag('headless'),
          );
          return _androidReport(commandName, report, json: json);
        case 'managed-status':
          final report = await managed.status();
          if (!report.verified) {
            return _preconditionFailure(
              commandName,
              'Managed Android emulator ownership is not healthy',
              json: json,
            );
          }
          return _androidReport(commandName, report, json: json);
        case 'stop':
          if (_mutationMode(operation)) {
            await tls.remove(apply: true);
          }
          return _androidReport(
            commandName,
            await managed.stop(apply: _mutationMode(operation)),
            json: json,
          );
        case 'tls-install':
          final owned = await managed.status();
          if (!owned.verified || owned.target == null) {
            throw StateError('No healthy managed Android emulator is owned');
          }
          return _androidReport(
            commandName,
            await tls.install(
              target: owned.target!,
              apply: _mutationMode(operation),
            ),
            json: json,
          );
        case 'tls-verify':
          final report = await tls.verify();
          if (!report.verified) {
            return _preconditionFailure(
              commandName,
              'Workspace TLS trust verification failed',
              json: json,
            );
          }
          return _androidReport(commandName, report, json: json);
        case 'tls-remove':
          return _androidReport(
            commandName,
            await tls.remove(apply: _mutationMode(operation)),
            json: json,
          );
        case 'bootstrap' || 'update':
          final apply = _mutationMode(operation);
          final pairing = _androidPairing(operation);
          final report = operation.name == 'bootstrap'
              ? await service.bootstrap(
                  serial: serial!,
                  pairing: pairing,
                  apply: apply,
                )
              : await service.update(
                  serial: serial!,
                  pairing: pairing,
                  apply: apply,
                );
          return _androidReport(commandName, report, json: json);
        case 'remove':
          final report = await service.remove(apply: _mutationMode(operation));
          return _androidReport(commandName, report, json: json);
        case 'verify':
          final report = await service.verify();
          if (!report.verified) {
            return _preconditionFailure(
              commandName,
              'Android bootstrap verification failed',
              json: json,
            );
          }
          return _androidReport(commandName, report, json: json);
        case 'install':
          await provider.installApk(serial!, operation.option('apk')!);
          final target = await inspectTarget(serial);
          return _androidReport(
            commandName,
            AndroidLifecycleReport(
              operation: AndroidLifecycleOperation.install,
              mode: AndroidLifecycleMode.apply,
              changed: true,
              verified: true,
              actions: const <String>['install or replace exact APK'],
              target: target,
            ),
            json: json,
          );
        case 'launch':
          final target = await inspectTarget(serial!);
          final request = AndroidLaunchRequest(
            packageName: operation.option('package')!,
            activity: operation.option('activity')!,
            pairing: _androidPairing(operation),
            overlay: RuntimeConfigurationOverlay(
              _keyValueOptions(operation.multiOption('overlay'), 'overlay'),
            ),
          );
          await provider.launch(serial, request);
          return _androidReport(
            commandName,
            AndroidLifecycleReport(
              operation: AndroidLifecycleOperation.launch,
              mode: AndroidLifecycleMode.apply,
              changed: true,
              verified: true,
              actions: const <String>['launch activity with ephemeral overlay'],
              target: target,
              pairing: request.pairing,
            ),
            json: json,
          );
        case 'reset':
          await provider.resetPackage(serial!, operation.option('package')!);
          final target = await inspectTarget(serial);
          return _androidReport(
            commandName,
            AndroidLifecycleReport(
              operation: AndroidLifecycleOperation.reset,
              mode: AndroidLifecycleMode.apply,
              changed: true,
              verified: true,
              actions: const <String>['clear exact package data'],
              target: target,
            ),
            json: json,
          );
        case 'capture':
          final bytes = await provider.capturePng(serial!);
          final store = FileSystemWorkspaceStore(
            workspaceRoot: workspaceDirectory,
          );
          late final Digest digest;
          store.withExclusiveLock(() {
            digest = store.putBlob(bytes);
            store.rebuildCasIndex();
          });
          final target = await inspectTarget(serial);
          return _androidReport(
            commandName,
            AndroidLifecycleReport(
              operation: AndroidLifecycleOperation.capture,
              mode: AndroidLifecycleMode.apply,
              changed: true,
              verified: true,
              actions: const <String>['capture lossless PNG into local CAS'],
              target: target,
              artifactDigest: digest,
            ),
            json: json,
          );
        case 'evidence':
          final target = await inspectTarget(serial!);
          final containment = TargetContainmentReport.fromJson(
            _readJsonDocument(operation.option('containment-report')!),
          );
          final rawInputs = _keyValueOptions(
            operation.multiOption('input-digest'),
            'input-digest',
          );
          final store = FileSystemWorkspaceStore(
            workspaceRoot: _absoluteWorkspacePath(
              operation.option('evidence-workspace')!,
            ),
          );
          final collected =
              await AndroidEvidenceProvider(
                provider: provider,
                store: store,
              ).collect(
                target: target,
                catalogDigest: Digest(operation.option('catalog-digest')!),
                launchProfileId: operation.option('launch-profile')!,
                packageName: operation.option('package')!,
                containment: containment,
                selection: AndroidEvidenceSelection(
                  screenshot: operation.flag('screenshot'),
                  semantics: operation.flag('semantics'),
                  logcat: operation.flag('logcat'),
                  screenRecording: operation.flag('screen-recording'),
                  performanceTrace: operation.flag('performance-trace'),
                  syntheticDataConfirmed: operation.flag(
                    'synthetic-data-confirmed',
                  ),
                  duration: Duration(
                    seconds: _boundedInteger(
                      operation.option('duration-seconds')!,
                      'duration-seconds',
                      minimum: 1,
                      maximum: 30,
                    ),
                  ),
                ),
                inputDigests: <String, Digest>{
                  for (final entry in rawInputs.entries)
                    entry.key: Digest(entry.value),
                },
                sourceRevision: operation.option('source-revision'),
                backendMode: BackendMode.values.byName(
                  operation.option('backend-mode')!,
                ),
              );
          LocalEvidenceRepository(
            store: store,
          ).persistEvidence(collected.evidence);
          final output = operation.option('output');
          if (output != null) {
            _writeCanonicalDocument(output, collected.manifest.toJson());
          }
          return _success(
            command: commandName,
            result: <String, Object?>{
              'evidence': collected.evidence.toJson(),
              'androidManifest': collected.manifest.toJson(),
              if (output != null) 'output': _absoluteWorkspacePath(output),
            },
            human:
                'Android Evidence ${collected.evidence.digest.value} collected',
            json: json,
            effectiveContext: <String, Object?>{
              'target': target.serial,
              'evidenceWorkspace': store.workspaceRoot,
              'runtimeFidelity': RuntimeFidelity.hostNative.name,
              'containment': containment.networkContainment.name,
            },
          );
        default:
          throw const FormatException('Unsupported Android target operation');
      }
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on ProcessException catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    } on TimeoutException {
      return _preconditionFailure(
        commandName,
        'Android operation timed out',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    }
  }

  CliResult _androidReport(
    String command,
    AndroidLifecycleReport report, {
    required bool json,
  }) => _success(
    command: command,
    result: report.toJson(),
    human:
        '${report.operation.name}: ${report.verified ? 'verified' : 'planned'}',
    json: json,
    effectiveContext: <String, Object?>{
      if (report.target != null) 'target': report.target!.serial,
      if (report.pairing != null)
        'gatewayOrigin': report.pairing!.targetOrigin.toString(),
    },
  );

  bool _mutationMode(ArgResults operation) {
    if (operation.flag('apply') && operation.flag('dry-run')) {
      throw const FormatException('Use either --apply or --dry-run');
    }
    return operation.flag('apply');
  }

  AndroidGatewayPairing _androidPairing(ArgResults operation) =>
      AndroidGatewayPairing(
        strategy: AndroidGatewayRouteStrategy.values.byName(
          operation.option('strategy')!,
        ),
        hostPort: _boundedInteger(
          operation.option('host-port')!,
          'host-port',
          minimum: 1,
          maximum: 65535,
        ),
        targetPort: _boundedInteger(
          operation.option('target-port')!,
          'target-port',
          minimum: 1,
          maximum: 65535,
        ),
        tls: operation.flag('tls'),
      );

  Map<String, String> _keyValueOptions(List<String> values, String field) {
    final result = <String, String>{};
    for (final value in values) {
      final separator = value.indexOf('=');
      if (separator < 1 || separator == value.length - 1) {
        throw FormatException('--$field must use KEY=value');
      }
      final key = value.substring(0, separator);
      if (result.containsKey(key)) {
        throw FormatException('Duplicate --$field key $key');
      }
      result[key] = value.substring(separator + 1);
    }
    return result;
  }

  Future<CliResult> _distribution(
    ArgResults command, {
    required bool json,
  }) async {
    final operation = command.command;
    if (operation == null) {
      return _failure(
        'distribution',
        'Usage: workspace distribution <compose-consumer|install|status|rollback|verify-bundle>',
        json: json,
      );
    }
    final commandName = 'distribution ${operation.name}';
    try {
      if (operation.name == 'verify-bundle') {
        final manifest = await const LocalDistributionBundleRepository().verify(
          operation.option('bundle')!,
        );
        return _success(
          command: commandName,
          result: <String, Object?>{
            'releaseVersion': manifest.releaseVersion,
            'manifestDigest': manifest.digest.value,
            'files': manifest.files.length,
          },
          human: 'Distribution ${manifest.releaseVersion} verified',
          json: json,
        );
      }
      if (operation.name == 'compose-consumer') {
        final specificationFile = File(
          operation.option('specification')!,
        ).absolute;
        if (Link(specificationFile.path).existsSync() ||
            !specificationFile.existsSync() ||
            specificationFile.lengthSync() <= 0 ||
            specificationFile.lengthSync() > 1024 * 1024) {
          throw FileSystemException(
            'Consumer distribution specification is missing or unsafe',
            specificationFile.path,
          );
        }
        final specification = ConsumerDistributionSpec.fromJson(
          jsonDecode(specificationFile.readAsStringSync()),
        );
        final result = await const LocalConsumerDistributionComposer().compose(
          baseBundleDirectory: operation.option('base-bundle')!,
          consumerWorkspaceDirectory: operation.option('workspace')!,
          specification: specification,
          outputDirectory: operation.option('output')!,
          configurationSchemas:
              const BuiltinModuleCatalog().configurationSchemas,
        );
        return _success(
          command: commandName,
          result: result.toJson(),
          human:
              'Consumer distribution ${result.release.releaseVersion} composed',
          json: json,
        );
      }
      final manager = LocalDistributionManager(
        installRoot: operation.option('install-root')!,
      );
      final Object result;
      switch (operation.name) {
        case 'install':
          result = (await manager.install(
            operation.option('bundle')!,
          )).toJson();
        case 'status':
          result = (await manager.status()).toJson();
        case 'rollback':
          result = (await manager.rollback()).toJson();
        default:
          throw const FormatException('Unsupported distribution command');
      }
      return _success(
        command: commandName,
        result: result,
        human: 'Distribution operation complete',
        json: json,
        effectiveContext: <String, Object?>{'installRoot': manager.installRoot},
      );
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    }
  }

  Future<CliResult> _evidence(ArgResults command, {required bool json}) async {
    final operation = command.command;
    if (operation == null ||
        !const <String>{
          'collect-tests',
          'collect-previews',
          'compare-visual',
          'compare-semantics',
          'import-artifact',
          'export-artifact',
        }.contains(operation.name)) {
      return _failure(
        'evidence',
        'Usage: workspace evidence <collect-previews|collect-tests|compare-visual|compare-semantics|import-artifact|export-artifact>',
        json: json,
      );
    }
    final commandName = 'evidence ${operation.name}';
    try {
      if (operation.name == 'collect-previews') {
        return await _collectPreviewEvidence(
          operation,
          commandName: commandName,
          json: json,
        );
      }
      if (operation.name == 'import-artifact') {
        final loaded = const CliKitPlanLoader().load(
          workspaceDirectory: workspaceDirectory,
          explicitConfigPath: operation.option('config'),
          profileOverride: operation.option('profile'),
          allowMissingWorkspace: true,
        );
        if (!loaded.plan.enabledModules.any(
          (module) => module.moduleId.value == 'artifact-store.local',
        )) {
          throw StateError('artifact-store.local is not enabled');
        }
        final workspaceRoot =
            loaded.configuration?.workspaceRoot ?? workspaceDirectory;
        final input = _readSupplementalArtifactInput(
          operation.option('input')!,
          workspaceRoot: workspaceRoot,
          inputBase: workspaceDirectory,
        );
        final mediaType = ScenarioLabSupplementalArtifactMediaType.fromValue(
          operation.option('media-type')!,
        );
        _validateSupplementalArtifactMedia(mediaType, input.bytes);
        final classification = ArtifactClassification.values.byName(
          operation.option('classification')!,
        );
        final provenance = ScenarioLabSupplementalArtifactProvenance(
          artifactDigest: Digest.bytes(input.bytes),
          size: input.bytes.length,
          mediaType: mediaType,
          classification: classification,
          sourceId: ScenarioLabSupplementalArtifactSourceId(
            operation.option('source-id')!,
          ),
          importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
            operation.option('import-policy')!,
          ),
        );
        final store = FileSystemWorkspaceStore(
          workspaceRoot: input.workspaceRoot,
        );
        late final Digest artifactDigest;
        late final Digest provenanceDigest;
        store.withExclusiveLock(() {
          artifactDigest = store.putBlob(input.bytes);
          if (artifactDigest != provenance.artifactDigest) {
            throw StateError(
              'Stored supplemental artifact digest does not match its bytes',
            );
          }
          provenanceDigest = store.putBlob(provenance.canonicalBytes);
          if (provenanceDigest != provenance.digest) {
            throw StateError(
              'Stored supplemental artifact provenance digest does not match its canonical bytes',
            );
          }
          store.rebuildCasIndex();
          _commitSupplementalArtifactImportRoot(
            store,
            artifactDigest: artifactDigest,
            provenanceDigest: provenanceDigest,
          );
        });
        return _success(
          command: commandName,
          result: <String, Object?>{
            'artifactDigest': artifactDigest.value,
            'provenanceDigest': provenanceDigest.value,
            'size': provenance.size,
            'mediaType': provenance.mediaType.value,
            'classification': provenance.classification.name,
            'sourceId': provenance.sourceId.value,
            'importPolicyId': provenance.importPolicyId.value,
          },
          human:
              'Imported artifact ${artifactDigest.value}; '
              'provenance ${provenanceDigest.value}',
          json: json,
        );
      }
      if (operation.name == 'export-artifact') {
        final digest = Digest(operation.option('digest')!);
        final bytes = FileSystemWorkspaceStore(
          workspaceRoot: workspaceDirectory,
        ).readBlob(digest);
        if (bytes == null) {
          throw StateError(
            'Evidence artifact is absent from the workspace CAS',
          );
        }
        final output = operation.option('output')!;
        _writeExactBytes(output, bytes);
        return _success(
          command: commandName,
          result: <String, Object?>{
            'artifactDigest': digest.value,
            'size': bytes.length,
            'output': _absoluteWorkspacePath(output),
          },
          human: 'Exported ${digest.value}',
          json: json,
        );
      }
      if (operation.name == 'compare-visual' ||
          operation.name == 'compare-semantics') {
        List<int> boundedBytes(String path, int maximum) {
          final file = File(_absoluteWorkspacePath(path));
          if (!file.existsSync() || Link(file.path).existsSync()) {
            throw FileSystemException(
              'Evidence comparison input is absent or linked',
              file.path,
            );
          }
          final length = file.lengthSync();
          if (length < 1 || length > maximum) {
            throw FormatException(
              'Evidence comparison input has an invalid size: ${file.path}',
            );
          }
          return file.readAsBytesSync();
        }

        final visual = operation.name == 'compare-visual';
        final expected = boundedBytes(
          operation.option('expected')!,
          visual ? 64 * 1024 * 1024 : 16 * 1024 * 1024,
        );
        final actual = boundedBytes(
          operation.option('actual')!,
          visual ? 64 * 1024 * 1024 : 16 * 1024 * 1024,
        );
        final service = const EvidenceComparisonService();
        final report = visual
            ? service.compareVisual(
                expected: expected,
                actual: actual,
                policy: VisualComparisonPolicy.fromJson(
                  _readJsonDocument(operation.option('policy')!),
                ),
              )
            : service.compareSemantic(
                expected: expected,
                actual: actual,
                policy: SemanticComparisonPolicy.fromJson(
                  _readJsonDocument(operation.option('policy')!),
                ),
              );
        final output = operation.option('output');
        if (output != null) _writeCanonicalDocument(output, report.toJson());
        final result = <String, Object?>{
          'report': report.toJson(),
          if (output != null) 'output': _absoluteWorkspacePath(output),
        };
        if (!report.passed) {
          return _policyDenied(
            commandName,
            'Evidence comparison exceeded its versioned policy.',
            result: result,
            json: json,
          );
        }
        return _success(
          command: commandName,
          result: result,
          human: 'Evidence comparison ${report.digest.value} passed',
          json: json,
        );
      }

      final targets = operation.multiOption('target');
      if (targets.isEmpty) {
        throw const FormatException('At least one --target is required');
      }
      final seconds = _boundedInteger(
        operation.option('timeout-seconds')!,
        'timeout-seconds',
        minimum: 1,
        maximum: 1800,
      );
      final summary =
          await DartTestEvidenceProvider(
            workspaceRoot: workspaceDirectory,
          ).collect(
            runner: DartTestRunner.values.byName(operation.option('runner')!),
            targets: targets,
            timeout: Duration(seconds: seconds),
          );
      if (summary.success) {
        return _success(
          command: commandName,
          result: summary.toJson(),
          human: 'Test evidence collected: ${summary.passed} passed',
          json: json,
          effectiveContext: <String, Object?>{
            'workspaceRoot': workspaceDirectory,
            'providerId': DartTestEvidenceProvider.providerId,
          },
        );
      }
      final failure = PlatformFailure(
        code: 'TESTS_FAILED',
        category: FailureCategory.consumerFailure,
        message: '${summary.failed} test result(s) failed.',
        recoverability: Recoverability.userAction,
      );
      if (!json) {
        return CliResult(exitCode: 5, stderr: '${failure.message}\n');
      }
      final output = MachineOutput(
        command: commandName,
        ok: false,
        correlationId: null,
        effectiveContext: <String, Object?>{
          'workspaceRoot': workspaceDirectory,
          'providerId': DartTestEvidenceProvider.providerId,
        },
        result: summary.toJson(),
        failures: <PlatformFailure>[failure],
        diagnostics: const <MachineDiagnostic>[],
      );
      return CliResult(exitCode: 5, stderr: '${jsonEncode(output.toJson())}\n');
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on PreviewSourceScanException catch (error) {
      return _failure(commandName, error.issues.join('; '), json: json);
    } on PreviewCompileException catch (error) {
      return _failure(commandName, error.issues.join('; '), json: json);
    } on KitPlanResolutionException catch (error) {
      return _failure(commandName, error.issues.join('; '), json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(commandName, error.message, json: json);
    }
  }

  CliResult _adoption(ArgResults command, {required bool json}) {
    final name = command.name!;
    try {
      final apply = name == 'adoption-report' ? false : command.flag('apply');
      final dryRun = name == 'adoption-report'
          ? false
          : command.flag('dry-run');
      if (apply && dryRun) {
        throw const FormatException('Use either --apply or --dry-run');
      }
      final service = LocalAdoptionService(
        workspaceRoot: workspaceDirectory,
        distributionId: command.option('distribution')!,
      );
      final AdoptionReport report;
      switch (name) {
        case 'init':
          report = apply
              ? service.applyInit(
                  workspaceId: command.option('workspace-id')!,
                  displayName: command.option('display-name')!,
                  applicationId: command.option('application-id')!,
                )
              : service.planInit(
                  workspaceId: command.option('workspace-id')!,
                  displayName: command.option('display-name')!,
                  applicationId: command.option('application-id')!,
                );
        case 'adoption-report':
          report = service.report();
        case 'detach':
          report = service.detach(apply: apply);
        default:
          throw StateError('Unsupported adoption command');
      }
      return _success(
        command: name,
        result: <String, Object?>{
          'mode': apply ? 'apply' : 'dryRun',
          'report': report.toJson(),
        },
        human: switch (name) {
          'init' when apply => 'Abel adoption applied',
          'init' => 'Abel adoption preview ready',
          'detach' when apply && !report.adopted => 'Abel detached',
          'detach' when apply => 'Abel partially detached',
          'detach' => 'Abel detach preview ready',
          _ =>
            report.adopted
                ? 'Abel adoption is active'
                : 'Abel adoption is not active',
        },
        json: json,
        effectiveContext: <String, Object?>{
          'workspaceRoot': service.workspaceRoot,
          'distributionId': service.distributionId,
        },
      );
    } on FormatException catch (error) {
      return _failure(name, error.message, json: json);
    } on ArgumentError catch (error) {
      return _failure(name, '${error.message}', json: json);
    } on FileSystemException catch (error) {
      return _failure(
        name,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on StateError catch (error) {
      return _preconditionFailure(name, error.message, json: json);
    }
  }

  Future<CliResult> _runCatalogCommand(
    ArgResults command, {
    required bool json,
  }) async {
    final effectiveCommand = command.name == 'release'
        ? command.command
        : command;
    if (effectiveCommand == null ||
        (command.name == 'release' && effectiveCommand.name != 'build')) {
      throw const FormatException('Usage: workspace release build [options]');
    }
    final loaded = const WorkspaceCatalogLoader().load(
      startPath: workspaceDirectory,
      explicitConfigPath: effectiveCommand.option('config'),
    );
    final manifest = const CatalogCompiler().compile(
      loaded.documents,
      layout: loaded.layout,
    );
    final gatewayPlans = const WorkspaceGatewayPlanCompiler().compileAll(
      loaded,
      persist: command.name == 'compile',
    );
    final context = <String, Object?>{
      'workspaceRoot': loaded.workspaceRoot,
      'configPath': loaded.configPath,
      'contentRoot': loaded.contentRoot,
      'distributionId': manifest.distribution.id,
      'gatewayPresets': gatewayPlans.length,
    };
    const diagnostics = <MachineDiagnostic>[];
    switch (command.name) {
      case 'validate':
        return _success(
          command: 'validate',
          result: <String, Object?>{
            ..._catalogSummary(manifest),
            'gatewayPresets': gatewayPlans.length,
          },
          human: 'Valid catalog ${manifest.digest}',
          json: json,
          effectiveContext: context,
          diagnostics: diagnostics,
        );
      case 'explain':
        return _success(
          command: 'explain',
          result: <String, Object?>{
            ..._catalogSummary(manifest),
            'gatewayPresets': gatewayPlans.length,
            'layout': loaded.layout.toJson(),
          },
          human:
              'Config: ${loaded.configPath}\nContent: ${loaded.contentRoot}\nDigest: ${manifest.digest}',
          json: json,
          effectiveContext: context,
          diagnostics: diagnostics,
        );
      case 'compile':
        final store = FileSystemWorkspaceStore(
          workspaceRoot: loaded.workspaceRoot,
        );
        late final Digest artifactDigest;
        store.withExclusiveLock(() {
          store.writeManifest(manifest);
          artifactDigest = store.putBlob(
            utf8.encode(
              const JcsCanonicalizer().canonicalize(manifest.toJson()),
            ),
          );
          store.rebuildCasIndex();
        });
        return _success(
          command: 'compile',
          result: <String, Object?>{
            ..._catalogSummary(manifest),
            'artifactDigest': artifactDigest.value,
            'manifestPath': '${store.stateRoot}/catalog/manifest.json',
            'gatewayPlans': <Object?>[
              for (final gateway in gatewayPlans)
                <String, Object?>{
                  'presetId': gateway.compilation.plan.preset.id.value,
                  'planDigest': gateway.compilation.plan.digest.value,
                  'artifactDigest': gateway.planArtifactDigest!.value,
                },
            ],
          },
          human: 'Compiled ${manifest.digest}',
          json: json,
          effectiveContext: context,
          diagnostics: diagnostics,
        );
      case 'dev':
        final loadedPlan = const CliKitPlanLoader().load(
          workspaceDirectory: workspaceDirectory,
          explicitConfigPath: effectiveCommand.option('config'),
          profileOverride: effectiveCommand.option('profile'),
        );
        if (effectiveCommand.flag('plan-only')) {
          final runId =
              'run-$pid-${DateTime.now().toUtc().microsecondsSinceEpoch}';
          final planPath = const ResolvedKitPlanFile().write(
            workspaceRoot: loaded.workspaceRoot,
            runId: runId,
            plan: loadedPlan.plan,
          );
          return _success(
            command: 'dev',
            result: <String, Object?>{
              ..._catalogSummary(manifest),
              'status': 'planned',
              'profileId': loadedPlan.plan.profileId,
              'planDigest': loadedPlan.plan.digest.value,
              'host': <String, Object?>{
                'workspaceRoot': loaded.workspaceRoot,
                'environment': <String, String>{
                  'RESOLVED_COMPOSITION_PLAN': planPath,
                  'RESOLVED_COMPOSITION_PLAN_DIGEST':
                      loadedPlan.plan.digest.value,
                },
              },
            },
            human:
                'Development plan ready for ${manifest.workspace.displayName}',
            json: json,
            effectiveContext: context,
            diagnostics: diagnostics,
          );
        }
        if (_developmentRuns.isNotEmpty) {
          throw StateError(
            'This CLI instance already supervises workspace dev',
          );
        }
        final studioEnabled = loadedPlan.plan.enabledModules.any(
          (module) => module.moduleId.value == 'studio.shell',
        );
        final studioDevelopmentOrigin = _studioDevelopmentOrigin(
          effectiveCommand.option('studio-dev-origin'),
        );
        if (!studioEnabled && studioDevelopmentOrigin != null) {
          throw const FormatException(
            '--studio-dev-origin requires the studio.shell module',
          );
        }
        if (studioDevelopmentOrigin != null &&
            effectiveCommand.option('studio-assets') != null) {
          throw const FormatException(
            '--studio-dev-origin cannot be combined with --studio-assets',
          );
        }
        final studioAssets = studioEnabled && studioDevelopmentOrigin == null
            ? await _resolveStudioAssets(
                effectiveCommand.option('studio-assets'),
              )
            : null;
        final gateway = await _gatewaySidecar(loadedPlan.plan);
        final supervisor = DevelopmentSupervisor(
          workspaceRoot: loaded.workspaceRoot,
          catalog: loadedPlan.catalog,
          plan: loadedPlan.plan,
          studioAssetRoot: studioAssets,
          studioDevelopmentOrigin: studioDevelopmentOrigin,
          hostPort: _port(effectiveCommand.option('host-port')!, 'host-port'),
          studioPort: _port(
            effectiveCommand.option('studio-port')!,
            'studio-port',
          ),
          headlessStudioOrigin: studioEnabled
              ? null
              : Uri.parse(effectiveCommand.option('headless-studio-origin')!),
          gatewaySidecarCommand: gateway?.command,
          gatewaySidecarArguments: gateway?.arguments ?? const <String>[],
          gatewaySidecarWorkingDirectory: gateway?.workingDirectory,
          launchProfiles:
              loadedPlan.configuration?.launchProfiles ??
              const <LaunchProfile>[],
        );
        final runtime = await supervisor.start();
        _watchDevelopment(supervisor);
        String? browserDiagnostic;
        if (runtime.studioOrigin != null && !effectiveCommand.flag('no-open')) {
          browserDiagnostic = await _openBrowser(runtime.studioOrigin!);
        }
        return _success(
          command: 'dev',
          result: <String, Object?>{
            ..._catalogSummary(manifest),
            'status': 'ready',
            ...runtime.toJson(),
            'browserDiagnostic': ?browserDiagnostic,
          },
          human: runtime.studioOrigin == null
              ? 'Workspace Host ready at ${runtime.hostOrigin}'
              : 'Abel Studio ready at ${runtime.studioOrigin}',
          json: json,
          effectiveContext: context,
          diagnostics: diagnostics,
        );
      case 'capture':
        final input = effectiveCommand.option('input');
        if (input == null || input.isEmpty) {
          throw const FormatException('--input is required for capture');
        }
        final inputFile = File(
          p.isAbsolute(input) ? input : p.join(workspaceDirectory, input),
        );
        if (!inputFile.existsSync()) {
          throw FileSystemException('Capture input not found', inputFile.path);
        }
        final fidelityName = effectiveCommand.option('fidelity')!;
        final classificationName = effectiveCommand.option('classification')!;
        final sourceSnapshotPath = effectiveCommand.option('source-snapshot');
        final sourceSnapshot = sourceSnapshotPath == null
            ? null
            : SourceSnapshot.fromJson(_readJsonDocument(sourceSnapshotPath));
        final fingerprint = ExecutionFingerprint(
          catalogDigest: manifest.digest,
          launchProfileId: effectiveCommand.option('launch-profile')!,
          targetId: effectiveCommand.option('target')!,
          platform: effectiveCommand.option('platform')!,
          renderer: effectiveCommand.option('renderer')!,
          runtimeFidelity: RuntimeFidelity.values.singleWhere(
            (value) => value.name == fidelityName,
          ),
          backendMode: BackendMode.none,
          networkContainment: NetworkContainment.unconstrained,
          bootstrapAssessment: BootstrapAssessment.unassessed,
          toolchain: <String, String>{
            'dart': Platform.version.split(' ').first,
            'workspace': version,
          },
          capabilities: const <String>{'capture.png'},
          inputDigests: <String, Digest>{
            'catalog': manifest.digest,
            if (sourceSnapshot != null)
              'source.${sourceSnapshot.repository.id}': sourceSnapshot.digest,
          },
          policies: const <String, String>{'evidence': 'local-v1'},
          sourceRevision: sourceSnapshot?.revision,
        );
        final store = FileSystemWorkspaceStore(
          workspaceRoot: loaded.workspaceRoot,
        );
        final evidence = LocalEvidenceRepository(store: store).capturePng(
          bytes: inputFile.readAsBytesSync(),
          fingerprint: fingerprint,
          classification: ArtifactClassification.values.singleWhere(
            (value) => value.name == classificationName,
          ),
        );
        final artifact = evidence.artifacts.single;
        return _success(
          command: 'capture',
          result: <String, Object?>{
            'evidenceDigest': evidence.digest.value,
            'subjectDigest': evidence.subjectDigest.value,
            'fingerprintDigest': evidence.fingerprint.digest.value,
            'artifact': artifact.toJson(),
            'freshness': EvidenceFreshness.fresh.name,
            'reproductionClaimComplete': fingerprint.hasReproductionClaim,
          },
          human: 'Captured ${artifact.digest.value}',
          json: json,
          effectiveContext: context,
          diagnostics: <MachineDiagnostic>[
            ...diagnostics,
            if (!fingerprint.hasReproductionClaim)
              const MachineDiagnostic(
                code: 'REPRODUCTION_CLAIM_DEGRADED',
                message:
                    'Source revision is absent; capture is evidence, not a complete reproduction claim.',
              ),
          ],
        );
      case 'release':
        final store = FileSystemWorkspaceStore(
          workspaceRoot: loaded.workspaceRoot,
        );
        final built = LocalEvidenceRepository(store: store).buildRelease(
          currentSubject: manifest.digest,
          distributionDigest: Digest.semantic(manifest.distribution.toJson()),
          coreVersion: version,
        );
        return _success(
          command: 'release build',
          result: <String, Object?>{
            'releaseId': built.release.id,
            'releaseDigest': built.release.digest.value,
            'bundleDigest': built.bundle.digest.value,
            'subjectDigest': built.release.subjectDigest.value,
            'directory': built.directory,
            'artifacts': built.bundle.artifacts.length,
          },
          human: 'Built Release ${built.release.digest.value}',
          json: json,
          effectiveContext: context,
          diagnostics: diagnostics,
        );
      default:
        throw StateError('Unsupported command ${command.name}');
    }
  }

  Future<CliResult> _doctor({required bool json}) async {
    final checks = <Map<String, Object?>>[];
    var ok = true;
    Future<void> executableCheck(
      String id,
      String executable,
      List<String> arguments,
    ) async {
      try {
        final result = await Process.run(
          executable,
          arguments,
        ).timeout(const Duration(seconds: 15));
        final passed = result.exitCode == 0;
        ok = ok && passed;
        checks.add(<String, Object?>{
          'id': id,
          'ok': passed,
          'exitCode': result.exitCode,
        });
      } on Object catch (error) {
        ok = false;
        checks.add(<String, Object?>{
          'id': id,
          'ok': false,
          'message': '$error',
        });
      }
    }

    await executableCheck('dart', Platform.resolvedExecutable, const <String>[
      '--version',
    ]);
    await executableCheck('flutter', 'flutter', const <String>[
      '--version',
      '--machine',
    ]);
    final chrome = <String>[
      'google-chrome-stable',
      'google-chrome',
      'chromium',
    ].where((candidate) => _findExecutable(candidate) != null).firstOrNull;
    checks.add(<String, Object?>{
      'id': 'chrome',
      'ok': chrome != null,
      if (chrome != null) 'executable': _findExecutable(chrome),
    });
    ok = ok && chrome != null;
    final output = MachineOutput(
      command: 'doctor',
      ok: ok,
      correlationId: null,
      effectiveContext: <String, Object?>{
        'workspaceDirectory': workspaceDirectory,
      },
      result: <String, Object?>{'checks': checks},
      failures: ok
          ? const <PlatformFailure>[]
          : const <PlatformFailure>[
              PlatformFailure(
                code: 'WORKSPACE_DOCTOR_FAILED',
                category: FailureCategory.precondition,
                message: 'One or more required toolchain checks failed.',
                recoverability: Recoverability.userAction,
              ),
            ],
      diagnostics: const <MachineDiagnostic>[],
    );
    if (json) {
      final encoded = '${jsonEncode(output.toJson())}\n';
      return CliResult(
        exitCode: ok ? 0 : 3,
        stdout: ok ? encoded : '',
        stderr: ok ? '' : encoded,
      );
    }
    return CliResult(
      exitCode: ok ? 0 : 3,
      stdout: ok ? 'Abel doctor: ready\n' : '',
      stderr: ok ? '' : 'Abel doctor: precondition failed\n',
    );
  }

  Future<CliResult> _session(ArgResults command, {required bool json}) async {
    final start = command.command;
    if (start?.name != 'start') {
      return _failure(
        'session',
        'Usage: workspace session start [options]',
        json: json,
      );
    }
    String requiredOption(String name) {
      final value = start!.option(name);
      if (value == null || value.isEmpty) {
        throw FormatException('--$name is required');
      }
      return value;
    }

    try {
      final host = Uri.parse(requiredOption('host'));
      final token = requiredOption('token');
      final studioOrigin = Uri.parse(requiredOption('studio-origin'));
      final launchProfile = requiredOption('launch-profile');
      final targetOrigin = requiredOption('target-origin');
      final connection = await _HostRpcConnection.connect(
        host: host,
        token: token,
        studioOrigin: studioOrigin,
      );
      late final Object? result;
      try {
        result = await connection.call('session.start', <String, Object?>{
          'launchProfileId': launchProfile,
          'targetOrigin': targetOrigin,
        });
      } finally {
        await connection.close();
      }
      return _success(
        command: 'session start',
        result: result,
        human: 'Session ${(result! as Map<String, Object?>)['id']} ready',
        json: json,
        effectiveContext: <String, Object?>{
          'hostOrigin': host.origin,
          'launchProfileId': launchProfile,
        },
      );
    } on FormatException catch (error) {
      return _failure('session start', error.message, json: json);
    } on SocketException catch (error) {
      return CliResult(
        exitCode: 5,
        stderr: 'Host unavailable: ${error.message}\n',
      );
    } on StateError catch (error) {
      return CliResult(exitCode: 3, stderr: '${error.message}\n');
    }
  }

  Future<CliResult> _gateway(ArgResults command, {required bool json}) async {
    final operation = command.command;
    if (operation == null) {
      return _failure(
        'gateway',
        'Usage: workspace gateway <run|status|apply-preset|verify|traffic|reset|stop|sync|doctor>',
        json: json,
      );
    }
    String requiredOption(String name) {
      final value = operation.option(name);
      if (value == null || value.isEmpty) {
        throw FormatException('--$name is required');
      }
      return value;
    }

    final commandName = 'gateway ${operation.name}';
    try {
      if (operation.name == 'sync' || operation.name == 'doctor') {
        return await _gatewayLocal(operation, json: json);
      }
      final host = Uri.parse(requiredOption('host'));
      final token = requiredOption('token');
      final studioOrigin = Uri.parse(requiredOption('studio-origin'));
      final connection = await _HostRpcConnection.connect(
        host: host,
        token: token,
        studioOrigin: studioOrigin,
      );
      try {
        final Object? result;
        switch (operation.name) {
          case 'run':
            final planDigest = _storeGatewayPlan(operation);
            result = await connection.call('gateway.start', <String, Object?>{
              'ownerSessionId': requiredOption('owner-session'),
              'planArtifactDigest': planDigest.value,
            });
          case 'status':
            result = await connection.call(
              'gateway.status',
              _gatewaySessionParams(operation),
            );
          case 'apply-preset':
            final planDigest = _storeGatewayPlan(operation);
            result = await connection.call('gateway.apply', <String, Object?>{
              ..._gatewaySessionParams(operation),
              'planArtifactDigest': planDigest.value,
            });
          case 'verify':
            final bodyPath = operation.option('body');
            final body = bodyPath == null
                ? null
                : File(_absoluteWorkspacePath(bodyPath)).readAsBytesSync();
            if (body != null && body.length > 256 * 1024) {
              throw const FormatException(
                'Gateway verify body exceeds 256 KiB',
              );
            }
            result = await connection.call('gateway.verify', <String, Object?>{
              ..._gatewaySessionParams(operation),
              'method': requiredOption('method'),
              'path': requiredOption('path'),
              'query': _queryOptions(operation.multiOption('query')),
              if (body != null) 'bodyBase64': base64Encode(body),
            });
          case 'traffic':
            result = await connection.call('gateway.traffic', <String, Object?>{
              ..._gatewaySessionParams(operation),
              'afterSequence': _boundedInteger(
                requiredOption('after-sequence'),
                'after-sequence',
                minimum: 0,
                maximum: 0x7fffffff,
              ),
              'limit': _boundedInteger(
                requiredOption('limit'),
                'limit',
                minimum: 1,
                maximum: 10000,
              ),
            });
          case 'reset':
            result = await connection.call(
              'gateway.reset',
              _gatewaySessionParams(operation),
            );
          case 'stop':
            result = await connection.call(
              'gateway.stop',
              _gatewaySessionParams(operation),
            );
          default:
            throw FormatException('Unsupported Gateway command');
        }
        final human = switch (operation.name) {
          'run' => 'Gateway ${(result! as Map<String, Object?>)['id']} running',
          'apply-preset' => 'Gateway preset applied',
          'verify' => 'Gateway verification complete',
          'traffic' => 'Gateway traffic returned',
          'reset' => 'Gateway reset complete',
          'stop' => 'Gateway stopped',
          _ => 'Gateway status returned',
        };
        return _success(
          command: commandName,
          result: result,
          human: human,
          json: json,
          effectiveContext: <String, Object?>{'hostOrigin': host.origin},
        );
      } finally {
        await connection.close();
      }
    } on FormatException catch (error) {
      return _failure(commandName, error.message, json: json);
    } on FileSystemException catch (error) {
      return _failure(
        commandName,
        '${error.message}${error.path == null ? '' : ': ${error.path}'}',
        json: json,
      );
    } on GatewayCompileException catch (error) {
      return _failure(commandName, error.toString(), json: json);
    } on ArgumentError catch (error) {
      return _failure(commandName, '${error.message}', json: json);
    } on SocketException catch (error) {
      return CliResult(
        exitCode: 5,
        stderr: 'Host unavailable: ${error.message}\n',
      );
    } on StateError catch (error) {
      return CliResult(exitCode: 3, stderr: '${error.message}\n');
    }
  }

  Future<CliResult> _gatewayLocal(
    ArgResults operation, {
    required bool json,
  }) async {
    final commandName = 'gateway ${operation.name}';
    final localConfig = operation.option('local-config')!;
    final configuration = const WorkspaceConfigurationLoader().load(
      startPath: workspaceDirectory,
      explicitConfigPath: operation.option('config'),
      localConfigRelativePath: localConfig,
    );
    final loaded = const WorkspaceCatalogLoader().loadFromConfiguration(
      configuration,
    );
    final endpoints = const LocalGatewayConfigurationLoader().parseDocument(
      configuration.localDocument,
    );
    final providers = const LocalRemoteConfigProviderLoader().parseDocument(
      configuration.localDocument,
    );
    final providerId = operation.option('provider');

    if (operation.name == 'sync') {
      final configuration = providers[providerId];
      if (configuration == null) {
        throw FormatException('Unknown remote provider: $providerId');
      }
      final result = await RemoteConfigSyncService(
        provider: HttpJsonRemoteConfigProvider(
          credentials: EnvironmentCredentialResolver(),
          clock: SystemClock(),
        ),
        repository: LocalRemoteConfigRepository(
          FileSystemWorkspaceStore(workspaceRoot: loaded.workspaceRoot),
        ),
      ).sync(configuration);
      return _success(
        command: commandName,
        result: result.toJson(),
        human: 'Gateway provider $providerId: ${result.observed.state.name}',
        json: json,
        effectiveContext: <String, Object?>{
          'workspaceRoot': loaded.workspaceRoot,
          'providerId': providerId,
        },
      );
    }

    if (endpoints.isEmpty) {
      throw const FormatException('No local Gateway upstream is configured');
    }
    if (providerId != null && !providers.containsKey(providerId)) {
      throw FormatException('Unknown remote provider: $providerId');
    }
    final selected = providerId == null
        ? endpoints.values
        : <GatewayUpstreamEndpoint>[providers[providerId]!.endpoint];
    final checks = <Map<String, Object?>>[];
    var ready = true;
    final credentials = EnvironmentCredentialResolver();
    for (final endpoint in selected) {
      final handle = endpoint.credentialHandle;
      final credentialAvailable =
          handle == null || await credentials.resolve(handle) != null;
      ready = ready && credentialAvailable;
      checks.add(<String, Object?>{
        ...endpoint.redactedStatus(),
        'credentialAvailable': credentialAvailable,
      });
    }
    final result = <String, Object?>{
      'ready': ready,
      'upstreams': checks,
      'providers': <Object?>[
        for (final provider in providers.values)
          if (providerId == null || provider.id == providerId)
            provider.redactedStatus(),
      ],
    };
    if (!ready) {
      return _gatewayLocalPrecondition(
        command: commandName,
        result: result,
        message: 'One or more Gateway credentials are unavailable.',
        json: json,
        workspaceRoot: loaded.workspaceRoot,
      );
    }
    return _success(
      command: commandName,
      result: result,
      human: 'Gateway local configuration: ready',
      json: json,
      effectiveContext: <String, Object?>{
        'workspaceRoot': loaded.workspaceRoot,
      },
    );
  }

  CliResult _gatewayLocalPrecondition({
    required String command,
    required Object? result,
    required String message,
    required bool json,
    required String workspaceRoot,
  }) {
    if (!json) return CliResult(exitCode: 3, stderr: '$message\n');
    final output = MachineOutput(
      command: command,
      ok: false,
      correlationId: null,
      effectiveContext: <String, Object?>{'workspaceRoot': workspaceRoot},
      result: result,
      failures: <PlatformFailure>[
        PlatformFailure(
          code: 'GATEWAY_PRECONDITION',
          category: FailureCategory.precondition,
          message: message,
          recoverability: Recoverability.userAction,
        ),
      ],
      diagnostics: const <MachineDiagnostic>[],
    );
    return CliResult(exitCode: 3, stderr: '${jsonEncode(output.toJson())}\n');
  }

  Map<String, Object?> _gatewaySessionParams(ArgResults operation) =>
      <String, Object?>{
        'gatewaySessionId': operation.option('gateway-session'),
      };

  Digest _storeGatewayPlan(ArgResults operation) {
    final explicitPlan = operation.option('plan');
    final positional = operation.rest.firstOrNull;
    if (explicitPlan != null && operation.rest.isNotEmpty) {
      throw const FormatException(
        'Use either --plan or one positional preset/file reference',
      );
    }
    final reference = explicitPlan ?? positional;
    if (reference == null || reference.isEmpty) {
      throw const FormatException(
        'A GatewayPreset ref or --plan CompiledGatewayPlan path is required',
      );
    }
    if (operation.rest.length > 1) {
      throw const FormatException('Only one plan reference is accepted');
    }
    final loaded = const WorkspaceCatalogLoader().load(
      startPath: workspaceDirectory,
      explicitConfigPath: operation.option('config'),
    );
    final planFile = File(_absoluteWorkspacePath(reference));
    if (explicitPlan == null && !planFile.existsSync()) {
      return const WorkspaceGatewayPlanCompiler()
          .compilePreset(loaded, presetId: reference, persist: true)
          .planArtifactDigest!;
    }
    if (!planFile.existsSync()) {
      throw FileSystemException('Gateway plan not found', planFile.path);
    }
    final source = planFile.readAsStringSync();
    if (utf8.encode(source).length > 1024 * 1024) {
      throw const FormatException('CompiledGatewayPlan exceeds 1 MiB');
    }
    final plan = CompiledGatewayPlan.fromJson(jsonDecode(source));
    final canonical = utf8.encode(
      const JcsCanonicalizer().canonicalize(plan.toJson()),
    );
    final store = FileSystemWorkspaceStore(workspaceRoot: loaded.workspaceRoot);
    return store.withExclusiveLock(() => store.putBlob(canonical));
  }

  String _absoluteWorkspacePath(String value) => p.isAbsolute(value)
      ? p.normalize(value)
      : p.normalize(p.join(workspaceDirectory, value));

  void _commitSupplementalArtifactImportRoot(
    FileSystemWorkspaceStore store, {
    required Digest artifactDigest,
    required Digest provenanceDigest,
  }) {
    final document = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'SupplementalArtifactImportRoot',
      'artifactDigest': artifactDigest.value,
      'provenanceDigest': provenanceDigest.value,
    };
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(document)}\n',
    );
    final relativePath = p.join(
      'evidence',
      'import-artifact',
      'roots-v1',
      'sha256',
      '${provenanceDigest.value.substring('sha256:'.length)}.json',
    );
    final existing = store.readStateBytes(relativePath);
    if (existing != null) {
      if (!_sameBytes(existing, bytes)) {
        throw StateError(
          'Supplemental artifact import root ownership conflict',
        );
      }
      return;
    }
    store.atomicWrite(relativePath, bytes);
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  ({String workspaceRoot, List<int> bytes}) _readSupplementalArtifactInput(
    String input, {
    required String workspaceRoot,
    required String inputBase,
  }) {
    if (input.isEmpty) {
      throw const FormatException('--input must not be empty');
    }
    final requestedRoot = Directory(workspaceRoot).absolute;
    if (!requestedRoot.existsSync()) {
      throw FileSystemException(
        'Workspace root does not exist',
        requestedRoot.path,
      );
    }
    final resolvedWorkspaceRoot = p.normalize(
      requestedRoot.resolveSymbolicLinksSync(),
    );
    final requestedBase = Directory(inputBase).absolute;
    if (!requestedBase.existsSync()) {
      throw FileSystemException(
        'Input base does not exist',
        requestedBase.path,
      );
    }
    final inputBasePath = p.normalize(requestedBase.resolveSymbolicLinksSync());
    final requestedPath = p.normalize(
      p.isAbsolute(input) ? input : p.join(inputBasePath, input),
    );
    if (!p.isWithin(resolvedWorkspaceRoot, requestedPath)) {
      throw FileSystemException(
        'Supplemental artifact input escapes the workspace',
        requestedPath,
      );
    }

    var currentPath = requestedPath;
    while (!p.equals(currentPath, resolvedWorkspaceRoot)) {
      if (FileSystemEntity.typeSync(currentPath, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'Supplemental artifact input crosses a symlink',
          currentPath,
        );
      }
      final parentPath = p.dirname(currentPath);
      if (p.equals(parentPath, currentPath)) {
        throw FileSystemException(
          'Supplemental artifact input escapes the workspace',
          requestedPath,
        );
      }
      currentPath = parentPath;
    }

    if (FileSystemEntity.typeSync(requestedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Supplemental artifact input must be a regular non-symlink file',
        requestedPath,
      );
    }
    final resolvedPath = p.normalize(
      File(requestedPath).resolveSymbolicLinksSync(),
    );
    if (!p.isWithin(resolvedWorkspaceRoot, resolvedPath) ||
        !p.equals(resolvedPath, requestedPath)) {
      throw FileSystemException(
        'Supplemental artifact input escapes the workspace',
        requestedPath,
      );
    }

    final file = File(resolvedPath);
    final before = file.statSync();
    if (before.type != FileSystemEntityType.file ||
        before.size < 1 ||
        before.size >
            ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes) {
      throw FormatException(
        'Supplemental artifact input must be between 1 and '
        '${ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes} bytes',
      );
    }
    final builder = BytesBuilder(copy: false);
    final reader = file.openSync();
    try {
      while (builder.length <=
          ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes) {
        final remaining =
            ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes +
            1 -
            builder.length;
        final bytesToRead = remaining < 64 * 1024 ? remaining : 64 * 1024;
        final chunk = reader.readSync(bytesToRead);
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
    } finally {
      reader.closeSync();
    }
    final bytes = builder.takeBytes();
    final after = file.statSync();
    if (FileSystemEntity.typeSync(resolvedPath, followLinks: false) !=
            FileSystemEntityType.file ||
        bytes.isEmpty ||
        bytes.length >
            ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes ||
        bytes.length != before.size ||
        after.size != before.size ||
        after.modified != before.modified ||
        after.changed != before.changed) {
      throw StateError(
        'Supplemental artifact input changed while it was being read',
      );
    }
    return (workspaceRoot: resolvedWorkspaceRoot, bytes: bytes);
  }

  void _validateSupplementalArtifactMedia(
    ScenarioLabSupplementalArtifactMediaType mediaType,
    List<int> bytes,
  ) {
    switch (mediaType) {
      case ScenarioLabSupplementalArtifactMediaType.png:
        const PngCaptureInspector().inspect(bytes);
        return;
      case ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1:
        if (bytes.length > 16 * 1024 * 1024) {
          throw const FormatException('Android semantics input exceeds 16 MiB');
        }
        final text = utf8.decode(bytes, allowMalformed: false);
        final value = jsonDecode(text);
        if (value is! Map<String, Object?>) {
          throw const FormatException(
            'Android semantics input must be an object',
          );
        }
        const fields = <String>{'schemaVersion', 'kind', 'privacy', 'nodes'};
        final nodes = value['nodes'];
        if (value.length != fields.length ||
            value.keys.any((key) => !fields.contains(key)) ||
            value['schemaVersion'] != 1 ||
            value['kind'] != 'AndroidSemanticsSnapshot' ||
            value['privacy'] != 'hashedTextV1' ||
            nodes is! List<Object?> ||
            nodes.isEmpty ||
            nodes.length > 100000 ||
            nodes.any((node) => node is! Map<String, Object?>)) {
          throw const FormatException(
            'Android semantics input has an invalid shape',
          );
        }
        String canonical;
        try {
          canonical = const JcsCanonicalizer().canonicalize(value);
        } on CanonicalJsonException catch (error) {
          throw FormatException(
            'Android semantics input is not canonical JSON: ${error.message}',
          );
        }
        if (text != '$canonical\n') {
          throw const FormatException(
            'Android semantics input must be canonical JCS',
          );
        }
        return;
    }
  }

  Object? _readJsonDocument(String path, {int maxBytes = 16 * 1024 * 1024}) {
    final file = File(_absoluteWorkspacePath(path));
    if (Link(file.path).existsSync() || !file.existsSync()) {
      throw FileSystemException(
        'JSON document is missing or linked',
        file.path,
      );
    }
    final length = file.lengthSync();
    if (length <= 0 || length > maxBytes) {
      throw FormatException('JSON document size is invalid: ${file.path}');
    }
    return jsonDecode(
      utf8.decode(file.readAsBytesSync(), allowMalformed: false),
    );
  }

  void _writeCanonicalDocument(String path, Map<String, Object?> document) {
    final file = File(_absoluteWorkspacePath(path));
    if (Link(file.path).existsSync()) {
      throw FileSystemException('Output path is a link', file.path);
    }
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(document)}\n',
    );
    if (file.existsSync()) {
      final existing = file.readAsBytesSync();
      if (_sameCliBytes(existing, bytes)) return;
      throw FileSystemException(
        'Output exists with different content',
        file.path,
      );
    }
    file.parent.createSync(recursive: true);
    final staging = File('${file.path}.new-$pid');
    if (staging.existsSync() || Link(staging.path).existsSync()) {
      throw FileSystemException(
        'Output staging path already exists',
        staging.path,
      );
    }
    try {
      staging.writeAsBytesSync(bytes, flush: true);
      staging.renameSync(file.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }

  void _writeExactBytes(String path, List<int> bytes) {
    final file = File(_absoluteWorkspacePath(path));
    if (Link(file.path).existsSync()) {
      throw FileSystemException('Output path is a link', file.path);
    }
    if (file.existsSync()) {
      if (_sameCliBytes(file.readAsBytesSync(), bytes)) return;
      throw FileSystemException(
        'Output exists with different content',
        file.path,
      );
    }
    file.parent.createSync(recursive: true);
    final staging = File('${file.path}.new-$pid');
    if (staging.existsSync() || Link(staging.path).existsSync()) {
      throw FileSystemException(
        'Output staging path already exists',
        staging.path,
      );
    }
    try {
      staging.writeAsBytesSync(bytes, flush: true);
      staging.renameSync(file.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }

  Map<String, Object?> _queryOptions(List<String> values) {
    final result = <String, Object?>{};
    for (final value in values) {
      final separator = value.indexOf('=');
      if (separator < 1) {
        throw FormatException('--query must use key=value: $value');
      }
      final key = value.substring(0, separator);
      final item = value.substring(separator + 1);
      if (item.isEmpty) {
        throw FormatException('--query value must not be empty: $value');
      }
      final previous = result[key];
      if (previous == null) {
        result[key] = item;
      } else if (previous is String) {
        result[key] = <String>[previous, item];
      } else {
        (previous as List<String>).add(item);
      }
    }
    return result;
  }

  int _boundedInteger(
    String source,
    String option, {
    required int minimum,
    required int maximum,
  }) {
    final value = int.tryParse(source);
    if (value == null || value < minimum || value > maximum) {
      throw FormatException(
        '--$option must be an integer from $minimum to $maximum',
      );
    }
    return value;
  }

  String? _findExecutable(String name) {
    final path = Platform.environment['PATH'];
    if (path == null) return null;
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      final candidate = File('$directory${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  Map<String, Object?> _catalogSummary(CatalogManifest manifest) =>
      <String, Object?>{
        'manifestDigest': manifest.digest.value,
        'applications': manifest.applications.length,
        'journeys': manifest.journeys.length,
        'scenarios': manifest.scenarios.length,
        'transitions': manifest.transitions.length,
      };

  int _port(String source, String option) =>
      _boundedInteger(source, option, minimum: 0, maximum: 65535);

  Uri? _studioDevelopmentOrigin(String? source) {
    if (source == null) return null;
    final origin = Uri.tryParse(source);
    final loopback =
        origin != null &&
        const <String>{'127.0.0.1', 'localhost', '::1'}.contains(origin.host);
    if (origin == null ||
        !origin.isAbsolute ||
        origin.scheme != 'http' ||
        !loopback ||
        origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw const FormatException(
        '--studio-dev-origin must be an HTTP loopback origin without path, '
        'query or fragment',
      );
    }
    return Uri.parse(origin.origin);
  }

  Future<String> _resolveStudioAssets(String? explicit) async {
    final candidates = <String>[
      if (explicit != null)
        p.isAbsolute(explicit)
            ? p.normalize(explicit)
            : p.normalize(p.join(workspaceDirectory, explicit)),
      if (Platform.environment['STUDIO_ASSETS_DIRECTORY'] case final value?)
        p.normalize(value),
      p.normalize(
        p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'studio'),
      ),
      if (await _sourceRepositoryRoot() case final root?)
        p.join(root, 'apps', 'studio', 'build', 'jaspr'),
    ];
    for (final candidate in candidates) {
      final index = File(p.join(candidate, 'index.html'));
      if (Directory(candidate).existsSync() && index.existsSync()) {
        return Directory(candidate).resolveSymbolicLinksSync();
      }
    }
    throw FileSystemException(
      'Packaged Studio assets not found; build the Studio or pass --studio-assets',
      explicit,
    );
  }

  Future<String?> _sourceRepositoryRoot() async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:workspace_cli/workspace_cli.dart'),
    );
    if (library == null || library.scheme != 'file') return null;
    final candidate = p.normalize(
      p.join(p.dirname(library.toFilePath()), '..', '..', '..'),
    );
    final pubspec = File(p.join(candidate, 'pubspec.yaml'));
    return pubspec.existsSync() &&
            pubspec.readAsStringSync().contains(
              'name: experience_platform_workspace',
            )
        ? Directory(candidate).resolveSymbolicLinksSync()
        : null;
  }

  Future<({String command, List<String> arguments, String workingDirectory})?>
  _gatewaySidecar(ResolvedKitPlan plan) async {
    if (!plan.enabledModules.any(
      (module) => module.moduleId.value == 'gateway.interceptor',
    )) {
      return null;
    }
    final configured = Platform.environment['GATEWAY_COMMAND'];
    if (configured != null && configured.isNotEmpty) {
      final rawArguments =
          Platform.environment['GATEWAY_ARGUMENTS_JSON'] ?? '[]';
      final decoded = jsonDecode(rawArguments);
      if (decoded is! List<Object?> || decoded.any((item) => item is! String)) {
        throw const FormatException(
          'GATEWAY_ARGUMENTS_JSON must be a string array',
        );
      }
      return (
        command: configured,
        arguments: decoded.cast<String>(),
        workingDirectory:
            Platform.environment['GATEWAY_WORKING_DIRECTORY'] ??
            workspaceDirectory,
      );
    }
    final packaged = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'gateway_sidecar'),
    );
    if (packaged.existsSync()) {
      return (
        command: packaged.resolveSymbolicLinksSync(),
        arguments: const <String>[],
        workingDirectory: workspaceDirectory,
      );
    }
    final repository = await _sourceRepositoryRoot();
    if (repository != null) {
      return (
        command: Platform.resolvedExecutable,
        arguments: <String>[
          'run',
          p.join(
            repository,
            'apps',
            'gateway_sidecar',
            'bin',
            'gateway_sidecar.dart',
          ),
        ],
        workingDirectory: repository,
      );
    }
    throw const FileSystemException(
      'gateway.interceptor is enabled but its sidecar is not packaged',
    );
  }

  void _watchDevelopment(DevelopmentSupervisor supervisor) {
    late final List<StreamSubscription<ProcessSignal>> subscriptions;
    void requestStop(ProcessSignal _) {
      unawaited(_stopDevelopment(supervisor));
    }

    subscriptions = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigint.watch().listen(requestStop),
      if (!Platform.isWindows)
        ProcessSignal.sigterm.watch().listen(requestStop),
    ];
    _developmentRuns[supervisor] = subscriptions;
  }

  Future<void> _stopDevelopment(DevelopmentSupervisor supervisor) async {
    final subscriptions = _developmentRuns.remove(supervisor);
    if (subscriptions == null) return;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await supervisor.close();
  }

  Future<String?> _openBrowser(Uri uri) async {
    final (command, arguments) = switch (Platform.operatingSystem) {
      'linux' => ('xdg-open', <String>[uri.toString()]),
      'macos' => ('open', <String>[uri.toString()]),
      'windows' => ('cmd', <String>['/c', 'start', '', uri.toString()]),
      _ => ('', const <String>[]),
    };
    if (command.isEmpty || _findExecutable(command) == null) {
      return 'Browser launcher is unavailable; open ${uri.toString()} manually.';
    }
    try {
      final result = await Process.run(
        command,
        arguments,
      ).timeout(const Duration(seconds: 10));
      return result.exitCode == 0
          ? null
          : 'Browser launcher exited with code ${result.exitCode}.';
    } on Object {
      return 'Browser launcher failed; open ${uri.toString()} manually.';
    }
  }

  CliResult _success({
    required String command,
    required Object? result,
    required String human,
    required bool json,
    Map<String, Object?> effectiveContext = const <String, Object?>{},
    List<MachineDiagnostic> diagnostics = const <MachineDiagnostic>[],
  }) {
    if (!json) return CliResult(exitCode: 0, stdout: '$human\n');
    final output = MachineOutput(
      command: command,
      ok: true,
      correlationId: null,
      effectiveContext: effectiveContext,
      result: result,
      failures: const <PlatformFailure>[],
      diagnostics: diagnostics,
    );
    return CliResult(exitCode: 0, stdout: '${jsonEncode(output.toJson())}\n');
  }

  CliResult _failure(String command, String message, {required bool json}) {
    final failure = PlatformFailure(
      code: 'AUTHORING_INVALID',
      category: FailureCategory.authoringValidation,
      message: message,
      recoverability: Recoverability.userAction,
    );
    if (!json) return CliResult(exitCode: 2, stderr: '$message\n');
    final output = MachineOutput(
      command: command,
      ok: false,
      correlationId: null,
      effectiveContext: const <String, Object?>{},
      result: null,
      failures: <PlatformFailure>[failure],
      diagnostics: const <MachineDiagnostic>[],
    );
    return CliResult(exitCode: 2, stderr: '${jsonEncode(output.toJson())}\n');
  }

  CliResult _preconditionFailure(
    String command,
    String message, {
    required bool json,
    EvidenceFreshness? freshness,
  }) {
    final failure = PlatformFailure(
      code: 'EVIDENCE_PRECONDITION',
      category: FailureCategory.precondition,
      message: message,
      recoverability: Recoverability.userAction,
    );
    if (!json) return CliResult(exitCode: 3, stderr: '$message\n');
    final output = MachineOutput(
      command: command,
      ok: false,
      correlationId: null,
      effectiveContext: <String, Object?>{
        if (freshness != null) 'freshness': freshness.name,
      },
      result: null,
      failures: <PlatformFailure>[failure],
      diagnostics: const <MachineDiagnostic>[],
    );
    return CliResult(exitCode: 3, stderr: '${jsonEncode(output.toJson())}\n');
  }

  CliResult _policyDenied(
    String command,
    String message, {
    required Object? result,
    required bool json,
  }) {
    if (!json) return CliResult(exitCode: 4, stderr: '$message\n');
    final output = MachineOutput(
      command: command,
      ok: false,
      correlationId: null,
      effectiveContext: const <String, Object?>{},
      result: result,
      failures: <PlatformFailure>[
        PlatformFailure(
          code: 'POLICY_DENIED',
          category: FailureCategory.policyDenied,
          message: message,
          recoverability: Recoverability.userAction,
        ),
      ],
      diagnostics: const <MachineDiagnostic>[],
    );
    return CliResult(exitCode: 4, stderr: '${jsonEncode(output.toJson())}\n');
  }
}

final class _HostedCredential {
  const _HostedCredential({
    required this.hostedUrl,
    required this.tenantId,
    required this.issuer,
    required this.subject,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final Uri hostedUrl;
  final String tenantId;
  final Uri issuer;
  final String subject;
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'hostedUrl': hostedUrl.toString(),
    'tenantId': tenantId,
    'issuer': issuer.toString(),
    'subject': subject,
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  Map<String, Object?> redactedJson() => <String, Object?>{
    'hostedUrl': hostedUrl.toString(),
    'tenantId': tenantId,
    'issuer': issuer.toString(),
    'subject': subject,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory _HostedCredential.fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['schemaVersion'] != 1) {
      throw const FormatException('hosted credential document is invalid');
    }
    String field(String name) {
      final item = value[name];
      if (item is! String || item.isEmpty) {
        throw FormatException('hosted credential $name is invalid');
      }
      return item;
    }

    final expiresAt = DateTime.tryParse(field('expiresAt'));
    final refreshToken = value['refreshToken'];
    if (expiresAt == null ||
        !expiresAt.isUtc ||
        (refreshToken != null && refreshToken is! String)) {
      throw const FormatException('hosted credential fields are invalid');
    }
    return _HostedCredential(
      hostedUrl: Uri.parse(field('hostedUrl')),
      tenantId: field('tenantId'),
      issuer: Uri.parse(field('issuer')),
      subject: field('subject'),
      accessToken: field('accessToken'),
      refreshToken: refreshToken as String?,
      expiresAt: expiresAt,
    );
  }
}

final class _HostedCredentialStore {
  const _HostedCredentialStore(this.path);

  final String path;

  _HostedCredential? read() {
    final file = File(path);
    if (!file.existsSync()) return null;
    if (!Platform.isWindows && file.statSync().mode & 0x3f != 0) {
      throw const FormatException(
        'hosted credential file must not be accessible by group or others',
      );
    }
    final decoded = jsonDecode(file.readAsStringSync());
    return _HostedCredential.fromJson(decoded);
  }

  void write(_HostedCredential value) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final temporary = File('$path.tmp-${pid.toString()}');
    try {
      temporary.writeAsStringSync(
        const JcsCanonicalizer().canonicalize(value.toJson()),
        flush: true,
      );
      if (!Platform.isWindows) {
        final chmod = Process.runSync('chmod', <String>['600', temporary.path]);
        if (chmod.exitCode != 0) {
          throw const FileSystemException('could not restrict credential file');
        }
      }
      temporary.renameSync(path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  bool delete() {
    final file = File(path);
    if (!file.existsSync()) return false;
    file.deleteSync();
    return true;
  }
}

final class _HostedLink {
  _HostedLink({
    required this.hostedUrl,
    required this.tenantId,
    required this.workspaceId,
    required this.localWorkspaceId,
    required this.linkedAt,
  }) {
    HostedWorkspaceLink(
      tenantId: tenantId,
      workspaceId: workspaceId,
      localWorkspaceId: localWorkspaceId,
      linkedAt: linkedAt,
      linkedBy: 'local-cli',
    );
  }

  final Uri hostedUrl;
  final String tenantId;
  final String workspaceId;
  final String localWorkspaceId;
  final DateTime linkedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'hostedUrl': hostedUrl.toString(),
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'localWorkspaceId': localWorkspaceId,
    'linkedAt': linkedAt.toIso8601String(),
  };

  factory _HostedLink.fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['schemaVersion'] != 1) {
      throw const FormatException('hosted workspace link is invalid');
    }
    String field(String name) {
      final item = value[name];
      if (item is! String || item.isEmpty) {
        throw FormatException('hosted workspace link $name is invalid');
      }
      return item;
    }

    final linkedAt = DateTime.tryParse(field('linkedAt'));
    if (linkedAt == null || !linkedAt.isUtc) {
      throw const FormatException('hosted workspace link timestamp is invalid');
    }
    return _HostedLink(
      hostedUrl: Uri.parse(field('hostedUrl')),
      tenantId: field('tenantId'),
      workspaceId: field('workspaceId'),
      localWorkspaceId: field('localWorkspaceId'),
      linkedAt: linkedAt,
    );
  }
}

final class _HostedLinkStore {
  const _HostedLinkStore(this.path);

  final String path;

  _HostedLink read() {
    final file = File(path);
    if (!file.existsSync()) {
      throw const FormatException('workspace is not linked to hosted');
    }
    return _HostedLink.fromJson(jsonDecode(file.readAsStringSync()));
  }

  void write(_HostedLink link) {
    final file = File(path)..parent.createSync(recursive: true);
    final temporary = File('$path.tmp-$pid');
    try {
      temporary.writeAsStringSync(
        const JcsCanonicalizer().canonicalize(link.toJson()),
        flush: true,
      );
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}

final class _HostedApiResponse {
  const _HostedApiResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

final class _HostedApiClient {
  _HostedApiClient(this.credential) : _client = HttpClient();

  static const int _maximumResponseBytes = 16 * 1024 * 1024;
  final _HostedCredential credential;
  final HttpClient _client;

  Future<_HostedApiResponse> get(String path, Map<String, String> query) =>
      _send('GET', path, query: query);

  Future<_HostedApiResponse> post(String path, Map<String, Object?> body) =>
      _send('POST', path, body: body);

  Future<_HostedApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final uri = credential.hostedUrl
        .resolve(path)
        .replace(queryParameters: query?.isEmpty ?? true ? null : query);
    if (uri.origin != credential.hostedUrl.origin) {
      throw const FormatException('hosted request escaped configured origin');
    }
    final request = await _client.openUrl(method, uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${credential.accessToken}',
      )
      ..headers.set('x-workspace-tenant', credential.tenantId)
      ..headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(const JcsCanonicalizer().canonicalize(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > _maximumResponseBytes) {
        throw const FormatException('hosted response exceeds 16 MiB');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('hosted response must be a JSON object');
    }
    return _HostedApiResponse(response.statusCode, decoded);
  }

  void close() => _client.close(force: true);
}

bool _sameCliBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _HostRpcConnection {
  _HostRpcConnection._(this.socket, this.iterator);

  final WebSocket socket;
  final StreamIterator<Object?> iterator;
  var _nextId = 1;

  static Future<_HostRpcConnection> connect({
    required Uri host,
    required String token,
    required Uri studioOrigin,
  }) async {
    if ((host.scheme != 'http' && host.scheme != 'https') ||
        host.host.isEmpty ||
        studioOrigin.origin == 'null') {
      throw const FormatException('Invalid Host or Studio origin');
    }
    final rpcUri = host.replace(
      scheme: host.scheme == 'https' ? 'wss' : 'ws',
      path: '/rpc',
      query: null,
      fragment: null,
    );

    // ignore: close_sinks
    final socket = await WebSocket.connect(
      rpcUri.toString(),
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    final connection = _HostRpcConnection._(
      socket,
      StreamIterator<Object?>(socket),
    );
    try {
      await connection.call('workspace.initialize', <String, Object?>{
        'protocolVersion': 1,
        'sessionToken': token,
      });
      return connection;
    } on Object {
      await connection.close();
      rethrow;
    }
  }

  Future<Object?> call(String method, Map<String, Object?> params) async {
    final requestId = 'cli-${_nextId++}';
    socket.add(
      JsonRpcRequest(method: method, id: requestId, params: params).encode(),
    );
    while (await iterator.moveNext()) {
      final value = iterator.current;
      if (value is! String) {
        throw const FormatException('Host returned a non-text RPC message');
      }
      final message = const JsonRpcCodec().decode(value);
      if (message is JsonRpcResponse && message.id == requestId) {
        if (!message.isSuccess) {
          throw StateError('${message.error!.code}: ${message.error!.message}');
        }
        return message.result;
      }
    }
    throw const SocketException('Host closed before returning a response');
  }

  Future<void> close() async {
    await iterator.cancel();
    await socket.close();
  }
}
