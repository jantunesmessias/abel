import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final options = _Options.parse(arguments);
  final root = Directory(options.output).absolute;
  if (root.existsSync() || Link(root.path).existsSync()) {
    throw FileSystemException('Scale corpus output already exists', root.path);
  }
  if (!root.parent.existsSync() || Link(root.parent.path).existsSync()) {
    throw FileSystemException(
      'Scale corpus output parent is missing or linked',
      root.parent.path,
    );
  }
  root.createSync();
  final content = Directory(p.join(root.path, '.experience'))..createSync();
  File(p.join(root.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace:
  id: scale-workspace
  displayName: Deterministic scale workspace
applications:
  scale:
    root: .
    target: web
    displayName: Scale application
kit:
  profile: journey-preview
  modules: {}
  providerBindings: []
  startupPolicy: fail-required-v1
''');

  for (var index = 0; index < options.scenarioCount; index += 1) {
    final id = _id('scenario', index);
    _writeDocument(
      content,
      p.join('scenarios', _partition(index), '$id.json'),
      <String, Object?>{
        'schemaVersion': 1,
        'kind': 'Scenario',
        'metadata': <String, Object?>{'id': id},
        'spec': <String, Object?>{
          'applicationId': 'scale',
          'title': 'Scale scenario ${index.toString().padLeft(5, '0')}',
          'description': 'Deterministic synthetic descriptor $id.',
          'sourceReferences': <Object?>[
            <String, Object?>{
              'repository': 'scale-source',
              'path': 'lib/group-${index ~/ 8}/scenario.dart',
              'symbol': 'scenario$index',
            },
          ],
        },
      },
    );
  }

  for (var index = 0; index < options.transitionCount; index += 1) {
    final endpoints = _endpoints(index, options.scenarioCount);
    final id = _id('transition', index);
    _writeDocument(
      content,
      p.join('transitions', _partition(index), '$id.json'),
      <String, Object?>{
        'schemaVersion': 1,
        'kind': 'Transition',
        'metadata': <String, Object?>{'id': id},
        'spec': <String, Object?>{
          'journeyId': 'scale-journey',
          'from': _id('scenario', endpoints.$1),
          'to': _id('scenario', endpoints.$2),
          'label': 'Synthetic transition ${index.toString().padLeft(5, '0')}',
        },
      },
    );
  }

  _writeDocument(content, 'journey.json', <String, Object?>{
    'schemaVersion': 1,
    'kind': 'Journey',
    'metadata': <String, Object?>{'id': 'scale-journey'},
    'spec': <String, Object?>{
      'applicationId': 'scale',
      'title': 'Deterministic nonlinear scale journey',
      'scenarioIds': <String>[
        for (var index = 0; index < options.scenarioCount; index += 1)
          _id('scenario', index),
      ],
    },
  });
  _writeDocument(content, p.join('topology', 'board.json'), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'Board',
    'metadata': <String, Object?>{'id': 'scale-board'},
    'spec': <String, Object?>{
      'applicationId': 'scale',
      'title': 'Scale board',
      'projectionIds': const <String>['scale-journey'],
    },
  });

  for (var index = 0; index < options.scenarioCount; index += 1) {
    final id = _id('node', index);
    _writeDocument(
      content,
      p.join('topology', 'nodes', _partition(index), '$id.json'),
      <String, Object?>{
        'schemaVersion': 2,
        'kind': 'NodeInstance',
        'metadata': <String, Object?>{'id': id},
        'spec': <String, Object?>{
          'projectionId': 'scale-journey',
          'scenarioId': _id('scenario', index),
        },
      },
    );
  }
  for (var index = 0; index < options.edgeCount; index += 1) {
    final endpoints = _endpoints(index, options.scenarioCount);
    final id = _id('edge', index);
    _writeDocument(
      content,
      p.join('topology', 'edges', _partition(index), '$id.json'),
      <String, Object?>{
        'schemaVersion': 2,
        'kind': 'EdgeInstance',
        'metadata': <String, Object?>{'id': id},
        'spec': <String, Object?>{
          'projectionId': 'scale-journey',
          'transitionId': _id('transition', index),
          'fromNodeId': _id('node', endpoints.$1),
          'toNodeId': _id('node', endpoints.$2),
        },
      },
    );
  }

  _writeDocument(
    content,
    p.join('topology', 'projection.json'),
    <String, Object?>{
      'schemaVersion': 2,
      'kind': 'ExperienceProjection',
      'metadata': <String, Object?>{'id': 'scale-journey'},
      'spec': <String, Object?>{
        'boardId': 'scale-board',
        'applicationId': 'scale',
        'title': 'Scale journey projection',
        'projectionKind': 'journey',
        'journeyId': 'scale-journey',
        'nodeInstanceIds': <String>[
          for (var index = 0; index < options.scenarioCount; index += 1)
            _id('node', index),
        ],
        'edgeInstanceIds': <String>[
          for (var index = 0; index < options.edgeCount; index += 1)
            _id('edge', index),
        ],
      },
    },
  );
  _writeDocument(content, p.join('topology', 'layout.json'), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'ProjectionLayout',
    'metadata': <String, Object?>{'id': 'scale-journey'},
    'spec': <String, Object?>{
      'projectionId': 'scale-journey',
      'nodeFrames': <Object?>[
        for (var index = 0; index < options.scenarioCount; index += 1)
          <String, Object?>{
            'nodeInstanceId': _id('node', index),
            'x': (index % 50) * 260,
            'y': (index ~/ 50) * 180,
            'width': 220,
            'height': 120,
          },
      ],
      'groups': const <Object?>[],
      'lanes': const <Object?>[],
      'annotations': const <Object?>[],
      'camera': const <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
    },
  });

  final authoringFileCount =
      options.scenarioCount * 2 +
      options.transitionCount +
      options.edgeCount +
      4;
  final manifest = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'DeterministicScaleCorpus',
    'scenarioCount': options.scenarioCount,
    'nodeCount': options.scenarioCount,
    'transitionCount': options.transitionCount,
    'edgeCount': options.edgeCount,
    'authoringFileCount': authoringFileCount,
    'batchSize': 500,
    'nonlinear': true,
  };
  _writeCanonical(File(p.join(root.path, 'scale-corpus.json')), manifest);
  stdout.writeln(jsonEncode(manifest));
}

void _writeDocument(
  Directory content,
  String relativePath,
  Map<String, Object?> document,
) {
  _writeCanonical(File(p.join(content.path, relativePath)), document);
}

void _writeCanonical(File file, Map<String, Object?> document) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(document)}\n',
  );
}

String _id(String prefix, int index) =>
    '$prefix-${index.toString().padLeft(5, '0')}';

String _partition(int index) =>
    'batch-${(index ~/ 500).toString().padLeft(3, '0')}';

(int, int) _endpoints(int index, int scenarioCount) {
  final from = index % scenarioCount;
  var to = (index * 37 + 17) % scenarioCount;
  if (to == from) to = (to + 1) % scenarioCount;
  return (from, to);
}

final class _Options {
  const _Options({
    required this.output,
    required this.scenarioCount,
    required this.transitionCount,
    required this.edgeCount,
  });

  final String output;
  final int scenarioCount;
  final int transitionCount;
  final int edgeCount;

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
        throw const FormatException(
          'Usage: generate_scale_corpus --output PATH --scenarios N '
          '--transitions N --edges N',
        );
      }
      values[arguments[index].substring(2)] = arguments[index + 1];
    }
    final output = values['output'];
    final scenarios = int.tryParse(values['scenarios'] ?? '');
    final transitions = int.tryParse(values['transitions'] ?? '');
    final edges = int.tryParse(values['edges'] ?? '');
    if (output == null ||
        scenarios == null ||
        scenarios < 1000 ||
        scenarios > 100000 ||
        transitions == null ||
        transitions < 20000 ||
        transitions > 100000 ||
        edges == null ||
        edges < scenarios ||
        edges > transitions) {
      throw const FormatException('Scale corpus cardinalities are invalid');
    }
    return _Options(
      output: output,
      scenarioCount: scenarios,
      transitionCount: transitions,
      edgeCount: edges,
    );
  }
}
