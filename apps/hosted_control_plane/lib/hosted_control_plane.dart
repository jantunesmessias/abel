import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'src/hosted_telemetry.dart';

export 'src/hosted_telemetry.dart';

abstract interface class HostedIdentityVerifier {
  Future<OidcIdentity> verifyBearerToken(String compactToken);
}

final class OidcHostedIdentityVerifier implements HostedIdentityVerifier {
  const OidcHostedIdentityVerifier(this._authenticator);

  final OidcPkceAuthenticator _authenticator;

  @override
  Future<OidcIdentity> verifyBearerToken(String compactToken) =>
      _authenticator.verifyBearerToken(compactToken);
}

abstract interface class HostedPrincipalDirectory {
  Future<String?> resolvePrincipal({
    required String tenantId,
    required Uri issuer,
    required String subject,
  });
}

final class PostgresHostedPrincipalDirectory
    implements HostedPrincipalDirectory {
  const PostgresHostedPrincipalDirectory(this._database);

  final SessionExecutor _database;

  @override
  Future<String?> resolvePrincipal({
    required String tenantId,
    required Uri issuer,
    required String subject,
  }) => _database.runTx((session) async {
    await session.execute(
      Sql.named(
        "SELECT set_config('control_plane.tenant_id', @tenant:text, true)",
      ),
      parameters: <String, Object?>{'tenant': tenantId},
    );
    final rows = await session.execute(
      Sql.named('''
        SELECT principal_id
        FROM control_plane.principals
        WHERE tenant_id = @tenant:text
          AND issuer = @issuer:text
          AND subject = @subject:text
      '''),
      parameters: <String, Object?>{
        'tenant': tenantId,
        'issuer': issuer.toString(),
        'subject': subject,
      },
    );
    return rows.isEmpty ? null : rows.single[0]! as String;
  });
}

final class HostedControlPlaneApplication {
  HostedControlPlaneApplication({
    required this._collaboration,
    required this._objectStore,
    required this._identities,
    required this._principals,
    required this._ids,
    required Set<String> allowedWebSocketOrigins,
    this._remoteScheduler,
    this._remoteTokenVerifier,
    this._remoteSessionTicketIssuer,
    this._remoteSessionGatewayOrigin,
    Clock? clock,
    this._telemetry = const NoopHostedTelemetry(),
  }) : _allowedWebSocketOrigins = Set<String>.unmodifiable(
         allowedWebSocketOrigins,
       ),
       _clock = clock ?? SystemClock() {
    final gateway = _remoteSessionGatewayOrigin;
    if (gateway != null &&
        (gateway.scheme != 'https' ||
            gateway.origin == 'null' ||
            gateway.userInfo.isNotEmpty ||
            gateway.query.isNotEmpty ||
            gateway.fragment.isNotEmpty)) {
      throw ArgumentError('remote session gateway must be an HTTPS origin');
    }
  }

  static const int _maximumRequestBytes = 1024 * 1024;
  final HostedCollaborationService _collaboration;
  final HostedObjectStore _objectStore;
  final HostedIdentityVerifier _identities;
  final HostedPrincipalDirectory _principals;
  final IdGenerator _ids;
  final Set<String> _allowedWebSocketOrigins;
  final RemoteSchedulerService? _remoteScheduler;
  final RemoteWorkerTokenVerifier? _remoteTokenVerifier;
  final RemoteSessionTicketIssuer? _remoteSessionTicketIssuer;
  final Uri? _remoteSessionGatewayOrigin;
  final Clock _clock;
  final HostedTelemetry _telemetry;

