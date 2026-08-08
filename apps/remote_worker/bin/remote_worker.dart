import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:jose/jose.dart';
import 'package:remote_worker/remote_worker.dart';

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(r'^--([a-z-]+)=(.+)$').firstMatch(argument);
    if (match == null || options.containsKey(match.group(1)!)) {
      throw FormatException('invalid remote worker argument');
    }
    options[match.group(1)!] = match.group(2)!;
  }
  String option(String name) =>
      options[name] ?? (throw StateError('--$name is required'));
  String environment(String name) =>
      Platform.environment[name] ?? (throw StateError('$name is required'));
  String? optionalEnvironment(String name) {
    final value = Platform.environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  String secretFile(String path, int maximum) {
    final file = File(path);
    if (!file.existsSync() ||
        Link(path).existsSync() ||
        file.lengthSync() > maximum) {
      throw StateError('worker credential file is absent or oversized');
    }
    return file.readAsStringSync().trim();
  }

  final planToken = secretFile(option('plan-file'), 1024 * 1024);
  final capabilityToken = secretFile(option('capability-file'), 16384);
  final jwksDocument = jsonDecode(secretFile(option('jwks-file'), 1024 * 1024));
  if (jwksDocument is! Map<String, Object?>) {
    throw StateError('worker trust file is not a JWK set');
  }
  final clock = SystemClock();
  final verifier = RemoteWorkerTokenVerifier(
    trustedKeys: JsonWebKeySet.fromJson(jwksDocument),
    allowedAlgorithms:
        (Platform.environment['REMOTE_SESSION_ALGORITHMS'] ?? 'ES256')
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet(),
    clock: clock,
  );
  final client = RemoteWorkerHttpClient(
    controlOrigin: Uri.parse(environment('CONTROL_PLANE_ORIGIN')),
    artifactOrigin: Uri.parse(environment('ARTIFACT_ORIGIN')),
    capabilityToken: capabilityToken,
  );
  final configuredAndroidImage = optionalEnvironment('ANDROID_IMAGE_DIGEST');
  final streamEndpoint = optionalEnvironment('SESSION_GATEWAY_URL');
  final stream = streamEndpoint == null
      ? null
      : LoopbackRemoteWorkerStreamClient(Uri.parse(streamEndpoint));
  final scrcpyServerDigest = optionalEnvironment('SCRCPY_SERVER_DIGEST');
  final service = RemoteWorkerService(
    verifier: verifier,
    artifacts: client,
    control: client,
    backend: SystemRemoteWorkerBackend(
      SystemRemoteWorkerConfiguration(
        chromiumExecutable: optionalEnvironment('CHROMIUM_PATH'),
        androidSdkRoot: optionalEnvironment('ANDROID_SDK_ROOT'),
        androidAvdName: optionalEnvironment('ANDROID_AVD'),
        androidImageDigest: configuredAndroidImage == null
            ? null
            : Digest(configuredAndroidImage),
        gatewayPort: int.parse(optionalEnvironment('GATEWAY_PORT') ?? '8443'),
        webInteractivePort: int.parse(
          optionalEnvironment('REMOTE_WEB_INTERACTIVE_PORT') ?? '27184',
        ),
        scrcpyServerPath: optionalEnvironment('SCRCPY_SERVER_PATH'),
        scrcpyServerDigest: scrcpyServerDigest == null
            ? null
            : Digest(scrcpyServerDigest),
        scrcpyVersion: optionalEnvironment('SCRCPY_VERSION') ?? '4.0',
        scrcpyPort: int.parse(optionalEnvironment('SCRCPY_PORT') ?? '27185'),
      ),
    ),
    clock: clock,
    workspaceRoot: Directory('/work'),
    namespace: environment('REMOTE_WORKER_NAMESPACE'),
    serviceAccount: 'worker',
    stream: stream,
  );
  try {
    final outcome = await service.run(
      signedPlan: planToken,
      capabilityToken: capabilityToken,
      workerId: environment('REMOTE_WORKER_ID'),
    );
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': true,
        'artifactManifestDigest': outcome.artifacts.digest.value,
        'containmentReportDigest': outcome.containment.digest.value,
        'interactiveTransport': outcome.interactiveTransport.name,
      }),
    );
  } finally {
    client.close();
  }
}
