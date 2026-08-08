import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';

Future<void> main(List<String> arguments) async {
  final options = arguments.skip(1).toList(growable: false);
  final flags = options
      .where((item) => !item.startsWith('--bootstrap='))
      .toSet();
  final bootstrapOption = options
      .where((item) => item.startsWith('--bootstrap='))
      .map((item) => item.substring('--bootstrap='.length))
      .firstOrNull;
  if (arguments.isEmpty ||
      flags.difference(const <String>{'--collect', '--refresh'}).isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/studio_rpc_probe.dart <studio-origin> '
      '[--refresh] [--collect] [--bootstrap=<url>]',
    );
    exitCode = 64;
    return;
  }
  final studioOrigin = Uri.parse(arguments.first);
  final collect = flags.contains('--collect');
  final refresh = flags.contains('--refresh');
  final bootstrapUri = bootstrapOption == null
      ? studioOrigin.resolve('/devex/bootstrap.json')
      : Uri.parse(bootstrapOption);
  final client = HttpClient();
  WebSocket? socket;
  try {
    final request = await client.getUrl(bootstrapUri);
    if (bootstrapUri.origin == studioOrigin.origin) {
      request.headers.set('sec-fetch-site', 'same-origin');
    } else {
      request.headers.set('Origin', studioOrigin.origin);
    }
    final response = await request.close();
    final bootstrap = jsonDecode(await utf8.decoder.bind(response).join());
    if (response.statusCode != 200 || bootstrap is! Map<String, Object?>) {
      throw StateError('Studio bootstrap was unavailable');
    }
    final hostOrigin = Uri.parse(bootstrap['hostOrigin']! as String);
    final token = bootstrap['sessionToken']! as String;
    socket = await WebSocket.connect(
      hostOrigin.replace(scheme: 'ws', path: '/rpc').toString(),
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    final connectedSocket = socket;
    final messages = StreamIterator<Object?>(connectedSocket);
    var id = 0;
    Future<Object?> call(String method, Map<String, Object?> params) async {
      final requestId = 'probe-${id++}';
      connectedSocket.add(
        JsonRpcRequest(method: method, id: requestId, params: params).encode(),
      );
      while (await messages.moveNext()) {
        final raw = messages.current;
        if (raw is! String) continue;
        final message = const JsonRpcCodec().decode(raw);
        if (message is JsonRpcResponse && message.id == requestId) {
          if (!message.isSuccess) {
            throw StateError(message.error!.message);
          }
          return message.result;
        }
      }
      throw StateError('Host closed the RPC connection');
    }

    await call('devex.initialize', <String, Object?>{
      'protocolVersion': 1,
      'sessionToken': token,
    });
    if (refresh) {
      await call('devex.workspace.refresh', const <String, Object?>{});
    }
    Map<String, Object?>? collection;
    if (collect) {
      collection =
          await call('devex.preview.collect', const <String, Object?>{
                'applicationId': 'sample',
                'syntheticDataConfirmed': true,
              })
              as Map<String, Object?>;
      const terminal = <String>{
        'cancelled',
        'completed',
        'completedWithFailures',
        'failed',
      };
      while (!terminal.contains(collection!['state'])) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        collection =
            await call('devex.preview.status', <String, Object?>{
                  'operationId': collection['operationId'],
                })
                as Map<String, Object?>;
      }
    }
    final description =
        await call('devex.workspace.describe', const <String, Object?>{})
            as Map<String, Object?>;
    final opened =
        await call('devex.workspace.open', <String, Object?>{
              'expectedRevision': description['revision'],
            })
            as Map<String, Object?>;
    final handle = ResourceHandle.fromJson(opened['resource']);
    final resourceRequest = await client.getUrl(handle.uri);
    resourceRequest.headers.set('Origin', studioOrigin.origin);
    final resourceResponse = await resourceRequest.close();
    final bytes = await resourceResponse.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (resourceResponse.statusCode != 200 ||
        Digest.bytes(bytes) != handle.digest) {
      throw StateError('Workspace resource was rejected');
    }
    final snapshot = WorkspaceSnapshot.fromJson(jsonDecode(utf8.decode(bytes)));
    var validatedPngs = 0;
    for (final projection in snapshot.visualProjections) {
      final artifactHandle = projection.artifactHandle;
      if (artifactHandle == null) continue;
      final artifactRequest = await client.getUrl(artifactHandle.uri);
      artifactRequest.headers.set('Origin', studioOrigin.origin);
      final artifactResponse = await artifactRequest.close();
      final artifactBytes = await artifactResponse.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (artifactResponse.statusCode != 200 ||
          artifactResponse.headers.contentType?.mimeType != 'image/png' ||
          Digest.bytes(artifactBytes) != artifactHandle.digest) {
        throw StateError('Visual artifact resource was rejected');
      }
      validatedPngs += 1;
    }
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'revision': snapshot.revision,
        'snapshotDigest': snapshot.digest.value,
        'applications': snapshot.catalog.applications.length,
        'journeys': snapshot.catalog.journeys.length,
        'scenarios': snapshot.catalog.scenarios.length,
        'variants': snapshot.variantManifest.variants.length,
        'providers': snapshot.providers
            .map((item) => item.providerId.value)
            .toList(growable: false),
        'visualProjections': snapshot.visualProjections.length,
        'validatedPngs': validatedPngs,
        'projectionStates': snapshot.visualProjections
            .map(
              (item) => <String, Object?>{
                'scenarioId': item.scenarioId?.value,
                'variantId': item.variantId?.value,
                'status': item.status.name,
                'freshness': item.freshness.name,
                'fidelity': item.fidelity?.name,
                'executionFingerprintDigest':
                    item.executionFingerprintDigest?.value,
                'capturePolicyId': item.capturePolicyId,
                'hasArtifactHandle': item.artifactHandle != null,
              },
            )
            .toList(growable: false),
        'collected': snapshot.visualProjections
            .where((item) => item.status == VisualEvidenceStatus.collected)
            .length,
        'fresh': snapshot.visualProjections
            .where((item) => item.freshness == EvidenceFreshness.fresh)
            .length,
        'stale': snapshot.visualProjections
            .where((item) => item.freshness == EvidenceFreshness.stale)
            .length,
        'rpcMethods': snapshot.effectiveKitManifest.rpcMethods,
        'collection': ?collection,
      }),
    );
  } finally {
    await socket?.close();
    client.close(force: true);
  }
}