  Handler get handler {
    final router = Router()
      ..get('/healthz', _health)
      ..post('/v1/workspaces/<workspaceId>/push', _push)
      ..get('/v1/workspaces/<workspaceId>/events', _events)
      ..get('/v1/workspaces/<workspaceId>/stream', _stream)
      ..post('/v1/workspaces/<workspaceId>/presence', _heartbeat)
      ..get('/v1/workspaces/<workspaceId>/presence', _presence)
      ..post('/v1/workspaces/<workspaceId>/comments', _comment)
      ..post('/v1/workspaces/<workspaceId>/approvals', _approval)
      ..post('/v1/workspaces/<workspaceId>/publish', _publish)
      ..post('/v1/artifacts/upload-grants', _uploadGrant)
      ..post('/v1/remote/runs', _enqueueRemote)
      ..post('/v1/remote/runs/<runId>/cancel', _cancelRemote)
      ..post('/v1/remote/runs/<runId>/session-ticket', _remoteSessionTicket)
      ..post(
        '/v1/remote/tenants/<tenantId>/workers/<workerId>/runs/<runId>/state',
        _remoteState,
      )
      ..post(
        '/v1/remote/tenants/<tenantId>/workers/<workerId>/runs/<runId>/heartbeat',
        _remoteHeartbeat,
      )
      ..post(
        '/v1/remote/tenants/<tenantId>/workers/<workerId>/runs/<runId>/complete',
        _remoteComplete,
      )
      ..post(
        '/v1/remote/tenants/<tenantId>/workers/<workerId>/runs/<runId>/artifacts/download-grant',
        _remoteDownloadGrant,
      )
      ..post(
        '/v1/remote/tenants/<tenantId>/workers/<workerId>/runs/<runId>/artifacts/upload-grant',
        _remoteUploadGrant,
      )
      ..all('/<ignored|.*>', _notFound);
    return const Pipeline()
        .addMiddleware(_telemetry.middleware)
        .addMiddleware(logRequests(logger: _safeLog))
        .addHandler(router.call);
  }

  Response _health(Request request) => _json(200, <String, Object?>{
    'ok': true,
    'service': 'control-plane-control-plane',
  });

  Future<Response> _push(Request request, String workspaceId) =>
      _guard(request, (context) async {
        final document = await _jsonBody(request);
        final changeSet = WorkspaceChangeSet.fromJson(document);
        if (changeSet.workspaceId != workspaceId) {
          throw const FormatException('workspace path and payload differ');
        }
        final result = await _collaboration.push(context, changeSet);
        return switch (result) {
          final WorkspacePushAccepted accepted => _json(200, <String, Object?>{
            'ok': true,
            'replayed': accepted.replayed,
            'revision': accepted.revision.toJson(),
            'event': accepted.event.toJson(),
          }),
          final WorkspacePushRejected rejected => _json(409, <String, Object?>{
            'ok': false,
            'code': 'CONTROL_PLANE_CONFLICT',
            'conflict': rejected.conflict.toJson(),
          }),
        };
      });

