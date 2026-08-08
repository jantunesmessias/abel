import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

Future<void> main() async {
  final token = Platform.environment['WORKSPACE_HOST_TOKEN'];
  final origin = Platform.environment['STUDIO_ORIGIN'];
  if (token == null || origin == null) {
    stderr.writeln('WORKSPACE_HOST_TOKEN and STUDIO_ORIGIN are required.');
    exitCode = 2;
    return;
  }

  final workspaceRoot =
      Platform.environment['WORKSPACE_ROOT'] ?? Directory.current.path;
  final planPath = Platform.environment['RESOLVED_COMPOSITION_PLAN'];
  final expectedPlanDigest =
      Platform.environment['RESOLVED_COMPOSITION_PLAN_DIGEST'];
  final moduleCatalogPath = Platform.environment['MODULE_CATALOG_PATH'];
  if ((planPath == null) != (expectedPlanDigest == null)) {
    stderr.writeln(
      'RESOLVED_COMPOSITION_PLAN and RESOLVED_COMPOSITION_PLAN_DIGEST must be set together.',
    );
    exitCode = 2;
    return;
  }
  if (moduleCatalogPath != null && planPath == null) {
    stderr.writeln('MODULE_CATALOG_PATH requires RESOLVED_COMPOSITION_PLAN.');
    exitCode = 2;
    return;
  }
  final gatewayCommand = Platform.environment['GATEWAY_COMMAND'];
  final gatewayArguments = <String>[];
  final encodedGatewayArguments =
      Platform.environment['GATEWAY_ARGUMENTS_JSON'];
  if (encodedGatewayArguments != null) {
    try {
      final decoded = jsonDecode(encodedGatewayArguments);
      if (decoded is! List<Object?> ||
          decoded.any((argument) => argument is! String)) {
        throw const FormatException('expected a string array');
      }
      gatewayArguments.addAll(decoded.cast<String>());
    } on Object catch (error) {
      stderr.writeln('Invalid GATEWAY_ARGUMENTS_JSON: $error');
      exitCode = 2;
      return;
    }
  }
  final gatewayWorkingDirectory =
      Platform.environment['GATEWAY_WORKING_DIRECTORY'];
  if ((gatewayCommand == null || gatewayCommand.isEmpty) &&
      (gatewayArguments.isNotEmpty || gatewayWorkingDirectory != null)) {
    stderr.writeln(
      'GATEWAY_COMMAND is required when Gateway options are present.',
    );
    exitCode = 2;
    return;
  }
  final profiles = <LaunchProfile>[];
  final encodedProfile = Platform.environment['TARGET_LAUNCH_PROFILE_JSON'];
  if (encodedProfile != null) {
    try {
      final profile = jsonDecode(encodedProfile) as Map<String, Object?>;
      profiles.add(
        LaunchProfile(
          id: profile['id']! as String,
          applicationId: ApplicationId(profile['applicationId']! as String),
          platform: TargetPlatform.values.byName(
            profile['platform']! as String,
          ),
          command: profile['command']! as String,
          arguments: (profile['arguments']! as List<Object?>).cast<String>(),
          workingDirectory: profile['workingDirectory']! as String,
          overlay: RuntimeConfigurationOverlay(
            (profile['overlay'] as Map<String, Object?>? ??
                    const <String, Object?>{})
                .cast<String, String>(),
          ),
          bootstrapPolicy: ApplicationBootstrapPolicy(
            const <String, BootstrapDependencyPolicy>{},
          ),
        ),
      );
    } on Object catch (error) {
      stderr.writeln('Invalid TARGET_LAUNCH_PROFILE_JSON: $error');
      exitCode = 2;
      return;
    }
  }
  late final WorkspaceHost application;
  Digest? configuredModuleCatalogDigest;
  try {
    if (planPath == null) {
      application = WorkspaceHost(
        studioOrigin: Uri.parse(origin),
        sessionToken: token,
        workspaceRoot: workspaceRoot,
        launchProfiles: profiles,
        gatewaySidecarCommand: gatewayCommand?.isEmpty ?? true
            ? null
            : gatewayCommand,
        gatewaySidecarArguments: gatewayArguments,
        gatewaySidecarWorkingDirectory: gatewayWorkingDirectory,
      );
    } else {
      final catalog = moduleCatalogPath == null
          ? const BuiltinModuleCatalog().create(platform: _platformId())
          : _readModuleCatalog(moduleCatalogPath);
      if (moduleCatalogPath != null) {
        configuredModuleCatalogDigest = catalog.digest;
      }
      final plan = const ResolvedKitPlanFile().read(
        path: planPath,
        catalog: catalog,
        expectedDigest: Digest(expectedPlanDigest!),
      );
      application = WorkspaceHost.fromResolvedPlan(
        studioOrigin: Uri.parse(origin),
        sessionToken: token,
        workspaceRoot: workspaceRoot,
        launchProfiles: profiles,
        catalog: catalog,
        plan: plan,
        gatewaySidecarCommand: gatewayCommand?.isEmpty ?? true
            ? null
            : gatewayCommand,
        gatewaySidecarArguments: gatewayArguments,
        gatewaySidecarWorkingDirectory: gatewayWorkingDirectory,
      );
    }
  } on Object catch (error) {
    stderr.writeln('Invalid Workspace Host composition: $error');
    exitCode = 2;
    return;
  }
  await application.start();
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'status': 'ready',
      'hostOrigin': application.rpc.httpUri.toString(),
      'launchProfiles': <String>[for (final profile in profiles) profile.id],
      'gatewayAvailable': gatewayCommand != null && gatewayCommand.isNotEmpty,
      'planDigest': application.effectiveKitManifest.resolvedPlanDigest.value,
      if (moduleCatalogPath != null)
        'moduleCatalogDigest': configuredModuleCatalogDigest!.value,
      'effectiveKitManifest': application.effectiveKitManifest.toJson(),
    }),
  );

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigint;
  late final StreamSubscription<ProcessSignal> sigterm;
  void requestStop(ProcessSignal _) {
    if (!stopping.isCompleted) stopping.complete();
  }

  sigint = ProcessSignal.sigint.watch().listen(requestStop);
  sigterm = ProcessSignal.sigterm.watch().listen(requestStop);
  await stopping.future;
  await application.close();
  await sigint.cancel();
  await sigterm.cancel();
}

ModuleCatalog _readModuleCatalog(String path) {
  final file = File(path).absolute;
  if (!file.existsSync() ||
      Link(file.path).existsSync() ||
      file.lengthSync() <= 0 ||
      file.lengthSync() > 8 * 1024 * 1024) {
    throw FileSystemException('Module catalog is missing or unsafe', file.path);
  }
  final bytes = file.readAsBytesSync();
  final catalog = ModuleCatalog.fromJson(jsonDecode(utf8.decode(bytes)));
  final canonical = utf8.encode(
    const JcsCanonicalizer().canonicalize(catalog.toJson()),
  );
  if (!_sameBytes(bytes, canonical) || catalog.platform != _platformId()) {
    throw const FormatException(
      'Module catalog is non-canonical or targets another platform',
    );
  }
  return catalog;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _platformId() => switch (Platform.operatingSystem) {
  'linux' => 'linux-x64',
  'macos' => 'macos-arm64',
  'windows' => 'windows-x64',
  final value => '$value-native',
};
