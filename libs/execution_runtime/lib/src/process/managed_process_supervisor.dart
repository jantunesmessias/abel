import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../io/bounded_utf8_line_decoder.dart';

typedef ManagedProcessExitHandler =
    FutureOr<void> Function(
      String ownerId,
      int exitCode,
      String stdoutTail,
      String stderrTail,
    );

final class ManagedProcessSupervisor {
  ManagedProcessSupervisor({
    required String workspaceRoot,
    this.maxCapturedOutputBytes = 256 * 1024,
    this.onExit,
  }) : workspaceRoot = Directory(workspaceRoot).resolveSymbolicLinksSync();

  final String workspaceRoot;
  final int maxCapturedOutputBytes;
  final ManagedProcessExitHandler? onExit;
  final Map<String, _ManagedProcess> _processes = <String, _ManagedProcess>{};

  int get activeCount => _processes.length;

  Future<TargetReadinessRecord> startTarget(
    String ownerId,
    LaunchProfile profile, {
    required String targetId,
    required TargetLaunchAttemptId launchAttemptId,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (_processes.containsKey(ownerId)) {
      throw StateError('Owner $ownerId already has a managed process');
    }
    final workingDirectory = _workingDirectory(profile.workingDirectory);
    final process = await Process.start(
      profile.command,
      profile.arguments,
      workingDirectory: workingDirectory,
      environment: <String, String>{
        ...profile.overlay.values,
        'TARGET_LAUNCH_ATTEMPT_ID': launchAttemptId.value,
        'TARGET_ID': targetId,
        'TARGET_LAUNCH_PROFILE_ID': profile.id,
      },
      includeParentEnvironment: true,
      mode: ProcessStartMode.normal,
    );
    final managed = _ManagedProcess(process, maxCapturedOutputBytes);
    _processes[ownerId] = managed;
    final stdout = managed.capturedStdout();
    managed.captureStderr();
    final readiness = Completer<TargetReadinessRecord>();
    TargetReadinessRecord? accepted;

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!readiness.isCompleted) {
        stackTrace == null
            ? readiness.completeError(error)
            : readiness.completeError(error, stackTrace);
      }
      process.kill(ProcessSignal.sigterm);
    }

    unawaited(
      stdout
          .transform(const BoundedUtf8LineDecoder(maxLineBytes: 16 * 1024))
          .forEach((line) {
            final Object? decoded;
            try {
              decoded = jsonDecode(line);
            } on FormatException {
              return;
            }
            if (decoded is! Map || decoded['kind'] != 'TargetReadinessRecord') {
              return;
            }
            try {
              final record = TargetReadinessRecord.fromJson(decoded);
              if (record.launchAttemptId != launchAttemptId ||
                  record.targetId != targetId ||
                  record.launchProfileId != profile.id ||
                  record.processId != process.pid) {
                throw const FormatException(
                  'Target readiness does not bind the launched process',
                );
              }
              final previous = accepted;
              if (previous != null) {
                if (previous.digest != record.digest) {
                  throw const FormatException(
                    'Target emitted conflicting readiness records',
                  );
                }
                return;
              }
              accepted = record;
              readiness.complete(record);
            } on Object catch (error, stackTrace) {
              fail(error, stackTrace);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            fail(error, stackTrace);
          }),
    );
    unawaited(
      process.exitCode.then((exitCode) async {
        if (_processes[ownerId] == managed) _processes.remove(ownerId);
        if (!readiness.isCompleted) {
          readiness.completeError(
            ProcessException(
              profile.command,
              profile.arguments,
              'Target exited before a readiness record. ${managed.stderrTail}',
              exitCode,
            ),
          );
        }
        await onExit?.call(
          ownerId,
          exitCode,
          managed.stdoutTail,
          managed.stderrTail,
        );
      }),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final record = await readiness.future.timeout(timeout);
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Target readiness');
      }
      await _probeTarget(record.origin, remaining);
      if (_processes[ownerId] != managed) {
        throw StateError('Target process exited during readiness verification');
      }
      return record;
    } on Object catch (error, stackTrace) {
      await stop(ownerId);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> start(String ownerId, LaunchProfile profile) async {
    if (_processes.containsKey(ownerId)) {
      throw StateError('Owner $ownerId already has a managed process');
    }
    final workingDirectory = _workingDirectory(profile.workingDirectory);
    final process = await Process.start(
      profile.command,
      profile.arguments,
      workingDirectory: workingDirectory,
      environment: profile.overlay.values,
      includeParentEnvironment: true,
      mode: ProcessStartMode.normal,
    );
    final managed = _ManagedProcess(process, maxCapturedOutputBytes);
    _processes[ownerId] = managed;
    managed.capture();
    unawaited(
      process.exitCode.then((exitCode) async {
        if (_processes[ownerId] == managed) _processes.remove(ownerId);
        await onExit?.call(
          ownerId,
          exitCode,
          managed.stdoutTail,
          managed.stderrTail,
        );
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!_processes.containsKey(ownerId)) {
      throw ProcessException(
        profile.command,
        profile.arguments,
        'Process exited before readiness. ${managed.stderrTail}',
        await process.exitCode,
      );
    }
  }

  Future<void> _probeTarget(Uri origin, Duration timeout) async {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(origin.replace(path: '/health'))
          .timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode != HttpStatus.ok || response.isRedirect) {
        throw StateError('Target readiness health probe failed');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop(String ownerId) async {
    final managed = _processes.remove(ownerId);
    if (managed == null) return;
    managed.process.kill(ProcessSignal.sigterm);
    try {
      await managed.process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      managed.process.kill(ProcessSignal.sigkill);
      await managed.process.exitCode;
    }
  }

  Future<void> close() async {
    for (final ownerId in _processes.keys.toList(growable: false)) {
      await stop(ownerId);
    }
  }

  String _workingDirectory(String relative) {
    final candidate = p.normalize(
      p.isAbsolute(relative) ? relative : p.join(workspaceRoot, relative),
    );
    if (!Directory(candidate).existsSync()) {
      throw FileSystemException('Working directory does not exist', candidate);
    }
    final resolved = Directory(candidate).resolveSymbolicLinksSync();
    if (resolved != workspaceRoot && !p.isWithin(workspaceRoot, resolved)) {
      throw FileSystemException(
        'Working directory escapes workspace',
        candidate,
      );
    }
    return resolved;
  }
}

final class _ManagedProcess {
  _ManagedProcess(this.process, this.maxBytes);

  final Process process;
  final int maxBytes;
  final List<int> _stdout = <int>[];
  final List<int> _stderr = <int>[];

  String get stdoutTail => utf8.decode(_stdout, allowMalformed: true);
  String get stderrTail => utf8.decode(_stderr, allowMalformed: true);

  Stream<List<int>> capturedStdout() => process.stdout.map((bytes) {
    _append(_stdout, bytes);
    return bytes;
  });

  void captureStderr() {
    process.stderr.listen((bytes) => _append(_stderr, bytes));
  }

  void capture() {
    capturedStdout().listen((_) {});
    captureStderr();
  }

  void _append(List<int> target, List<int> bytes) {
    target.addAll(bytes);
    if (target.length > maxBytes) {
      target.removeRange(0, target.length - maxBytes);
    }
  }
}
