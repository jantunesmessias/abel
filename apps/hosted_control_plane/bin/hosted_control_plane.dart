import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_hosted_control_plane/hosted_control_plane.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:jose/jose.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final environment = Platform.environment;
  String requiredValue(String key) {
    final value = environment[key];
    if (value == null || value.isEmpty) {
      throw StateError('$key is required');
    }
    return value;
  }

  final database = Pool<String>.withUrl(requiredValue('DATABASE_URL'));
  final remoteEnabled = environment['DEVEX_REMOTE_ENABLED'] == 'true';
  Pool<String>? schedulerDatabase;
  RemoteSchedulerService? remoteScheduler;
  RemoteWorkerTokenVerifier? remoteVerifier;
  RemoteSessionTicketIssuer? remoteSessionTickets;
  Uri? remoteSessionGatewayOrigin;
  KubernetesApiRemoteJobLauncher? remoteLauncher;
  Timer? remoteDispatchTimer;
  if (remoteEnabled) {
    schedulerDatabase = Pool<String>.withUrl(
      requiredValue('SCHEDULER_DATABASE_URL'),
    );
    final privateJwkFile = File(requiredValue('REMOTE_SIGNING_JWK_FILE'));
    final keyDocument = jsonDecode(privateJwkFile.readAsStringSync());
    if (keyDocument is! Map<String, Object?>) {
      throw StateError('REMOTE_SIGNING_JWK_FILE is not a JWK object');
    }
    final signingKey = JsonWebKey.fromJson(keyDocument);
    final keyId = requiredValue('REMOTE_SIGNING_KEY_ID');
    final algorithm = environment['REMOTE_SIGNING_ALGORITHM'] ?? 'ES256';
    final androidImage = DeviceImageDescriptor(
      id: requiredValue('REMOTE_ANDROID_IMAGE_ID'),
      imageDigest: Digest(requiredValue('REMOTE_ANDROID_IMAGE_DIGEST')),
      apiLevel: int.parse(requiredValue('REMOTE_ANDROID_API_LEVEL')),
      abi: requiredValue('REMOTE_ANDROID_ABI'),
      renderer: requiredValue('REMOTE_ANDROID_RENDERER'),
      kvmRequired: true,
    );
    final publicKey = JsonWebKey.fromCryptoKeys(
      publicKey: signingKey.cryptoKeyPair.publicKey,
    );
    final trustedJwksJson = jsonEncode(<String, Object?>{
      'keys': <Object?>[
        <String, Object?>{...publicKey.toJson(), 'kid': keyId},
      ],
    });
    final security = JoseRemoteExecutionSecurity(
      signingKey: signingKey,
      keyId: keyId,
      algorithm: algorithm,
    );
    remoteSessionTickets = security;
    remoteSessionGatewayOrigin = Uri.parse(
      requiredValue('DEVEX_GATEWAY_ORIGIN'),
    );
    remoteVerifier = RemoteWorkerTokenVerifier(
      trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
        'keys': <Object?>[
          <String, Object?>{...publicKey.toJson(), 'kid': keyId},
        ],
      }),
      allowedAlgorithms: <String>{algorithm},
      clock: SystemClock(),
    );
    remoteScheduler = RemoteSchedulerService(
      repository: PostgresRemoteSchedulerRepository(
        tenantDatabase: database,
        schedulerDatabase: schedulerDatabase,
      ),
      quotas: const StaticRemoteQuotaPolicy(),
      signer: security,
      capabilities: security,
      clock: SystemClock(),
      ids: SecureIdGenerator(),
      deviceImages: StaticRemoteDeviceImagePolicy(<DeviceImageDescriptor>{
        androidImage,
      }),
    );
    final tokenFile = File(requiredValue('KUBERNETES_API_TOKEN_FILE'));
    final tokenSource = RotatingKubernetesBearerTokenFile(
      file: tokenFile,
      trustedRoot: tokenFile.parent,
    );
    remoteLauncher = KubernetesApiRemoteJobLauncher(
      apiServer: Uri.parse(requiredValue('KUBERNETES_API_SERVER')),
      bearerTokenProvider: tokenSource.read,
    );
    final dispatcher = RemoteKubernetesDispatcher(
      scheduler: remoteScheduler,
      builder: KubernetesRemoteJobBuilder(
        KubernetesRemoteJobConfiguration(
          webWorkerImage: requiredValue('REMOTE_WEB_WORKER_IMAGE'),
          androidWorkerImage: requiredValue('REMOTE_ANDROID_WORKER_IMAGE'),
          controlPlaneOrigin: Uri.parse(
            requiredValue('DEVEX_CONTROL_PLANE_ORIGIN'),
          ),
          artifactOrigin: Uri.parse(requiredValue('S3_ENDPOINT')),
          gatewayOrigin: Uri.parse(requiredValue('DEVEX_GATEWAY_ORIGIN')),
          trustedJwksJson: trustedJwksJson,
          androidImageDigest: androidImage.imageDigest,
          androidScrcpyServerDigest: Digest(
            requiredValue('REMOTE_ANDROID_SCRCPY_SERVER_DIGEST'),
          ),
          allowedStudioOrigins:
              (environment['DEVEX_ALLOWED_STUDIO_ORIGINS'] ?? '')
                  .split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false),
          allowedEgressCidrs: requiredValue('REMOTE_ALLOWED_EGRESS_CIDRS')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
          chromiumExecutable:
              environment['REMOTE_CHROMIUM_PATH'] ?? '/usr/bin/chromium',
          androidSdkRoot:
              environment['REMOTE_ANDROID_SDK_ROOT'] ?? '/opt/android-sdk',
          androidAvdName: environment['REMOTE_ANDROID_AVD'] ?? 'devex-api-35',
          androidScrcpyServerPath:
              environment['REMOTE_ANDROID_SCRCPY_SERVER_PATH'] ??
              '/opt/scrcpy/scrcpy-server.jar',
          androidScrcpyVersion:
              environment['REMOTE_ANDROID_SCRCPY_VERSION'] ?? '4.0',
          gatewayPort: int.parse(environment['REMOTE_GATEWAY_PORT'] ?? '8443'),
          sessionGatewayName:
              environment['REMOTE_SESSION_GATEWAY_NAME'] ?? 'devex-public',
          sessionGatewayNamespace:
              environment['REMOTE_SESSION_GATEWAY_NAMESPACE'] ?? 'devex-system',
        ),
      ),
      launcher: remoteLauncher,
      clock: SystemClock(),
      webCapacity: int.parse(environment['REMOTE_WEB_CAPACITY'] ?? '4'),
      androidCapacity: int.parse(environment['REMOTE_ANDROID_CAPACITY'] ?? '1'),
    );
    final cleanupReconciler = RemoteCleanupReconciler(
      scheduler: remoteScheduler,
      launcher: remoteLauncher,
    );
    var dispatching = false;
    remoteDispatchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (dispatching) return;
      dispatching = true;
      unawaited(
        Future<void>(() async {
          try {
            await remoteScheduler!.reapExpiredLeases();
            await cleanupReconciler.reconcileOnce();
            await dispatcher.dispatchOnce();
          } on Object {
            stderr.writeln('remote scheduler iteration failed');
          } finally {
            dispatching = false;
          }
        }),
      );
    });
  }
  final issuer = Uri.parse(requiredValue('OIDC_ISSUER'));
  final authorizationEndpoint = Uri.parse(
    requiredValue('OIDC_AUTHORIZATION_ENDPOINT'),
  );
  final tokenEndpoint = Uri.parse(requiredValue('OIDC_TOKEN_ENDPOINT'));
  final jwksUri = Uri.parse(requiredValue('OIDC_JWKS_URI'));
  final oidc = OidcPkceAuthenticator(
    configuration: OidcConfiguration(
      issuer: issuer,
      authorizationEndpoint: authorizationEndpoint,
      tokenEndpoint: tokenEndpoint,
      jwksUri: jwksUri,
      clientId: requiredValue('OIDC_CLIENT_ID'),
      allowedAlgorithms: (environment['OIDC_ALLOWED_ALGORITHMS'] ?? 'RS256')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet(),
    ),
    transport: DartIoOidcHttpTransport(
      allowedOrigins: <String>{tokenEndpoint.origin, jwksUri.origin},
    ),
    clock: SystemClock(),
  );
  final objectStore = S3CompatibleObjectStore(
    configuration: S3ObjectStoreConfiguration(
      endpoint: Uri.parse(requiredValue('S3_ENDPOINT')),
      bucket: requiredValue('S3_BUCKET'),
      region: requiredValue('S3_REGION'),
      credentials: S3Credentials(
        accessKeyId: requiredValue('S3_ACCESS_KEY_ID'),
        secretAccessKey: requiredValue('S3_SECRET_ACCESS_KEY'),
        sessionToken: environment['S3_SESSION_TOKEN'],
      ),
    ),
    clock: SystemClock(),
  );
  final telemetryEndpoint = environment['OTEL_EXPORTER_OTLP_ENDPOINT'];
  final HostedTelemetry telemetry =
      telemetryEndpoint == null || telemetryEndpoint.isEmpty
      ? const NoopHostedTelemetry()
      : OpenTelemetryHostedTelemetry(
          collectorEndpoint: Uri.parse(telemetryEndpoint),
          serviceVersion: environment['DEVEX_SERVICE_VERSION'] ?? '0.1.0-dev',
          deploymentEnvironment:
              environment['DEVEX_DEPLOYMENT_ENVIRONMENT'] ?? 'development',
        );
  final application = HostedControlPlaneApplication(
    collaboration: HostedCollaborationService(
      repository: PostgresHostedCollaborationRepository(database),
      clock: SystemClock(),
      ids: SecureIdGenerator(),
    ),
    objectStore: objectStore,
    identities: OidcHostedIdentityVerifier(oidc),
    principals: PostgresHostedPrincipalDirectory(database),
    ids: SecureIdGenerator(),
    allowedWebSocketOrigins: (environment['DEVEX_ALLOWED_STUDIO_ORIGINS'] ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet(),
    remoteScheduler: remoteScheduler,
    remoteTokenVerifier: remoteVerifier,
    remoteSessionTicketIssuer: remoteSessionTickets,
    remoteSessionGatewayOrigin: remoteSessionGatewayOrigin,
    clock: SystemClock(),
    telemetry: telemetry,
  );
  final port = int.tryParse(environment['PORT'] ?? '8080');
  if (port == null || port < 1 || port > 65535) {
    throw StateError('PORT is invalid');
  }
  final server = await shelf_io.serve(
    application.handler,
    InternetAddress.anyIPv4,
    port,
    poweredByHeader: null,
  );
  stdout.writeln('devex hosted control plane listening on ${server.port}');

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> term;
  late final StreamSubscription<ProcessSignal> interrupt;
  Future<void> stop(ProcessSignal _) async {
    if (stopping.isCompleted) return;
    await server.close(force: false);
    remoteDispatchTimer?.cancel();
    remoteLauncher?.close();
    await telemetry.shutdown();
    await schedulerDatabase?.close();
    await database.close();
    stopping.complete();
  }

  term = ProcessSignal.sigterm.watch().listen(stop);
  interrupt = ProcessSignal.sigint.watch().listen(stop);
  await stopping.future;
  await term.cancel();
  await interrupt.cancel();
}
