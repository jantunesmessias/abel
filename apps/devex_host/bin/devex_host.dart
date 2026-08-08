import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';

Future<void> main() async {
  final token = Platform.environment['DEVEX_HOST_TOKEN'];
  final origin = Platform.environment['DEVEX_STUDIO_ORIGIN'];
  if (token == null || origin == null) {
    stderr.writeln('DEVEX_HOST_TOKEN and DEVEX_STUDIO_ORIGIN are required.');
    exitCode = 2;
    return;
  }

  final workspaceRoot =
      Platform.environment['DEVEX_WORKSPACE_ROOT'] ?? Directory.current.path;
  final planPath = Platform.environment['DEVEX_RESOLVED_KIT_PLAN'];
  final expectedPlanDigest =
      Platform.environment['DEVEX_RESOLVED_KIT_PLAN_DIGEST'];
  if ((planPath == null) != (expectedPlanDigest == null)) {
    stderr.writeln(
      'DEVEX_RESOLVED_KIT_PLAN and DEVEX_RESOLVED_KIT_PLAN_DIGEST must be set together.',
    );
    exitCode = 2;
    return;
  }
  final gatewayCommand = Platform.environment['DEVEX_GATEWAY_COMMAND'];
  final gatewayArguments = <String>[];
  final encodedGatewayArguments =
      Platform.environment['DEVEX_GATEWAY_ARGUMENTS_JSON'];
  if (encodedGatewayArguments != null) {
    try {
      final decoded = jsonDecode(encodedGatewayArguments);
      if (decoded is! List<Object?> ||
          decoded.any((argument) => argument is! String)) {
        throw const FormatException('expected a string array');
      }
      gatewayArguments.addAll(decoded.cast<String>());
    } on Object catch (error) {
      stderr.writeln('Invalid DEVEX_GATEWAY_ARGUMENTS_JSON: $error');
      exitCode = 2;
      return;
    }
  }
  final gatewayWorkingDirectory =
      Platform.environment['DEVEX_GATEWAY_WORKING_DIRECTORY'];
  if ((gatewayCommand == null || gatewayCommand.isEmpty) &&
      (gatewayArguments.isNotEmpty || gatewayWorkingDirectory != null)) {
    stderr.writeln(
      'DEVEX_GATEWAY_COMMAND is required when Gateway options are present.',
    );
    exitCode = 2;
    return;
  }
  final profiles = <LaunchProfile>[];
  final encodedProfile = Platform.environment['DEVEX_LAUNCH_PROFILE_JSON'];
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
      stderr.writeln('Invalid DEVEX_LAUNCH_PROFILE_JSON: $error');
      exitCode = 2;
      return;
    }
  }
  late final DevExHostApplication application;
  try {
    if (planPath == null) {
      application = DevExHostApplication(
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
      const builtins = BuiltinModuleCatalog();
      final catalog = builtins.create(platform: _platformId());
      final plan = const ResolvedKitPlanFile().read(
        path: planPath,
        catalog: catalog,
        expectedDigest: Digest(expectedPlanDigest!),
      );
      application = DevExHostApplication.fromResolvedPlan(
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
    stderr.writeln('Invalid DevEx Host composition: $error');
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

String _platformId() => switch (Platform.operatingSystem) {
  'linux' => 'linux-x64',
  'macos' => 'macos-arm64',
  'windows' => 'windows-x64',
  final value => '$value-native',
};
