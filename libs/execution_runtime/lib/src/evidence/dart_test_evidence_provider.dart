import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../io/bounded_utf8_line_decoder.dart';
import '../storage/filesystem_workspace_store.dart';

enum DartTestRunner { dart, flutter }

final class DartTestEvidenceProvider {
  DartTestEvidenceProvider({
    required String workspaceRoot,
    String distributionId = 'full-local',
  }) : workspaceRoot = Directory(
         workspaceRoot,
       ).absolute.resolveSymbolicLinksSync(),
       store = FileSystemWorkspaceStore(
         workspaceRoot: workspaceRoot,
         distributionId: distributionId,
       );

  static const String providerId = 'dart-test-json-v1';
  static const int maxLineBytes = 1024 * 1024;
  static const int maxEvents = 100000;
  static const int maxStderrBytes = 1024 * 1024;
  static const int maxReferencedArtifacts = 32;
  static const int maxArtifactBytes = 64 * 1024 * 1024;
  static const int maxTotalArtifactBytes = 256 * 1024 * 1024;

  final String workspaceRoot;
  final FileSystemWorkspaceStore store;

  Future<TestEvidenceSummary> collect({
    required DartTestRunner runner,
    required List<String> targets,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (targets.isEmpty || targets.length > 256) {
      throw ArgumentError('At least one bounded test target is required');
    }
    final safeTargets = targets.map(_validateTarget).toList(growable: false);
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 30)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    final executable = switch (runner) {
      DartTestRunner.dart => Platform.resolvedExecutable,
      DartTestRunner.flutter => _findExecutable('flutter'),
    };
    final arguments = switch (runner) {
      DartTestRunner.dart => <String>[
        'test',
        '--reporter',
        'json',
        ...safeTargets,
      ],
      DartTestRunner.flutter => <String>['test', '--machine', ...safeTargets],
    };
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workspaceRoot,
      mode: ProcessStartMode.normal,
    );
    final parser = _DartTestReportParser();
    try {
      final parsing = parser.consume(process.stdout);
      final stderrDrain = _drainBounded(process.stderr, limit: maxStderrBytes);
      final exit = process.exitCode;
      await Future.wait<Object?>(<Future<Object?>>[
        parsing,
        stderrDrain,
        exit,
      ]).timeout(timeout);
      return _materialize(parser.finish(exitCode: await exit));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return 130;
        },
      );
      throw StateError('Dart test evidence provider timed out');
    } on Object {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  Future<TestEvidenceSummary> ingest(
    Stream<List<int>> report, {
    required int exitCode,
  }) async {
    final parser = _DartTestReportParser();
    await parser.consume(report);
    return _materialize(parser.finish(exitCode: exitCode));
  }

  TestEvidenceSummary _materialize(_ParsedTestReport parsed) {
    final referenced = <Artifact>[];
    var totalArtifactBytes = 0;
    for (final reference in parsed.artifactReferences) {
      final file = _safeArtifactFile(reference.path);
      final size = file.lengthSync();
      if (size > maxArtifactBytes) {
        throw StateError('Referenced test artifact exceeds 64 MiB');
      }
      final bytes = _readBounded(file, maxArtifactBytes);
      totalArtifactBytes += bytes.length;
      if (totalArtifactBytes > maxTotalArtifactBytes) {
        throw StateError('Referenced test artifacts exceed 256 MiB');
      }
      final digest = store.withExclusiveLock(() => store.putBlob(bytes));
      referenced.add(
        Artifact(
          digest: digest,
          size: bytes.length,
          mediaType: reference.mediaType,
          classification: reference.classification,
          role: reference.role,
        ),
      );
    }
    final uniqueDigests = <Digest>{};
    if (referenced.any((artifact) => !uniqueDigests.add(artifact.digest))) {
      throw StateError('Referenced test artifacts must have unique content');
    }
    final normalized = <String, Object?>{
      'schemaVersion': 1,
      'providerId': providerId,
      'runnerProtocolVersion': parsed.protocolVersion,
      'runnerVersion': parsed.runnerVersion,
      'success': parsed.success,
      'total': parsed.total,
      'passed': parsed.passed,
      'failed': parsed.failed,
      'skipped': parsed.skipped,
      'durationMilliseconds': parsed.durationMilliseconds,
      'platforms': parsed.platforms.toList()..sort(),
      'referencedArtifacts': referenced
          .map((artifact) => artifact.toJson())
          .toList(growable: false),
    };
    final reportBytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(normalized)}\n',
    );
    final reportDigest = store.withExclusiveLock(
      () => store.putBlob(reportBytes),
    );
    return TestEvidenceSummary(
      providerId: providerId,
      runnerProtocolVersion: parsed.protocolVersion,
      runnerVersion: parsed.runnerVersion,
      success: parsed.success,
      total: parsed.total,
      passed: parsed.passed,
      failed: parsed.failed,
      skipped: parsed.skipped,
      durationMilliseconds: parsed.durationMilliseconds,
      platforms: parsed.platforms,
      reportArtifact: Artifact(
        digest: reportDigest,
        size: reportBytes.length,
        mediaType: 'application/json',
        classification: ArtifactClassification.internal,
        role: 'dart-test-report',
      ),
      referencedArtifacts: referenced,
    );
  }

  String _validateTarget(String value) {
    if (value.isEmpty || value.startsWith('-') || p.isAbsolute(value)) {
      throw FormatException('Test target must be a relative path');
    }
    final normalized = p.normalize(p.join(workspaceRoot, value));
    if (!p.isWithin(workspaceRoot, normalized) ||
        Link(normalized).existsSync() ||
        (!File(normalized).existsSync() &&
            !Directory(normalized).existsSync())) {
      throw FormatException('Test target is missing or unsafe: $value');
    }
    _rejectSymlinkAncestors(normalized);
    return p.relative(normalized, from: workspaceRoot);
  }

  File _safeArtifactFile(String relativePath) {
    if (relativePath.isEmpty ||
        p.isAbsolute(relativePath) ||
        relativePath.split(RegExp(r'[/\\]')).contains('..')) {
      throw FormatException('Test artifact path must be workspace-relative');
    }
    final normalized = p.normalize(p.join(workspaceRoot, relativePath));
    if (!p.isWithin(workspaceRoot, normalized) ||
        Link(normalized).existsSync() ||
        !File(normalized).existsSync()) {
      throw FormatException('Referenced test artifact is missing or unsafe');
    }
    _rejectSymlinkAncestors(normalized);
    return File(normalized);
  }

  List<int> _readBounded(File file, int limit) {
    final input = file.openSync(mode: FileMode.read);
    final builder = BytesBuilder(copy: false);
    var length = 0;
    try {
      while (true) {
        final chunk = input.readSync(64 * 1024);
        if (chunk.isEmpty) break;
        length += chunk.length;
        if (length > limit) {
          throw StateError('Referenced test artifact exceeds 64 MiB');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      input.closeSync();
    }
  }

  void _rejectSymlinkAncestors(String path) {
    var parent = File(path).parent;
    while (parent.path != workspaceRoot) {
      if (Link(parent.path).existsSync()) {
        throw FormatException('Path crosses a symlink');
      }
      parent = parent.parent;
    }
  }

  String _findExecutable(String name) {
    final path = Platform.environment['PATH'] ?? '';
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      final candidate = File('$directory${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
    throw StateError('$name executable is unavailable');
  }

  Future<void> _drainBounded(
    Stream<List<int>> source, {
    required int limit,
  }) async {
    var length = 0;
    await for (final chunk in source) {
      length += chunk.length;
      if (length > limit) throw StateError('Test runner stderr is oversized');
    }
  }
}

final class _DartTestReportParser {
  String? protocolVersion;
  String? runnerVersion;
  bool? doneSuccess;
  int durationMilliseconds = 0;
  int passed = 0;
  int failed = 0;
  int skipped = 0;
  int events = 0;
  final Set<String> platforms = <String>{};
  final List<_ArtifactReference> artifactReferences = <_ArtifactReference>[];
  var _started = false;
  var _done = false;

  Future<void> consume(Stream<List<int>> source) async {
    await for (final line in const BoundedUtf8LineDecoder(
      maxLineBytes: DartTestEvidenceProvider.maxLineBytes,
    ).bind(source)) {
      if (line.isEmpty) continue;
      events += 1;
      if (events > DartTestEvidenceProvider.maxEvents) {
        throw StateError('Test reporter event quota exceeded');
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Test reporter event must be an object');
      }
      final type = decoded['type'];
      if (type is! String) {
        throw const FormatException('Test reporter event type is missing');
      }
      if (_done) throw const FormatException('Event observed after done');
      switch (type) {
        case 'start':
          if (_started) throw const FormatException('Duplicate start event');
          protocolVersion = _requiredString(decoded, 'protocolVersion');
          runnerVersion = _requiredString(decoded, 'runnerVersion');
          if (protocolVersion != '0.1.1') {
            throw FormatException(
              'Unsupported test reporter protocol: $protocolVersion',
            );
          }
          _started = true;
        case 'suite':
          _requireStarted();
          final suite = _requiredObject(decoded, 'suite');
          platforms.add(_requiredString(suite, 'platform'));
        case 'testDone':
          _requireStarted();
          final hidden = decoded['hidden'];
          final wasSkipped = decoded['skipped'];
          final result = decoded['result'];
          if (hidden is! bool || wasSkipped is! bool || result is! String) {
            throw const FormatException('Malformed testDone event');
          }
          if (hidden && result == 'success') continue;
          if (wasSkipped) {
            skipped += 1;
          } else if (result == 'success') {
            passed += 1;
          } else {
            failed += 1;
          }
        case 'print':
          _requireStarted();
          final message = _requiredString(decoded, 'message');
          _parseArtifactMarkers(message);
        case 'done':
          _requireStarted();
          final success = decoded['success'];
          final time = decoded['time'];
          if (success is! bool || time is! int || time < 0) {
            throw const FormatException('Malformed done event');
          }
          doneSuccess = success;
          durationMilliseconds = time;
          _done = true;
        case 'allSuites':
        case 'debug':
        case 'error':
        case 'group':
        case 'message':
        case 'testStart':
          _requireStarted();
        default:
          throw FormatException('Unknown test reporter event type: $type');
      }
    }
  }

  _ParsedTestReport finish({required int exitCode}) {
    if (!_started ||
        !_done ||
        protocolVersion == null ||
        runnerVersion == null ||
        doneSuccess == null) {
      throw const FormatException('Incomplete test reporter stream');
    }
    if (platforms.isEmpty) {
      throw const FormatException('Test reporter emitted no suite platform');
    }
    if ((exitCode == 0) != doneSuccess!) {
      throw const FormatException('Runner exit code contradicts done event');
    }
    if (doneSuccess! != (failed == 0)) {
      if (!doneSuccess! && failed == 0) {
        failed = 1;
      } else {
        throw const FormatException(
          'Runner success contradicts completed test results',
        );
      }
    }
    return _ParsedTestReport(
      protocolVersion: protocolVersion!,
      runnerVersion: runnerVersion!,
      success: doneSuccess!,
      passed: passed,
      failed: failed,
      skipped: skipped,
      durationMilliseconds: durationMilliseconds,
      platforms: Set<String>.unmodifiable(platforms),
      artifactReferences: List<_ArtifactReference>.unmodifiable(
        artifactReferences,
      ),
    );
  }

  void _parseArtifactMarkers(String message) {
    const prefix = 'TEST_ARTIFACT_JSON:';
    for (final line in const LineSplitter().convert(message)) {
      if (!line.startsWith(prefix)) continue;
      if (artifactReferences.length ==
          DartTestEvidenceProvider.maxReferencedArtifacts) {
        throw StateError('Too many referenced test artifacts');
      }
      final decoded = jsonDecode(line.substring(prefix.length));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Artifact marker must be an object');
      }
      const allowed = <String>{'path', 'mediaType', 'classification', 'role'};
      if (decoded.keys.any((key) => !allowed.contains(key))) {
        throw const FormatException('Artifact marker has unknown fields');
      }
      artifactReferences.add(
        _ArtifactReference(
          path: _requiredString(decoded, 'path'),
          mediaType: _requiredString(decoded, 'mediaType'),
          classification: ArtifactClassification.values.byName(
            _requiredString(decoded, 'classification'),
          ),
          role: _requiredString(decoded, 'role'),
        ),
      );
    }
  }

  void _requireStarted() {
    if (!_started) throw const FormatException('Event observed before start');
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! Map<String, Object?>) {
      throw FormatException('$key must be an object');
    }
    return value;
  }
}

final class _ParsedTestReport {
  const _ParsedTestReport({
    required this.protocolVersion,
    required this.runnerVersion,
    required this.success,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.durationMilliseconds,
    required this.platforms,
    required this.artifactReferences,
  });

  final String protocolVersion;
  final String runnerVersion;
  final bool success;
  final int passed;
  final int failed;
  final int skipped;
  final int durationMilliseconds;
  final Set<String> platforms;
  final List<_ArtifactReference> artifactReferences;

  int get total => passed + failed + skipped;
}

final class _ArtifactReference {
  const _ArtifactReference({
    required this.path,
    required this.mediaType,
    required this.classification,
    required this.role,
  });

  final String path;
  final String mediaType;
  final ArtifactClassification classification;
  final String role;
}
