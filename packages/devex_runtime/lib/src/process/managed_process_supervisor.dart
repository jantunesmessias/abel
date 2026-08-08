import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

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

  void capture() {
    process.stdout.listen((bytes) => _append(_stdout, bytes));
    process.stderr.listen((bytes) => _append(_stderr, bytes));
  }

  void _append(List<int> target, List<int> bytes) {
    target.addAll(bytes);
    if (target.length > maxBytes) {
      target.removeRange(0, target.length - maxBytes);
    }
  }
}
