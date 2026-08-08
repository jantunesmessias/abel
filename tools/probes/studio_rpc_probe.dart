import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';

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
      'Usage: dart run tools/probes/studio_rpc_probe.dart <studio-origin> '
      '[--refresh] [--collect] [--bootstrap=<url>]',
    );
    exitCode = 64;
    return;
  }
  final studioOrigin = Uri.parse(arguments.first);
  final collect = flags.contains('--collect');
  final refresh = flags.contains('--refresh');
  final bootstrapUri = bootstrapOption == null
      ? studioOrigin.resolve('/studio/bootstrap.json')
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

    await call('workspace.initialize', <String, Object?>{
      'protocolVersion': 1,
      'sessionToken': token,
    });
    Map<String, Object?>? refreshResult;
    if (refresh) {
      final refreshed = _object(
        await call('workspace.refresh', const <String, Object?>{}),
        'WorkspaceRefresh',
      );
      _only(refreshed, const <String>{
        'schemaVersion',
        'kind',
        'status',
        'revision',
        'workspaceId',
        'catalogDigest',
        'variantManifestDigest',
        'effectiveKitManifestDigest',
        'snapshotDigest',
        'generatedAt',
        'changed',
      }, 'WorkspaceRefresh');
      if (refreshed['changed'] is! bool) {
        throw const FormatException('WorkspaceRefresh.changed must be boolean');
      }
      refreshResult = <String, Object?>{
        'revision': _integer(refreshed, 'revision', 'WorkspaceRefresh'),
        'catalogDigest': _digest(
          refreshed,
          'catalogDigest',
          'WorkspaceRefresh',
        ).value,
        'snapshotDigest': _digest(
          refreshed,
          'snapshotDigest',
          'WorkspaceRefresh',
        ).value,
        'changed': refreshed['changed'],
      };
    }
    Map<String, Object?>? collection;
    if (collect) {
      collection =
          await call('preview.collect', const <String, Object?>{
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
            await call('preview.status', <String, Object?>{
                  'operationId': collection['operationId'],
                })
                as Map<String, Object?>;
      }
    }
    final description =
        await call('workspace.describe', const <String, Object?>{})
            as Map<String, Object?>;
    final opened =
        await call('workspace.open', <String, Object?>{
              'expectedRevision': description['revision'],
            })
            as Map<String, Object?>;
    final handle = ResourceHandle.fromJson(opened['resource']);
    final bytes = await _readResource(
      client: client,
      handle: handle,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'application/json',
      expectedPurpose: 'workspace-snapshot',
      label: 'Workspace',
    );
    final snapshot = WorkspaceSnapshot.fromJson(jsonDecode(utf8.decode(bytes)));
    if (opened['revision'] != snapshot.revision ||
        opened['snapshotDigest'] != snapshot.digest.value ||
        description['revision'] != snapshot.revision ||
        description['snapshotDigest'] != snapshot.digest.value ||
        description['catalogDigest'] != snapshot.catalog.digest.value) {
      throw StateError('Workspace describe/open/resource identity mismatch');
    }
    if (refreshResult case final refreshed?) {
      if (refreshed['revision'] != snapshot.revision ||
          refreshed['snapshotDigest'] != snapshot.digest.value ||
          refreshed['catalogDigest'] != snapshot.catalog.digest.value) {
        throw StateError('Workspace refresh/resource identity mismatch');
      }
    }

    final experienceDescription = _object(
      await call('experience.describe', const <String, Object?>{}),
      'ExperienceDescription',
    );
    final experience = await _openAndValidateExperience(
      call: call,
      client: client,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      catalog: snapshot.catalog,
      description: experienceDescription,
    );
    final contentSet = await _openAndValidateContentSet(
      call: call,
      client: client,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      workspaceSnapshot: snapshot,
      experience: experience,
    );
    var validatedPngs = 0;
    for (final projection in snapshot.visualProjections) {
      final artifactHandle = projection.artifactHandle;
      if (artifactHandle == null) continue;
      await _readResource(
        client: client,
        handle: artifactHandle,
        hostOrigin: hostOrigin,
        studioOrigin: studioOrigin,
        expectedMediaType: 'image/png',
        expectedPurpose: artifactHandle.purpose,
        label: 'Visual artifact',
      );
      validatedPngs += 1;
    }
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'revision': snapshot.revision,
        'snapshotDigest': snapshot.digest.value,
        'workspaceContentDigest': snapshot.workspaceContentDigest.value,
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
        'experience': experience,
        'contentSet': contentSet,
        'refresh': ?refreshResult,
        'collection': ?collection,
      }),
    );
  } finally {
    await socket?.close();
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _openAndValidateContentSet({
  required _RpcCall call,
  required HttpClient client,
  required Uri hostOrigin,
  required Uri studioOrigin,
  required WorkspaceSnapshot workspaceSnapshot,
  required Map<String, Object?> experience,
}) async {
  final description = ExperienceContentSetDescription.fromJson(
    await call('experience.content.describe', const <String, Object?>{}),
  );
  final opened = ExperienceContentSetOpenResult.fromJson(
    await call('experience.content.open', <String, Object?>{
      'expectedRevision': description.identity.revision,
      'catalogDigest': description.identity.catalogDigest.value,
      'contentSetDigest': description.identity.contentSetDigest.value,
    }),
  );
  if (!_sameContentIdentity(description.identity, opened.identity)) {
    throw const FormatException(
      'Experience content-set describe/open identity mismatch',
    );
  }

  final snapshotBytes = await _readResource(
    client: client,
    handle: opened.workspaceSnapshot,
    hostOrigin: hostOrigin,
    studioOrigin: studioOrigin,
    expectedMediaType: 'application/json',
    expectedPurpose: 'workspace-snapshot',
    label: 'Atomic WorkspaceSnapshot',
  );
  final snapshot = WorkspaceSnapshot.fromJson(
    jsonDecode(utf8.decode(snapshotBytes)),
  );
  if (snapshot.digest != description.identity.workspaceSnapshotDigest ||
      snapshot.workspaceContentDigest !=
          description.identity.workspaceContentDigest ||
      snapshot.catalog.digest != description.identity.catalogDigest ||
      snapshot.digest != workspaceSnapshot.digest ||
      snapshot.workspaceContentDigest !=
          workspaceSnapshot.workspaceContentDigest) {
    throw const FormatException(
      'Atomic WorkspaceSnapshot differs from the advertised generation',
    );
  }

  final topologyHandle = opened.experienceTopologyBundle;
  final ExperienceTopologyBundle? topology;
  if (topologyHandle == null) {
    topology = null;
  } else {
    final bytes = await _readResource(
      client: client,
      handle: topologyHandle,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'application/json',
      expectedPurpose: 'experience-topology-bundle',
      label: 'Atomic ExperienceTopologyBundle',
    );
    topology = ExperienceTopologyBundle.fromJson(
      jsonDecode(utf8.decode(bytes)),
      catalog: snapshot.catalog,
    );
    if (topology.digest !=
            description.identity.experienceTopologyBundleDigest ||
        topology.digest.value != experience['bundleDigest']) {
      throw const FormatException(
        'Atomic ExperienceTopologyBundle differs from the advertised content',
      );
    }
  }

  final facetsHandle = opened.scenarioFacetManifest;
  final ScenarioFacetManifest? facets;
  if (facetsHandle == null) {
    facets = null;
  } else {
    final bytes = await _readResource(
      client: client,
      handle: facetsHandle,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'application/json',
      expectedPurpose: 'scenario-facet-manifest',
      label: 'Atomic ScenarioFacetManifest',
    );
    facets = ScenarioFacetManifest.fromJson(
      jsonDecode(utf8.decode(bytes)),
      catalog: snapshot.catalog,
    );
    if (facets.digest != description.identity.scenarioFacetManifestDigest) {
      throw const FormatException(
        'Atomic ScenarioFacetManifest differs from its identity',
      );
    }
  }

  final labHandle = opened.scenarioLabManifest;
  final ScenarioLabManifest? lab;
  if (labHandle == null) {
    lab = null;
  } else {
    final bytes = await _readResource(
      client: client,
      handle: labHandle,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'application/json',
      expectedPurpose: 'scenario-lab-manifest',
      label: 'Atomic ScenarioLabManifest',
    );
    lab = ScenarioLabManifest.fromJson(
      jsonDecode(utf8.decode(bytes)),
      catalog: snapshot.catalog,
    );
    if (lab.digest != description.identity.scenarioLabManifestDigest) {
      throw const FormatException(
        'Atomic ScenarioLabManifest differs from its identity',
      );
    }
  }

  final motionHandle = opened.motionManifest;
  final MotionManifest? motion;
  if (motionHandle == null) {
    motion = null;
  } else {
    final bytes = await _readResource(
      client: client,
      handle: motionHandle,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'application/json',
      expectedPurpose: 'motion-manifest',
      label: 'Atomic MotionManifest',
    );
    motion = MotionManifest.fromJson(
      jsonDecode(utf8.decode(bytes)),
      catalog: snapshot.catalog,
      topology:
          topology?.topology ??
          (throw const FormatException(
            'MotionManifest requires Experience topology',
          )),
    );
    if (motion.digest != description.identity.motionManifestDigest) {
      throw const FormatException(
        'Atomic MotionManifest differs from its identity',
      );
    }
  }

  return <String, Object?>{
    'revision': description.identity.revision,
    'catalogDigest': description.identity.catalogDigest.value,
    'workspaceSnapshotDigest':
        description.identity.workspaceSnapshotDigest.value,
    'workspaceContentDigest': description.identity.workspaceContentDigest.value,
    'experienceTopologyBundleDigest':
        description.identity.experienceTopologyBundleDigest?.value,
    'scenarioFacetManifestDigest':
        description.identity.scenarioFacetManifestDigest?.value,
    'scenarioLabManifestDigest':
        description.identity.scenarioLabManifestDigest?.value,
    'motionManifestDigest': description.identity.motionManifestDigest?.value,
    'contentSetDigest': description.identity.contentSetDigest.value,
    'describeOpenIdentityMatches': true,
    'workspaceMatches': snapshot.digest == workspaceSnapshot.digest,
    'experienceMatches': topology?.digest.value == experience['bundleDigest'],
    'resourcePurposes': <String>[
      opened.workspaceSnapshot.purpose,
      if (topologyHandle != null) topologyHandle.purpose,
      if (facetsHandle != null) facetsHandle.purpose,
      if (labHandle != null) labHandle.purpose,
      if (motionHandle != null) motionHandle.purpose,
    ],
    'labCardinalities': lab == null
        ? null
        : <String, Object?>{
            'plans': lab.plans.length,
            'scripts': lab.scripts.length,
            'requiredEvidence': lab.requiredEvidence.length,
            'comparisons': lab.comparisonBindings.length,
          },
    'facetCardinalities': facets == null
        ? null
        : <String, Object?>{
            'scenarioKinds': facets.scenarioKinds.length,
            'surfaces': facets.surfaces.length,
            'states': facets.states.length,
            'ownershipAreas': facets.ownershipAreas.length,
            'tags': facets.tags.length,
            'components': facets.components.length,
            'fixtures': facets.fixtures.length,
            'formFactors': facets.formFactors.length,
            'presentationFrames': facets.presentationFrames.length,
            'scenarioFacets': facets.scenarioFacets.length,
          },
    'scenarioFacets': facets == null
        ? const <Object?>[]
        : <Object?>[
            for (final facet in facets.scenarioFacets)
              <String, Object?>{
                'scenarioId': facet.scenarioId.value,
                'lifecycle': facet.lifecycle.name,
                'scenarioKindId': facet.scenarioKindId.value,
                'surfaceId': facet.surfaceId.value,
                'stateId': facet.stateId.value,
                'ownershipAreaId': facet.ownershipAreaId.value,
                'tagIds': facet.tagIds
                    .map((id) => id.value)
                    .toList(growable: false),
                'componentIds': facet.componentIds
                    .map((id) => id.value)
                    .toList(growable: false),
                'fixtureId': facet.fixtureId.value,
                'renderSourceKind': facet.renderSource.kind.name,
                'presentationFrameIds': facet.presentationFrameIds
                    .map((id) => id.value)
                    .toList(growable: false),
                'preferredPresentationFrameId':
                    facet.preferredPresentationFrameId.value,
              },
          ],
  };
}

bool _sameContentIdentity(
  ExperienceContentSetIdentity left,
  ExperienceContentSetIdentity right,
) =>
    left.revision == right.revision &&
    left.catalogDigest == right.catalogDigest &&
    left.workspaceSnapshotDigest == right.workspaceSnapshotDigest &&
    left.workspaceContentDigest == right.workspaceContentDigest &&
    left.experienceTopologyBundleDigest ==
        right.experienceTopologyBundleDigest &&
    left.scenarioFacetManifestDigest == right.scenarioFacetManifestDigest &&
    left.scenarioLabManifestDigest == right.scenarioLabManifestDigest &&
    left.motionManifestDigest == right.motionManifestDigest &&
    left.contentSetDigest == right.contentSetDigest;

typedef _RpcCall =
    Future<Object?> Function(String method, Map<String, Object?> params);

Future<Map<String, Object?>> _openAndValidateExperience({
  required _RpcCall call,
  required HttpClient client,
  required Uri hostOrigin,
  required Uri studioOrigin,
  required CatalogManifest catalog,
  required Map<String, Object?> description,
}) async {
  const baseKeys = <String>{
    'schemaVersion',
    'kind',
    'status',
    'revision',
    'catalogDigest',
  };
  const readyKeys = <String>{
    ...baseKeys,
    'topologyDigest',
    'layoutDigests',
    'bundleDigest',
  };
  if (description['schemaVersion'] != 1 ||
      description['kind'] != 'ExperienceDescription') {
    throw const FormatException(
      'Experience description has invalid schemaVersion or kind',
    );
  }
  final status = description['status'];
  if (status != 'ready' && status != 'absent') {
    throw const FormatException(
      'Experience description status must be ready or absent',
    );
  }
  _only(description, status == 'ready' ? readyKeys : baseKeys, 'Experience');
  final revision = _integer(description, 'revision', 'Experience');
  if (revision < 0) {
    throw const FormatException('Experience.revision must be non-negative');
  }
  final catalogDigest = _digest(description, 'catalogDigest', 'Experience');
  if (catalogDigest != catalog.digest) {
    throw const FormatException(
      'Experience description belongs to another CatalogManifest',
    );
  }
  if (status == 'absent') {
    return <String, Object?>{
      'status': 'absent',
      'revision': revision,
      'catalogDigest': catalogDigest.value,
      'topologyDigest': null,
      'bundleDigest': null,
      'layoutDigests': const <Object?>[],
      'cardinalities': const <String, Object?>{
        'boards': 0,
        'projections': 0,
        'nodeInstances': 0,
        'edgeInstances': 0,
        'layouts': 0,
        'nodeFrames': 0,
        'groups': 0,
        'lanes': 0,
        'annotations': 0,
      },
      'projections': const <Object?>[],
      'resource': null,
    };
  }

  final topologyDigest = _digest(description, 'topologyDigest', 'Experience');
  final bundleDigest = _digest(description, 'bundleDigest', 'Experience');
  final describedLayouts = _layoutDigests(description['layoutDigests']);
  final opened = _object(
    await call('experience.open', <String, Object?>{
      'expectedRevision': revision,
      'expectedBundleDigest': bundleDigest.value,
    }),
    'ExperienceOpen',
  );
  _only(opened, const <String>{
    'revision',
    'bundleDigest',
    'resource',
  }, 'ExperienceOpen');
  if (_integer(opened, 'revision', 'ExperienceOpen') != revision ||
      _digest(opened, 'bundleDigest', 'ExperienceOpen') != bundleDigest) {
    throw const FormatException('Experience describe/open identity mismatch');
  }
  final handle = ResourceHandle.fromJson(opened['resource']);
  final bytes = await _readResource(
    client: client,
    handle: handle,
    hostOrigin: hostOrigin,
    studioOrigin: studioOrigin,
    expectedMediaType: 'application/json',
    expectedPurpose: 'experience-topology-bundle',
    label: 'Experience topology bundle',
  );
  final bundle = ExperienceTopologyBundle.fromJson(
    jsonDecode(utf8.decode(bytes)),
    catalog: catalog,
  );
  if (bundle.catalogDigest != catalogDigest ||
      bundle.topology.catalogDigest != catalogDigest ||
      bundle.topology.digest != topologyDigest ||
      bundle.digest != bundleDigest) {
    throw const FormatException(
      'Experience bundle/catalog/topology digest mismatch',
    );
  }
  final actualLayouts = <String, Digest>{
    for (final layout in bundle.layouts)
      layout.projectionId.value: layout.digest,
  };
  if (actualLayouts.length != describedLayouts.length ||
      actualLayouts.entries.any(
        (entry) => describedLayouts[entry.key] != entry.value,
      )) {
    throw const FormatException(
      'Experience description/layout digest mismatch',
    );
  }

  final nodesByProjection = <ExperienceProjectionId, int>{};
  for (final node in bundle.topology.nodes) {
    nodesByProjection.update(
      node.projectionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final edgesByProjection = <ExperienceProjectionId, int>{};
  for (final edge in bundle.topology.edges) {
    edgesByProjection.update(
      edge.projectionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final layoutsByProjection =
      <ExperienceProjectionId, ProjectionLayoutManifest>{
        for (final layout in bundle.layouts) layout.projectionId: layout,
      };
  final projectionSummaries = <Object?>[
    for (final projection in bundle.topology.projections)
      <String, Object?>{
        'projectionId': projection.id.value,
        'kind': projection.kind.name,
        'journeyId': projection.journeyId?.value,
        'nodeInstances': nodesByProjection[projection.id] ?? 0,
        'edgeInstances': edgesByProjection[projection.id] ?? 0,
        'layoutDigest': layoutsByProjection[projection.id]?.digest.value,
        'nodeFrames':
            layoutsByProjection[projection.id]?.nodeFrames.length ?? 0,
        'groups': layoutsByProjection[projection.id]?.groups.length ?? 0,
        'lanes': layoutsByProjection[projection.id]?.lanes.length ?? 0,
        'annotations':
            layoutsByProjection[projection.id]?.annotations.length ?? 0,
      },
  ];
  final layoutDigests = <Object?>[
    for (final layout in bundle.layouts)
      <String, Object?>{
        'projectionId': layout.projectionId.value,
        'digest': layout.digest.value,
      },
  ];
  return <String, Object?>{
    'status': 'ready',
    'revision': revision,
    'catalogDigest': catalogDigest.value,
    'topologyDigest': topologyDigest.value,
    'bundleDigest': bundleDigest.value,
    'layoutDigests': layoutDigests,
    'cardinalities': <String, Object?>{
      'boards': bundle.topology.boards.length,
      'projections': bundle.topology.projections.length,
      'nodeInstances': bundle.topology.nodes.length,
      'edgeInstances': bundle.topology.edges.length,
      'layouts': bundle.layouts.length,
      'nodeFrames': bundle.layouts.fold<int>(
        0,
        (total, layout) => total + layout.nodeFrames.length,
      ),
      'groups': bundle.layouts.fold<int>(
        0,
        (total, layout) => total + layout.groups.length,
      ),
      'lanes': bundle.layouts.fold<int>(
        0,
        (total, layout) => total + layout.lanes.length,
      ),
      'annotations': bundle.layouts.fold<int>(
        0,
        (total, layout) => total + layout.annotations.length,
      ),
    },
    'projections': projectionSummaries,
    'resource': <String, Object?>{
      'origin': handle.uri.origin,
      'mediaType': handle.mediaType,
      'size': handle.size,
      'purpose': handle.purpose,
      'digest': handle.digest.value,
    },
  };
}

Future<Uint8List> _readResource({
  required HttpClient client,
  required ResourceHandle handle,
  required Uri hostOrigin,
  required Uri studioOrigin,
  required String expectedMediaType,
  required String expectedPurpose,
  required String label,
}) async {
  if (handle.uri.origin != hostOrigin.origin ||
      handle.mediaType != expectedMediaType ||
      handle.purpose != expectedPurpose ||
      handle.isExpiredAt(DateTime.now().toUtc())) {
    throw StateError('$label ResourceHandle was rejected');
  }
  final request = await client.getUrl(handle.uri);
  request.headers.set('Origin', studioOrigin.origin);
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok ||
      response.headers.contentType?.mimeType != expectedMediaType ||
      response.contentLength != handle.size ||
      response.headers.value('access-control-allow-origin') !=
          studioOrigin.origin ||
      response.headers.value('x-content-type-options') != 'nosniff') {
    await response.drain<void>();
    throw StateError('$label resource metadata was rejected');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    if (builder.length + chunk.length > handle.size) {
      throw StateError('$label resource exceeded its declared length');
    }
    builder.add(chunk);
  }
  final bytes = builder.takeBytes();
  if (bytes.length != handle.size || Digest.bytes(bytes) != handle.digest) {
    throw StateError('$label resource bytes were rejected');
  }
  return bytes;
}

Map<String, Digest> _layoutDigests(Object? value) {
  if (value is! List<Object?> || value.length > 50000) {
    throw const FormatException(
      'Experience.layoutDigests must be a bounded array',
    );
  }
  final result = <String, Digest>{};
  var previousId = '';
  for (var index = 0; index < value.length; index += 1) {
    final item = _object(value[index], 'Experience.layoutDigests[$index]');
    _only(item, const <String>{
      'projectionId',
      'digest',
    }, 'Experience.layoutDigests[$index]');
    final projectionId = item['projectionId'];
    if (projectionId is! String) {
      throw FormatException(
        'Experience.layoutDigests[$index].projectionId must be a string',
      );
    }
    ExperienceProjectionId(projectionId);
    final digest = _digest(item, 'digest', 'Experience.layoutDigests[$index]');
    if (projectionId.compareTo(previousId) <= 0 ||
        result.putIfAbsent(projectionId, () => digest) != digest) {
      throw const FormatException(
        'Experience.layoutDigests must be sorted and unique',
      );
    }
    previousId = projectionId;
  }
  return result;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _only(Map<String, Object?> value, Set<String> allowed, String path) {
  final unknown = value.keys.toSet().difference(allowed);
  final missing = allowed.difference(value.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw FormatException(
      '$path keys mismatch; unknown=${unknown.join(',')}, '
      'missing=${missing.join(',')}',
    );
  }
}

int _integer(Map<String, Object?> value, String key, String path) {
  final item = value[key];
  if (item is! int) throw FormatException('$path.$key must be an integer');
  return item;
}

Digest _digest(Map<String, Object?> value, String key, String path) {
  final item = value[key];
  if (item is! String) throw FormatException('$path.$key must be a digest');
  return Digest(item);
}
