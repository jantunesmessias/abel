import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';

import '../secure_id_generator.dart';
import 'devex_host_application.dart';
import 'devex_studio_server.dart';

final class DevExDevelopmentRuntime {
  const DevExDevelopmentRuntime({
    required this.profileId,
    required this.planDigest,
    required this.hostOrigin,
    required this.studioOrigin,
    required this.studioBootstrapUri,
    required this.effectiveKitManifest,
  });

  final String profileId;
  final Digest planDigest;
  final Uri hostOrigin;
  final Uri? studioOrigin;
  final Uri? studioBootstrapUri;
  final EffectiveKitManifest effectiveKitManifest;

  Map<String, Object?> toJson() => <String, Object?>{
    'profileId': profileId,
    'planDigest': planDigest.value,
    'hostOrigin': hostOrigin.toString(),
    if (studioOrigin != null) 'studioOrigin': studioOrigin.toString(),
    if (studioBootstrapUri != null)
      'studioBootstrapUri': studioBootstrapUri.toString(),
    'effectiveKitManifestDigest': effectiveKitManifest.digest.value,
    'pid': pid,
  };
}

/// Starts and owns the local Host + optional packaged Studio origin.
final class DevExDevelopmentSupervisor {
  DevExDevelopmentSupervisor({
    required this.workspaceRoot,
    required this.catalog,
    required this.plan,
    this.studioAssetRoot,
    this.studioDevelopmentOrigin,
    this.hostPort = 0,
    this.studioPort = 0,
    this.headlessStudioOrigin,
    this.gatewaySidecarCommand,
    this.gatewaySidecarArguments = const <String>[],
    this.gatewaySidecarWorkingDirectory,
    this.launchProfiles = const <LaunchProfile>[],
  });

  final String workspaceRoot;
  final ModuleCatalog catalog;
  final ResolvedKitPlan plan;
  final String? studioAssetRoot;
  final Uri? studioDevelopmentOrigin;
  final int hostPort;
  final int studioPort;
  final Uri? headlessStudioOrigin;
  final String? gatewaySidecarCommand;
  final List<String> gatewaySidecarArguments;
  final String? gatewaySidecarWorkingDirectory;
  final List<LaunchProfile> launchProfiles;

  DevExHostApplication? _host;
  DevExStudioServer? _studio;
  DevExDevelopmentRuntime? _runtime;

  bool get isRunning => _runtime != null;
  DevExDevelopmentRuntime get runtime =>
      _runtime ?? (throw StateError('Development runtime is not started'));

  Future<DevExDevelopmentRuntime> start() async {
    if (_host != null || _studio != null || _runtime != null) {
      throw StateError('Development supervisor already started');
    }
    bool enabled(String id) =>
        plan.enabledModules.any((module) => module.moduleId.value == id);
    final studioEnabled = enabled('studio.shell');
    if (studioEnabled &&
        (studioAssetRoot == null) == (studioDevelopmentOrigin == null)) {
      throw ArgumentError(
        'studio.shell requires exactly one packaged asset root or external '
        'development origin',
      );
    }
    if (!studioEnabled &&
        (studioAssetRoot != null || studioDevelopmentOrigin != null)) {
      throw ArgumentError(
        'Studio configuration was supplied while studio.shell is disabled',
      );
    }
    if (studioDevelopmentOrigin case final origin?
        when !_isLoopbackOrigin(origin)) {
      throw ArgumentError.value(
        origin,
        'studioDevelopmentOrigin',
        'must be an HTTP loopback origin without path, query or fragment',
      );
    }
    if (!studioEnabled && headlessStudioOrigin == null) {
      throw ArgumentError('Headless Host requires an allowed Studio origin');
    }
    if (enabled('gateway.interceptor') && gatewaySidecarCommand == null) {
      throw ArgumentError('gateway.interceptor requires its packaged sidecar');
    }

    final tokenGenerator = SecureIdGenerator();
    final sessionToken = '${tokenGenerator.nextId()}${tokenGenerator.nextId()}';
    try {
      if (studioEnabled) {
        if (studioAssetRoot case final assetRoot?) {
          final studio = DevExStudioServer(assetRoot: assetRoot);
          await studio.start(port: studioPort);
          _studio = studio;
        }
      }
      final allowedStudioOrigin =
          _studio?.origin ?? studioDevelopmentOrigin ?? headlessStudioOrigin!;
      final host = DevExHostApplication.fromResolvedPlan(
        studioOrigin: allowedStudioOrigin,
        sessionToken: sessionToken,
        workspaceRoot: workspaceRoot,
        launchProfiles: launchProfiles,
        catalog: catalog,
        plan: plan,
        gatewaySidecarCommand: gatewaySidecarCommand,
        gatewaySidecarArguments: gatewaySidecarArguments,
        gatewaySidecarWorkingDirectory: gatewaySidecarWorkingDirectory,
        rpcPort: hostPort,
        exposeStudioBootstrap: studioDevelopmentOrigin != null,
      );
      _host = host;
      await host.start();
      _studio?.configure(
        hostOrigin: host.rpc.httpUri,
        sessionToken: sessionToken,
        effectiveKitManifest: host.effectiveKitManifest,
      );
      _runtime = DevExDevelopmentRuntime(
        profileId: plan.profileId,
        planDigest: plan.digest,
        hostOrigin: host.rpc.httpUri,
        studioOrigin: _studio?.origin ?? studioDevelopmentOrigin,
        studioBootstrapUri: studioDevelopmentOrigin == null
            ? _studio?.origin.replace(path: '/devex/bootstrap.json')
            : host.rpc.httpUri.replace(path: '/devex/bootstrap.json'),
        effectiveKitManifest: host.effectiveKitManifest,
      );
      return runtime;
    } on Object {
      await close();
      rethrow;
    }
  }

  Future<void> close() async {
    _runtime = null;
    final host = _host;
    _host = null;
    final studio = _studio;
    _studio = null;
    Object? firstError;
    StackTrace? firstStack;
    try {
      await host?.close();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStack = stackTrace;
    }
    try {
      await studio?.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

bool _isLoopbackOrigin(Uri origin) =>
    origin.scheme == 'http' &&
    const <String>{'127.0.0.1', 'localhost', '::1'}.contains(origin.host) &&
    origin.userInfo.isEmpty &&
    (origin.path.isEmpty || origin.path == '/') &&
    !origin.hasQuery &&
    !origin.hasFragment;
