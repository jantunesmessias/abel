import 'package:experience_contracts/experience_contracts.dart';

import 'authoring_parser.dart';
import 'catalog_compiler.dart';

final class MotionManifestCompiler {
  const MotionManifestCompiler();

  bool hasAuthoring(Iterable<AuthoringDocument> source) =>
      source.any((document) => document.kind == AuthoringKind.motionSequence);

  MotionManifest compile(
    Iterable<AuthoringDocument> source, {
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
  }) {
    final documents = source
        .where((document) => document.kind == AuthoringKind.motionSequence)
        .toList(growable: false);
    final issues = <String>[];
    final sequences = <MotionSequenceManifest>[];
    final ids = <String>{};
    for (final document in documents) {
      if (document.schemaVersion != 2) {
        issues.add('${document.sourceName}: MotionSequence must use v2');
        continue;
      }
      if (!ids.add(document.id)) {
        issues.add(
          '${document.sourceName}: duplicate MotionSequence ${document.id}',
        );
        continue;
      }
      try {
        _only(document, const <String>{
          'projectionId',
          'title',
          'staticSummary',
          'steps',
        });
        final sequence = MotionSequenceManifest(
          id: document.id,
          projectionId: ExperienceProjectionId(
            _string(document, 'projectionId'),
          ),
          title: _string(document, 'title'),
          staticSummary: _string(document, 'staticSummary'),
          steps: _objects(document, 'steps').map((step) {
            _onlyMap(step, const <String>{
              'id',
              'transitionId',
              'fromNodeId',
              'toNodeId',
              'startMs',
              'fullDurationMs',
              'reducedDurationMs',
              'easing',
              'observations',
            }, 'steps[]');
            return MotionTransitionStep(
              id: _mapString(step, 'id', 'steps[]'),
              transitionId: TransitionId(
                _mapString(step, 'transitionId', 'steps[]'),
              ),
              fromNodeId: NodeInstanceId(
                _mapString(step, 'fromNodeId', 'steps[]'),
              ),
              toNodeId: NodeInstanceId(_mapString(step, 'toNodeId', 'steps[]')),
              startMs: _mapInteger(step, 'startMs', 'steps[]'),
              fullDurationMs: _mapInteger(step, 'fullDurationMs', 'steps[]'),
              reducedDurationMs: _mapInteger(
                step,
                'reducedDurationMs',
                'steps[]',
              ),
              easing: _enumValue(
                MotionEasing.values,
                _mapString(step, 'easing', 'steps[]'),
                'steps[].easing',
              ),
              observations: _mapObjects(step, 'observations', 'steps[]').map((
                observation,
              ) {
                _onlyMap(observation, const <String>{
                  'id',
                  'label',
                  'atFraction',
                  'kind',
                }, 'steps[].observations[]');
                return MotionObservation(
                  id: _mapString(observation, 'id', 'steps[].observations[]'),
                  label: _mapString(
                    observation,
                    'label',
                    'steps[].observations[]',
                  ),
                  atFraction: _mapNumber(
                    observation,
                    'atFraction',
                    'steps[].observations[]',
                  ),
                  kind: _enumValue(
                    MotionObservationKind.values,
                    _mapString(observation, 'kind', 'steps[].observations[]'),
                    'steps[].observations[].kind',
                  ),
                );
              }),
            );
          }),
        );
        sequences.add(sequence);
      } on ArgumentError catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      } on FormatException catch (error) {
        issues.add('${document.sourceName}: ${error.message}');
      }
    }
    if (issues.isNotEmpty) throw CatalogCompileException(issues);
    final manifest = MotionManifest(
      catalogDigest: catalog.digest,
      topologyDigest: topology.digest,
      sequences: sequences,
    );
    try {
      manifest.validateAgainst(catalog: catalog, topology: topology);
    } on ArgumentError catch (error) {
      throw CatalogCompileException(<String>[
        'motion-manifest: ${error.message}',
      ]);
    }
    return manifest;
  }
}

void _only(AuthoringDocument document, Set<String> allowed) =>
    _onlyMap(document.spec, allowed, 'spec');

void _onlyMap(Map<String, Object?> value, Set<String> allowed, String path) {
  final unknown = value.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _string(AuthoringDocument document, String key) =>
    _mapString(document.spec, key, 'spec');

String _mapString(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return result;
}

int _mapInteger(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! int) throw FormatException('$path.$key must be an integer');
  return result;
}

double _mapNumber(Map<String, Object?> value, String key, String path) {
  final result = value[key];
  if (result is! num || !result.toDouble().isFinite) {
    throw FormatException('$path.$key must be a finite number');
  }
  return result.toDouble();
}

Iterable<Map<String, Object?>> _objects(
  AuthoringDocument document,
  String key,
) => _mapObjects(document.spec, key, 'spec');

Iterable<Map<String, Object?>> _mapObjects(
  Map<String, Object?> value,
  String key,
  String path,
) {
  final raw = value[key];
  if (raw is! List<Object?> || raw.length > 10000) {
    throw FormatException('$path.$key must be a bounded array');
  }
  return raw.map((item) {
    if (item is! Map<Object?, Object?>) {
      throw FormatException('$path.$key entries must be objects');
    }
    final output = <String, Object?>{};
    for (final entry in item.entries) {
      if (entry.key is! String) {
        throw FormatException('$path.$key entry keys must be strings');
      }
      output[entry.key! as String] = entry.value;
    }
    return output;
  });
}

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unknown value');
}
