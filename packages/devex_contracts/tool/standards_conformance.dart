import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/standards_conformance.dart '
      '<JSON-Schema-Test-Suite root> <json-canonicalization root>',
    );
    exitCode = 2;
    return;
  }

  final schemaRoot = Directory(arguments[0]);
  final jcsRoot = Directory(arguments[1]);
  if (!schemaRoot.existsSync() || !jcsRoot.existsSync()) {
    stderr.writeln('Both standards repositories must exist.');
    exitCode = 2;
    return;
  }

  final schemaResult = _verifyJsonSchema(schemaRoot);
  final jcsResult = _verifyJcs(jcsRoot);
  stdout.writeln(
    'JSON Schema profile: ${schemaResult.passed}/${schemaResult.total} '
    '(skipped outside profile: ${schemaResult.skipped}); '
    'JCS: ${jcsResult.passed}/${jcsResult.total}',
  );
  final failures = <String>[...schemaResult.failures, ...jcsResult.failures];
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

_ConformanceResult _verifyJsonSchema(Directory repository) {
  final directory = Directory('${repository.path}/tests/draft2020-12');
  final files =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) => !file.path.endsWith('/refRemote.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  var total = 0;
  var passed = 0;
  var skipped = 0;
  final failures = <String>[];
  for (final file in files) {
    final groups = jsonDecode(file.readAsStringSync())! as List<Object?>;
    for (final rawGroup in groups) {
      final group = rawGroup! as Map<String, Object?>;
      final description = group['description']! as String;
      final tests = group['tests']! as List<Object?>;
      if (!_isSupportedDevExSchemaProfile(group['schema'])) {
        skipped += tests.length;
        continue;
      }
      final Draft202012Validator validator;
      try {
        validator = Draft202012Validator(group['schema']!);
      } on Object catch (error) {
        failures.add('${file.path}: $description could not compile: $error');
        continue;
      }
      for (final rawTest in tests) {
        total += 1;
        final test = rawTest! as Map<String, Object?>;
        final expected = test['valid']! as bool;
        final actual = validator.validate(test['data']).isValid;
        if (actual == expected) {
          passed += 1;
        } else {
          failures.add(
            '${file.path}: $description / ${test['description']} '
            'expected $expected, got $actual',
          );
        }
      }
    }
  }
  return _ConformanceResult(
    total: total,
    passed: passed,
    skipped: skipped,
    failures: failures,
  );
}

const Set<String> _integerCountKeywords = <String>{
  'maxContains',
  'maxItems',
  'maxLength',
  'maxProperties',
  'minContains',
  'minItems',
  'minLength',
  'minProperties',
};

const Set<String> _unsupportedProfileKeywords = <String>{
  r'$dynamicAnchor',
  r'$dynamicRef',
  'contentSchema',
  'unevaluatedItems',
};

bool _isSupportedDevExSchemaProfile(Object? value) {
  if (value case final Map<String, Object?> map) {
    for (final entry in map.entries) {
      if (_unsupportedProfileKeywords.contains(entry.key)) return false;
      if (entry.key == r'$schema' &&
          entry.value != 'https://json-schema.org/draft/2020-12/schema') {
        return false;
      }
      if (entry.key == r'$ref' &&
          entry.value is String &&
          !(entry.value! as String).startsWith('#')) {
        return false;
      }
      if (entry.key == 'enum' &&
          entry.value is List<Object?> &&
          (entry.value! as List<Object?>).isEmpty) {
        return false;
      }
      if (_integerCountKeywords.contains(entry.key) && entry.value is! int) {
        return false;
      }
      if (!_isSupportedDevExSchemaProfile(entry.value)) return false;
    }
  } else if (value case final List<Object?> list) {
    return list.every(_isSupportedDevExSchemaProfile);
  }
  return true;
}

_ConformanceResult _verifyJcs(Directory repository) {
  final inputDirectory = Directory('${repository.path}/testdata/input');
  final outputDirectory = Directory('${repository.path}/testdata/output');
  final files =
      inputDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  var passed = 0;
  final failures = <String>[];
  for (final input in files) {
    final filename = input.uri.pathSegments.last;
    final expectedFile = File('${outputDirectory.path}/$filename');
    final value = jsonDecode(input.readAsStringSync());
    final actual = const JcsCanonicalizer().canonicalize(value);
    final expected = _removeSingleTrailingNewline(
      expectedFile.readAsStringSync(),
    );
    if (actual == expected) {
      passed += 1;
    } else {
      failures.add('JCS $filename differs from the official output');
    }
  }
  return _ConformanceResult(
    total: files.length,
    passed: passed,
    skipped: 0,
    failures: failures,
  );
}

String _removeSingleTrailingNewline(String value) {
  if (value.endsWith('\r\n')) return value.substring(0, value.length - 2);
  if (value.endsWith('\n')) return value.substring(0, value.length - 1);
  return value;
}

final class _ConformanceResult {
  const _ConformanceResult({
    required this.total,
    required this.passed,
    required this.skipped,
    required this.failures,
  });

  final int total;
  final int passed;
  final int skipped;
  final List<String> failures;
}