  Future<Response> _events(Request request, String workspaceId) => _guard(
    request,
    (context) async {
      final after = int.tryParse(request.url.queryParameters['after'] ?? '0');
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '500');
      if (after == null || limit == null) {
        throw const FormatException('event cursor is invalid');
      }
      final events = await _collaboration.replay(
        context,
        workspaceId: workspaceId,
        afterSequence: after,
        limit: limit,
      );
      return _json(200, <String, Object?>{
        'ok': true,
        'events': <Object?>[for (final event in events) event.toJson()],
        'nextCursor': events.isEmpty ? after : events.last.sequence,
      });
    },
  );

  Future<Response> _stream(Request request, String workspaceId) =>
      _guard(request, (context) async {
        final after = int.tryParse(request.url.queryParameters['after'] ?? '0');
        if (after == null || after < 0) {
          throw const FormatException('event cursor is invalid');
        }
        final websocket = webSocketHandler(
          (channel, _) => _serveEventStream(
            channel,
            context: context,
            workspaceId: workspaceId,
            afterSequence: after,
          ),
          protocols: const <String>['workspace.collaboration.v1'],
          allowedOrigins: _allowedWebSocketOrigins,
          pingInterval: const Duration(seconds: 20),
        );
        return websocket(request);
      });

  void _serveEventStream(
    WebSocketChannel channel, {
    required HostedRequestContext context,
    required String workspaceId,
    required int afterSequence,
  }) {
    var cursor = afterSequence;
    var closed = false;
    final subscription = channel.stream.listen(
      (_) {},
      onDone: () => closed = true,
      onError: (_) => closed = true,
      cancelOnError: true,
    );
    unawaited(
      Future<void>(() async {
        try {
          while (!closed) {
            final events = await _collaboration.replay(
              context,
              workspaceId: workspaceId,
              afterSequence: cursor,
            );
            for (final event in events) {
              channel.sink.add(
                jsonEncode(<String, Object?>{
                  'jsonrpc': '2.0',
                  'method': 'collaboration.event',
                  'params': event.toJson(),
                }),
              );
              cursor = event.sequence;
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } on Object {
          await channel.sink.close(1011, 'stream failed');
        } finally {
          await subscription.cancel();
        }
      }),
    );
  }

  Future<Response> _heartbeat(Request request, String workspaceId) => _guard(
    request,
    (context) async {
      final json = await _jsonBody(request);
      final sessionId = _requiredString(json, 'sessionId');
      final lease = await _collaboration.heartbeat(
        context,
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      return _json(200, <String, Object?>{'ok': true, 'lease': lease.toJson()});
    },
  );

  Future<Response> _presence(Request request, String workspaceId) =>
      _guard(request, (context) async {
        final leases = await _collaboration.presence(
          context,
          workspaceId: workspaceId,
        );
        return _json(200, <String, Object?>{
          'ok': true,
          'leases': <Object?>[for (final lease in leases) lease.toJson()],
        });
      });

  Future<Response> _comment(Request request, String workspaceId) =>
      _guard(request, (context) async {
        final json = await _jsonBody(request);
        final thread = await _collaboration.comment(
          context,
          workspaceId: workspaceId,
          subjectDigest: Digest(_requiredString(json, 'subjectDigest')),
          body: _requiredString(json, 'body'),
        );
        return _json(201, <String, Object?>{
          'ok': true,
          'thread': thread.toJson(),
        });
      });

  Future<Response> _approval(Request request, String workspaceId) =>
      _guard(request, (context) async {
        final json = await _jsonBody(request);
        final approved = json['approved'];
        if (approved is! bool) {
          throw const FormatException('approved must be boolean');
        }
        final approval = await _collaboration.approve(
          context,
          workspaceId: workspaceId,
          subjectDigest: Digest(_requiredString(json, 'subjectDigest')),
          approved: approved,
        );
        return _json(201, <String, Object?>{
          'ok': true,
          'approval': approval.toJson(),
        });
      });

  Future<Response> _publish(Request request, String workspaceId) => _guard(
    request,
    (context) async {
      final json = await _jsonBody(request);
      final event = await _collaboration.publish(
        context,
        workspaceId: workspaceId,
        expectedDigest: Digest(_requiredString(json, 'expectedDigest')),
        release: Release.fromJson(
          json['release'],
          expectedDigest: Digest(_requiredString(json, 'releaseDigest')),
        ),
      );
      return _json(201, <String, Object?>{'ok': true, 'event': event.toJson()});
    },
  );

  Future<Response> _uploadGrant(Request request) =>
      _guard(request, (context) async {
        await _collaboration.authorize(context, HostedPermission.push);
        final json = await _jsonBody(request);
        final size = json['size'];
        if (size is! int) throw const FormatException('size must be integer');
        final transfer = await _objectStore.authorizeUpload(
          context,
          digest: Digest(_requiredString(json, 'digest')),
          size: size,
          mediaType: _requiredString(json, 'mediaType'),
          classification: _requiredString(json, 'classification'),
        );
        return _json(201, <String, Object?>{
          'ok': true,
          'transfer': transfer.toEphemeralJson(),
        });
      });

  Future<Response> _enqueueRemote(Request request) => _guard(request, (
    context,
  ) async {
    await _collaboration.authorize(context, HostedPermission.push);
    final scheduler = _requireRemoteScheduler();
    final json = await _jsonBody(request);
    final executionRequest = RemoteExecutionRequest.fromJson(json['request']);
    final run = await scheduler.enqueue(
      context,
      executionRequest,
      executionFingerprintDigest: Digest(
        _requiredString(json, 'executionFingerprintDigest'),
      ),
      containmentPolicyDigest: Digest(
        _requiredString(json, 'containmentPolicyDigest'),
      ),
      deviceImage: json['deviceImage'] == null
          ? null
          : DeviceImageDescriptor.fromJson(json['deviceImage']),
    );
    return _json(202, <String, Object?>{'ok': true, 'run': run.toJson()});
  });

  Future<Response> _cancelRemote(Request request, String runId) =>
      _guard(request, (context) async {
        final run = await _requireRemoteScheduler().cancel(context, runId);
        return _json(200, <String, Object?>{'ok': true, 'run': run.toJson()});
      });

  Future<Response> _remoteSessionTicket(Request request, String runId) =>
      _guard(request, (context) async {
        await _collaboration.authorize(context, HostedPermission.read);
        final scheduler = _requireRemoteScheduler();
        final issuer =
            _remoteSessionTicketIssuer ??
            (throw const RemoteStateException(
              'remote session tickets are not configured',
            ));
        final gateway =
            _remoteSessionGatewayOrigin ??
            (throw const RemoteStateException(
              'remote session gateway is not configured',
            ));
        final run = await scheduler.runForTenant(context.tenantId, runId);
        final plan = await scheduler.planForTenant(context.tenantId, runId);
        if (run.mode != RemoteRunMode.interactive ||
            plan.mode != RemoteRunMode.interactive ||
            run.state != RemoteRunState.running ||
            run.terminal) {
          throw const RemoteStateException(
            'remote interactive target is not available',
          );
        }
        final now = _clock.nowUtc();
        final requestedExpiry = now.add(const Duration(seconds: 60));
        final expiresAt = requestedExpiry.isBefore(plan.expiresAt)
            ? requestedExpiry
            : plan.expiresAt;
        if (!expiresAt.isAfter(now)) {
          throw const RemoteStateException('remote session plan has expired');
        }
        final transports = <RemoteInteractiveTransport>{
          plan.interactiveTransport,
        };
        final ticket = RemoteSessionTicket(
          tenantId: context.tenantId,
          runId: runId,
          principalId: context.principalId,
          role: RemoteSessionRole.viewer,
          allowedTransports: transports,
          issuedAt: now,
          expiresAt: expiresAt,
          nonce: _ids.nextId(),
        );
        final endpoint = gateway.replace(
          scheme: 'wss',
          pathSegments: <String>[
            ...gateway.pathSegments.where((segment) => segment.isNotEmpty),
            'v1',
            'sessions',
            runId,
            'viewer',
          ],
        );
        final grant = RemoteSessionGrant(
          runId: runId,
          endpoint: endpoint,
          compactTicket: await issuer.issueViewerTicket(ticket),
          allowedTransports: transports,
          expiresAt: expiresAt,
        );
        return _json(201, <String, Object?>{
          'ok': true,
          'session': grant.toEphemeralJson(),
        });
      });

  Future<Response> _remoteState(
    Request request,
    String tenantId,
    String workerId,
    String runId,
  ) => _workerGuard(
    request,
    tenantId,
    workerId,
    runId,
    <String>{'run:complete'},
    (scheduler, lease, _) async {
      final json = await _jsonBody(request);
      final name = _requiredString(json, 'state');
      final state = RemoteRunState.values
          .where((candidate) => candidate.name == name)
          .firstOrNull;
      if (state == null ||
          !const <RemoteRunState>{
            RemoteRunState.provisioning,
            RemoteRunState.running,
            RemoteRunState.uploading,
            RemoteRunState.failed,
          }.contains(state)) {
        throw const FormatException('worker state is invalid');
      }
      final run = await scheduler.transition(
        lease,
        state,
        failureCode: state == RemoteRunState.failed
            ? _requiredString(json, 'failureCode')
            : null,
      );
      return _json(200, <String, Object?>{'ok': true, 'run': run.toJson()});
    },
  );

  Future<Response> _remoteHeartbeat(
    Request request,
    String tenantId,
    String workerId,
    String runId,
  ) => _workerGuard(
    request,
    tenantId,
    workerId,
    runId,
    <String>{'run:heartbeat'},
    (scheduler, lease, _) async {
      final renewal = await scheduler.renew(lease);
      return _json(200, <String, Object?>{
        'ok': true,
        'lease': renewal.lease.toJson(),
        'capabilityToken': renewal.capabilityToken,
      });
    },
  );

  Future<Response> _remoteComplete(
    Request request,
    String tenantId,
    String workerId,
    String runId,
  ) => _workerGuard(
    request,
    tenantId,
    workerId,
    runId,
    <String>{'run:complete', 'artifact:write'},
    (scheduler, lease, _) async {
      final json = await _jsonBody(request);
      final artifacts = RemoteArtifactManifest.fromJson(json['artifacts']);
      if (json['interactiveTransport'] != artifacts.interactiveTransport.name) {
        throw const FormatException(
          'interactive transport differs from the artifact manifest',
        );
      }
      final containment = RemoteContainmentReport.fromJson(json['containment']);
      final plan = await scheduler.planForTenant(tenantId, runId);
      final expectedProfile = plan.target == RemoteTargetKind.androidEmulator
          ? 'android-kvm-minimal'
          : 'restricted';
      if (containment.namespace != remoteNamespaceFor(tenantId, runId) ||
          containment.serviceAccount != 'worker' ||
          containment.podSecurityProfile != expectedProfile ||
          !containment.allowedEndpointClasses.containsAll(const <String>{
            'gateway',
            'artifact',
            'control',
            'dns',
          }) ||
          containment.allowedEndpointClasses.length != 4) {
        throw const FormatException(
          'remote containment does not match the scheduled Job',
        );
      }
      final run = await scheduler.complete(
        lease,
        artifacts: artifacts,
        containment: containment,
      );
      return _json(200, <String, Object?>{'ok': true, 'run': run.toJson()});
    },
  );

  Future<Response> _remoteDownloadGrant(
    Request request,
    String tenantId,
    String workerId,
    String runId,
  ) => _workerGuard(
    request,
    tenantId,
    workerId,
    runId,
    <String>{'artifact:read'},
    (scheduler, lease, capability) async {
      final json = await _jsonBody(request);
      final digest = Digest(_requiredString(json, 'digest'));
      if (!capability.artifactDigests.contains(digest)) {
        throw const HostedAuthorizationException(
          'artifact is not present in the signed execution plan',
        );
      }
      final size = json['size'];
      if (size is! int) throw const FormatException('size must be integer');
      final descriptor = HostedBlobDescriptor(
        tenantId: tenantId,
        digest: digest,
        size: size,
        mediaType: _requiredString(json, 'mediaType'),
        classification: 'internal',
        objectKey:
            'tenants/$tenantId/blobs/sha256/${digest.value.substring(7)}',
      );
      final transfer = await _objectStore.authorizeDownload(
        HostedRequestContext(
          tenantId: tenantId,
          principalId: workerId,
          correlationId: capability.tokenId,
        ),
        descriptor,
      );
      return _json(200, <String, Object?>{
        'ok': true,
        'transfer': transfer.toEphemeralJson(),
      });
    },
  );

  Future<Response> _remoteUploadGrant(
    Request request,
    String tenantId,
    String workerId,
    String runId,
  ) => _workerGuard(
    request,
    tenantId,
    workerId,
    runId,
    <String>{'artifact:write'},
    (scheduler, lease, capability) async {
      final json = await _jsonBody(request);
      final size = json['size'];
      if (size is! int) throw const FormatException('size must be integer');
      final transfer = await _objectStore.authorizeUpload(
        HostedRequestContext(
          tenantId: tenantId,
          principalId: workerId,
          correlationId: capability.tokenId,
        ),
        digest: Digest(_requiredString(json, 'digest')),
        size: size,
        mediaType: _requiredString(json, 'mediaType'),
        classification: _requiredString(json, 'classification'),
      );
      return _json(200, <String, Object?>{
        'ok': true,
        'transfer': transfer.toEphemeralJson(),
      });
    },
  );

  RemoteSchedulerService _requireRemoteScheduler() =>
      _remoteScheduler ??
      (throw const RemoteStateException('remote runtime is not configured'));

  Future<Response> _workerGuard(
    Request request,
    String tenantId,
    String workerId,
    String runId,
    Set<String> scopes,
    Future<Response> Function(
      RemoteSchedulerService scheduler,
      RemoteLease lease,
      VerifiedRemoteCapability capability,
    )
    operation,
  ) async {
    try {
      final scheduler = _requireRemoteScheduler();
      final verifier =
          _remoteTokenVerifier ??
          (throw const RemoteStateException(
            'remote token verifier is not configured',
          ));
      final authorization = request.headers[HttpHeaders.authorizationHeader];
      if (authorization == null || !authorization.startsWith('Bearer ')) {
        throw const OidcAuthenticationException(
          'worker capability is required',
        );
      }
      final RemoteExecutionPlan plan;
      try {
        plan = await scheduler.planForTenant(tenantId, runId);
      } on Object {
        throw const OidcAuthenticationException('worker capability is invalid');
      }
      final capability = await verifier.verifyCapability(
        authorization.substring('Bearer '.length),
        plan: plan,
        workerId: workerId,
        requiredScopes: scopes,
      );
      final presentationTime = capability.expiresAt.subtract(
        const Duration(seconds: 1),
      );
      final lease = RemoteLease(
        tenantId: capability.tenantId,
        runId: capability.runId,
        workerId: capability.workerId,
        tokenId: capability.tokenId,
        generation: capability.generation,
        acquiredAt: presentationTime,
        heartbeatAt: presentationTime,
        expiresAt: capability.expiresAt,
      );
      return await operation(scheduler, lease, capability);
    } on OidcAuthenticationException catch (error) {
      return _error(401, 'AUTHENTICATION_INVALID', error.message);
    } on HostedAuthorizationException catch (error) {
      return _error(403, 'POLICY_DENIED', error.message);
    } on RemoteStateException catch (error) {
      return _error(409, 'REMOTE_STATE', error.message);
    } on FormatException catch (error) {
      return _error(400, 'INPUT_INVALID', error.message);
    }
  }

  Response _notFound(Request request, String ignored) =>
      _json(404, const <String, Object?>{'ok': false, 'code': 'NOT_FOUND'});

  Future<Response> _guard(
    Request request,
    Future<Response> Function(HostedRequestContext context) operation,
  ) async {
    try {
      return await operation(await _authenticate(request));
    } on OidcAuthenticationException catch (error) {
      return _error(401, 'AUTHENTICATION_INVALID', error.message);
    } on HostedAuthorizationException catch (error) {
      return _error(403, 'POLICY_DENIED', error.message);
    } on HostedIdempotencyException catch (error) {
      return _error(409, 'IDEMPOTENCY_CONFLICT', error.message);
    } on HostedConcurrencyException catch (error) {
      return _json(409, <String, Object?>{
        'ok': false,
        'code': 'CONTROL_PLANE_CONFLICT',
        'conflict': error.conflict.toJson(),
      });
    } on FormatException catch (error) {
      return _error(400, 'INPUT_INVALID', error.message);
    } on ArgumentError catch (error) {
      return _error(400, 'INPUT_INVALID', '$error');
    } on RemoteQuotaException catch (error) {
      return _error(429, 'REMOTE_QUOTA', error.message);
    } on RemoteStateException catch (error) {
      return _error(409, 'REMOTE_STATE', error.message);
    }
  }

  Future<HostedRequestContext> _authenticate(Request request) async {
    final authorization = request.headers[HttpHeaders.authorizationHeader];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const OidcAuthenticationException('bearer token is required');
    }
    final tenantId = request.headers['x-workspace-tenant'];
    if (tenantId == null || tenantId.isEmpty) {
      throw const OidcAuthenticationException('tenant header is required');
    }
    final identity = await _identities.verifyBearerToken(
      authorization.substring('Bearer '.length),
    );
    final principalId = await _principals.resolvePrincipal(
      tenantId: tenantId,
      issuer: identity.issuer,
      subject: identity.subject,
    );
    if (principalId == null) {
      throw const HostedAuthorizationException(
        'principal is not a tenant member',
      );
    }
    return HostedRequestContext(
      tenantId: tenantId,
      principalId: principalId,
      correlationId: request.headers['x-correlation-id'] ?? _ids.nextId(),
    );
  }

  Future<Map<String, Object?>> _jsonBody(Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > _maximumRequestBytes) {
        throw const FormatException('request exceeds 1 MiB');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('request body must be a JSON object');
    }
    return decoded;
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  Response _error(int status, String code, String message) => _json(
    status,
    <String, Object?>{'ok': false, 'code': code, 'message': message},
  );

  Response _json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: const <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  );

  void _safeLog(String message, bool isError) {
    if (isError) {
      Zone.current.print('hosted-control-plane error: $message');
    }
  }
}
