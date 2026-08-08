import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

void main() {
  final value = jsonDecode(
    File(
      'tests/fixtures/source_impact/source-impact-corpus.json',
    ).readAsStringSync(),
  );
  if (value is! Map<String, Object?> ||
      value['schemaVersion'] != 1 ||
      value['cases'] is! List<Object?>) {
    stderr.writeln('Invalid source impact corpus');
    exitCode = 2;
    return;
  }
  var decisions = 0;
  var truePositives = 0;
  var trueNegatives = 0;
  var falsePositives = 0;
  var falseNegatives = 0;
  final failures = <String>[];
  for (final rawCase in value['cases']! as List<Object?>) {
    if (rawCase is! Map<String, Object?>) {
      throw const FormatException('Corpus case must be an object');
    }
    final id = rawCase['id']! as String;
    final base = _snapshot(
      'base-$id',
      rawCase['base']! as Map<String, Object?>,
      complete: rawCase['baseComplete'] as bool? ?? true,
    );
    final current = _snapshot(
      'current-$id',
      rawCase['current']! as Map<String, Object?>,
      complete: rawCase['currentComplete'] as bool? ?? true,
    );
    final bindingValues = rawCase['bindings']! as List<Object?>;
    final bindings = bindingValues
        .map(SourceBinding.fromJson)
        .toList(growable: false);
    final expected = (rawCase['expectedImpacted']! as List<Object?>)
        .cast<String>()
        .toSet();
    final engine = const SourceImpactEngine();
    final actual = engine
        .plan(engine.diff(base, current), bindings)
        .impacted
        .map((item) => item.bindingId)
        .toSet();
    for (final binding in bindings) {
      decisions += 1;
      final predicted = actual.contains(binding.id);
      final labeled = expected.contains(binding.id);
      if (predicted && labeled) truePositives += 1;
      if (!predicted && !labeled) trueNegatives += 1;
      if (predicted && !labeled) falsePositives += 1;
      if (!predicted && labeled) falseNegatives += 1;
    }
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      failures.add(
        '$id expected=${expected.toList()..sort()} actual=${actual.toList()..sort()}',
      );
    }
  }
  final falsePositiveRate = falsePositives / decisions;
  final falseNegativeRate = falseNegatives / decisions;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'SourceImpactCorpusReport',
    'cases': (value['cases']! as List<Object?>).length,
    'decisions': decisions,
    'truePositives': truePositives,
    'trueNegatives': trueNegatives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'falsePositiveRate': falsePositiveRate,
    'falseNegativeRate': falseNegativeRate,
    'thresholds': const <String, Object?>{
      'maximumFalsePositiveRate': 0.10,
      'maximumFalseNegativeRate': 0.0,
    },
    'failures': failures,
  };
  stdout.writeln(const JcsCanonicalizer().canonicalize(report));
  if (failures.isNotEmpty ||
      falseNegativeRate > 0 ||
      falsePositiveRate > 0.10) {
    exitCode = 1;
  }
}

SourceSnapshot _snapshot(
  String revision,
  Map<String, Object?> values, {
  required bool complete,
}) => SourceSnapshot(
  repository: SourceRepository(
    id: 'repo',
    kind: SourceRepositoryKind.filesystem,
    root: '.',
  ),
  revision: revision,
  completeness: complete
      ? SnapshotCompleteness.complete
      : SnapshotCompleteness.partial,
  files: <SourceFileEntry>[
    for (final entry in values.entries)
      SourceFileEntry(
        path: entry.key,
        digest: Digest.bytes(utf8.encode(entry.value! as String)),
        size: utf8.encode(entry.value! as String).length,
      ),
  ],
  omissions: complete
      ? const <String>[]
      : const <String>['corpus:deliberate-omission'],
);
