import 'dart:convert';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

final class SessionCaptureDescriptor {
  const SessionCaptureDescriptor({
    required this.id,
    required this.principalId,
    required this.targetId,
    required this.targetGeneration,
    required this.expiresAt,
    required this.hintNames,
  });

  final String id;
  final String principalId;
  final String targetId;
  final String targetGeneration;
  final DateTime expiresAt;
  final Set<String> hintNames;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'principalId': principalId,
    'targetId': targetId,
    'targetGeneration': targetGeneration,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'hintNames': hintNames.toList()..sort(),
    'storage': 'processMemoryOnly',
    'redaction': 'values=omitted',
  };
}

final class CapturedSessionMaterial {
  CapturedSessionMaterial._(Map<String, String> values)
    : _values = Map<String, String>.unmodifiable(values);

  final Map<String, String> _values;

  String? value(String name) => _values[name.toLowerCase()];

  Set<String> get names => Set<String>.unmodifiable(_values.keys);

  @override
  String toString() => '<redacted-session-material>';
}

/// A process-memory-only vault for short-lived, explicitly allowlisted session
/// hints. Nothing in this type has a filesystem/CAS serializer by design.
final class SessionCaptureVault {
  SessionCaptureVault({required this.clock, required this.ids});

  static const Set<String> allowedHintNames = <String>{
    'authorization',
    'x-csrf-token',
    'x-session-id',
  };

  final Clock clock;
  final IdGenerator ids;
  final Map<String, _CapturedEntry> _entries = <String, _CapturedEntry>{};

  int get activeCount {
    purgeExpired();
    return _entries.length;
  }

  SessionCaptureDescriptor capture({
    required String principalId,
    required String targetId,
    required String targetGeneration,
    required Map<String, String> hints,
    required Duration ttl,
  }) {
    OpaqueId.validate(principalId, 'Principal');
    OpaqueId.validate(targetId, 'ExecutionTarget');
    if (targetGeneration.isEmpty || targetGeneration.length > 256) {
      throw ArgumentError.value(targetGeneration, 'targetGeneration');
    }
    if (ttl <= Duration.zero || ttl > const Duration(minutes: 30)) {
      throw ArgumentError.value(ttl, 'ttl', 'must be at most 30 minutes');
    }
    if (hints.isEmpty || hints.length > allowedHintNames.length) {
      throw ArgumentError('Session capture requires allowlisted hints');
    }
    purgeExpired();
    final protected = <String, Uint8List>{};
    for (final entry in hints.entries) {
      final name = entry.key.toLowerCase();
      if (!allowedHintNames.contains(name)) {
        _wipe(protected.values);
        throw FormatException('Session hint $name is not allowlisted');
      }
      final bytes = utf8.encode(entry.value);
      if (bytes.isEmpty || bytes.length > 8192) {
        _wipe(protected.values);
        throw FormatException('Session hint $name has an invalid size');
      }
      protected[name] = Uint8List.fromList(bytes);
    }
    final id = 'capture-${ids.nextId()}';
    final descriptor = SessionCaptureDescriptor(
      id: id,
      principalId: principalId,
      targetId: targetId,
      targetGeneration: targetGeneration,
      expiresAt: clock.nowUtc().add(ttl),
      hintNames: Set<String>.unmodifiable(protected.keys),
    );
    _entries[id] = _CapturedEntry(descriptor, protected);
    return descriptor;
  }

  CapturedSessionMaterial resolve({
    required String captureId,
    required String principalId,
    required String targetId,
    required String targetGeneration,
  }) {
    purgeExpired();
    final entry = _entries[captureId];
    if (entry == null ||
        entry.descriptor.principalId != principalId ||
        entry.descriptor.targetId != targetId ||
        entry.descriptor.targetGeneration != targetGeneration) {
      throw StateError('Captured session is unavailable for this context');
    }
    return CapturedSessionMaterial._(<String, String>{
      for (final hint in entry.values.entries)
        hint.key: utf8.decode(hint.value),
    });
  }

  int invalidateTarget(String targetId) =>
      _invalidate((entry) => entry.descriptor.targetId == targetId);

  int invalidatePrincipal(String principalId) =>
      _invalidate((entry) => entry.descriptor.principalId == principalId);

  int purgeExpired() {
    final now = clock.nowUtc();
    return _invalidate((entry) => !entry.descriptor.expiresAt.isAfter(now));
  }

  void close() => _invalidate((_) => true);

  int _invalidate(bool Function(_CapturedEntry) matches) {
    final ids = _entries.entries
        .where((entry) => matches(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in ids) {
      final entry = _entries.remove(id)!;
      _wipe(entry.values.values);
    }
    return ids.length;
  }

  void _wipe(Iterable<Uint8List> values) {
    for (final value in values) {
      value.fillRange(0, value.length, 0);
    }
  }
}

final class _CapturedEntry {
  const _CapturedEntry(this.descriptor, this.values);

  final SessionCaptureDescriptor descriptor;
  final Map<String, Uint8List> values;
}
