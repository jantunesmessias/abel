import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';
import 'experience_authoring_store.dart';

const String experienceAuthoringDurableWriteProtocol =
    'linux-x64-openat-renameat-fsync-v1';

enum ExperienceAuthoringStateDurabilityFailureCode {
  unsupported,
  unsafeEntity,
  ioFailure,
  unproven,
}

/// Sanitized failure from the Host-private durable-state boundary.
///
/// Paths and errno are retained only for private diagnostics and deliberately
/// omitted from [toString], journal records, and RPC results.
final class ExperienceAuthoringStateDurabilityFailure implements Exception {
  const ExperienceAuthoringStateDurabilityFailure.unsupported()
    : this._(ExperienceAuthoringStateDurabilityFailureCode.unsupported);

  const ExperienceAuthoringStateDurabilityFailure._(
    this.code, {
    this._diagnosticPath,
    this._diagnosticErrno,
  });

  final ExperienceAuthoringStateDurabilityFailureCode code;
  final String? _diagnosticPath;
  final int? _diagnosticErrno;

  @override
  int get hashCode => Object.hash(code, _diagnosticPath, _diagnosticErrno);

  @override
  bool operator ==(Object other) =>
      other is ExperienceAuthoringStateDurabilityFailure &&
      other.code == code &&
      other._diagnosticPath == _diagnosticPath &&
      other._diagnosticErrno == _diagnosticErrno;

  @override
  String toString() =>
      'ExperienceAuthoringStateDurabilityFailure(${code.name})';
}

enum ExperienceAuthoringStateFsyncTarget {
  stateDirectoryParent,
  stagingFile,
  destinationParent,
  existingFile,
  existingParent,
}

typedef ExperienceAuthoringStateFsyncHook =
    void Function(ExperienceAuthoringStateFsyncTarget target);

enum ExperienceAuthoringGuardBoundary {
  afterCreateBeforeWrite,
  afterAcquire,
  beforeRelease,
}

typedef ExperienceAuthoringGuardBoundaryHook =
    void Function(ExperienceAuthoringGuardBoundary boundary);

/// An opaque proof produced only after file and directory durability fences.
///
/// The private constructor prevents an injected writer from claiming success
/// without first delegating to the strict native writer.
final class ExperienceAuthoringDurableWriteReceipt {
  const ExperienceAuthoringDurableWriteReceipt._({
    required this.protocol,
    required this.workspaceAuthorityDigest,
    required this.relativePath,
    required this.digest,
    required this.byteLength,
  });

  final String protocol;
  final Digest workspaceAuthorityDigest;
  final String relativePath;
  final Digest digest;
  final int byteLength;
}

abstract interface class ExperienceAuthoringStateWriter {
  bool get isDurabilitySupported;

  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  });

  /// Re-establishes durability for an exact, already-visible state entry.
  ///
  /// This is mandatory even for content-addressed entries: the shared CAS may
  /// have been written by an older producer that flushed the inode but not its
  /// directory entry, or by a process that observed a directory-fsync failure
  /// immediately after rename. Integrity alone is not a power-loss proof.
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  });
}

final class DefaultExperienceAuthoringStateWriter
    implements ExperienceAuthoringStateWriter {
  const DefaultExperienceAuthoringStateWriter({this.beforeFsync});

  /// Deterministic native-boundary test seam. Production composition leaves
  /// this null.
  final ExperienceAuthoringStateFsyncHook? beforeFsync;

  static final _LinuxX64AuthoringStateBindings? _bindings =
      _LinuxX64AuthoringStateBindings.tryLoad();

  @override
  bool get isDurabilitySupported =>
      ffi.Abi.current() == ffi.Abi.linuxX64 && _bindings != null;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    final bindings = _bindings;
    if (ffi.Abi.current() != ffi.Abi.linuxX64 || bindings == null) {
      throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
    }
    return bindings.write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
      beforeFsync: beforeFsync,
    );
  }

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) {
    final bindings = _bindings;
    if (ffi.Abi.current() != ffi.Abi.linuxX64 || bindings == null) {
      throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
    }
    return bindings.reproveExisting(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      beforeFsync: beforeFsync,
    );
  }
}

/// Durable, single-owner LayoutDraft authority.
///
/// The public draft stays bounded. Its potentially larger immutable base layout
/// is retained in the workspace CAS and linked from a canonical hash-chained
/// journal. Every replacement must extend both the public draft revision chain
/// and the exact current digest, preventing semantic ABA after undo/reset.
final class FilesystemExperienceAuthoringStore {
  FilesystemExperienceAuthoringStore({
    required this.workspaceStore,
    this.writer = const DefaultExperienceAuthoringStateWriter(),
    this.maxJournalEntries = 100000,
    this.maxDraftMutations = experienceAuthoringMaxSafeInteger,
    this.maxPromotionReceiptsPerSubject = 256,
    this.maxStoredGrants = 4096,
    this.maxStoredAttempts = 8192,
    this.maxStoredReviewObjects = 4096,
    this.guardTimeout = const Duration(seconds: 30),
    this.guardBoundaryHook,
  }) {
    if (maxJournalEntries < 2 || maxJournalEntries > 1000000) {
      throw ArgumentError.value(maxJournalEntries, 'maxJournalEntries');
    }
    if (maxDraftMutations < 1 ||
        maxDraftMutations > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError.value(maxDraftMutations, 'maxDraftMutations');
    }
    if (maxPromotionReceiptsPerSubject <
            experienceAuthoringMaxPromotionReceipts ||
        maxPromotionReceiptsPerSubject > 1024) {
      throw ArgumentError.value(
        maxPromotionReceiptsPerSubject,
        'maxPromotionReceiptsPerSubject',
      );
    }
    if (maxStoredGrants < 16 || maxStoredGrants > 65536) {
      throw ArgumentError.value(maxStoredGrants, 'maxStoredGrants');
    }
    if (maxStoredAttempts < maxStoredGrants * 2 || maxStoredAttempts > 131072) {
      throw ArgumentError.value(maxStoredAttempts, 'maxStoredAttempts');
    }
    if (maxStoredReviewObjects < 16 || maxStoredReviewObjects > 65536) {
      throw ArgumentError.value(
        maxStoredReviewObjects,
        'maxStoredReviewObjects',
      );
    }
    if (guardTimeout <= Duration.zero ||
        guardTimeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(guardTimeout, 'guardTimeout');
    }
  }

  static const String statePath = 'experience-authoring/authoring.journal.json';
  static const int _maxStateBytes = 64 * 1024 * 1024;
  static const int _maxBaseLayoutBytes = 16 * 1024 * 1024;
  static const int _maxPromotionSourceBytes = 1024 * 1024;
  static const String _guardName = 'authoring.lock.guard';

  final FileSystemWorkspaceStore workspaceStore;
  final ExperienceAuthoringStateWriter writer;
  final int maxJournalEntries;
  final int maxDraftMutations;
  final int maxPromotionReceiptsPerSubject;
  final int maxStoredGrants;
  final int maxStoredAttempts;
  final int maxStoredReviewObjects;
  final Duration guardTimeout;
  final ExperienceAuthoringGuardBoundaryHook? guardBoundaryHook;
  ExperienceAuthoringStoreTransaction? _activeTransaction;
  bool _durabilityUncertain = false;

  String get stateFilePath => p.join(workspaceStore.stateRoot, statePath);
  String get guardFilePath =>
      p.join(workspaceStore.stateRoot, 'experience-authoring', _guardName);
  bool get isDurabilityAvailable =>
      !_durabilityUncertain && writer.isDurabilitySupported;
  bool get hasDurabilityUncertainty => _durabilityUncertain;

  /// Keeps one continuous journal/source authority lock for a synchronous
  /// multi-step transaction. Nested store calls reuse the same claim.
  T withTransaction<T>(
    T Function(ExperienceAuthoringStoreTransaction transaction) action,
  ) {
    if (action
        is Future<dynamic> Function(ExperienceAuthoringStoreTransaction)) {
      throw StateError(
        'Experience authoring transactions reject async callbacks',
      );
    }
    final active = _activeTransaction;
    if (active != null) return _synchronous(action(active));
    return _locked(() {
      final transaction = ExperienceAuthoringStoreTransaction._(this);
      _activeTransaction = transaction;
      try {
        return _synchronous(action(transaction));
      } finally {
        transaction._deactivate();
        _activeTransaction = null;
      }
    });
  }

  StoredLayoutDraftOpenResult openOrResumeDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) => _transactional(() {
    var state = _load();
    final key = _subjectKey(draft.subject);
    final existing = state.drafts[key];
    if (existing != null) {
      if (existing.ownerPrincipalId != ownerPrincipalId) {
        throw ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.ownerConflict,
          currentDigest: existing.draft.digest,
          currentRevision: existing.draft.revision,
        );
      }
      return StoredLayoutDraftOpenResult(storedDraft: existing, resumed: true);
    }
    if (draft.revision != 0 || draft.previousDraftDigest != null) {
      throw ArgumentError('A newly opened draft must start at revision zero');
    }
    if (draft.baseLayoutDigest != baseLayout.digest ||
        draft.topologyDigest != baseLayout.topologyDigest ||
        draft.subject.projectionId != baseLayout.projectionId) {
      throw ArgumentError('Draft and base layout do not share one authority');
    }
    const LayoutDraftEngine().validateDraft(
      draft: draft,
      baseLayout: baseLayout,
    );
    if (state.draftIds.contains(draft.id.value)) {
      throw StateError('LayoutDraft ID collision');
    }
    final baseBytes = _encodeBaseLayout(baseLayout);
    final blobDigest = _putBlobBounded(
      baseBytes,
      maxBytes: _maxBaseLayoutBytes,
    );
    final stored = StoredLayoutDraft(
      ownerPrincipalId: ownerPrincipalId,
      draft: draft,
      baseLayoutBlobDigest: blobDigest,
    );
    state = _appendEvent(state, _JournalEventType.openDraft, <String, Object?>{
      'storedDraft': _storedDraftJson(stored),
    });
    _persist(state);
    return StoredLayoutDraftOpenResult(
      storedDraft: state.drafts[key]!,
      resumed: false,
    );
  });

  StoredLayoutDraft? findDraft(AuthoringSubjectRef subject) =>
      _transactional(() => _load().drafts[_subjectKey(subject)]);

  StoredLayoutDraft? findDraftById(LayoutDraftId draftId) => _transactional(() {
    final matches = _load().drafts.values
        .where((stored) => stored.draft.id == draftId)
        .toList(growable: false);
    if (matches.length > 1) {
      throw const FormatException('Duplicate active LayoutDraft IDs');
    }
    return matches.firstOrNull;
  });

  StoredLayoutDraft requireDraft(AuthoringSubjectRef subject) =>
      findDraft(subject) ??
      (throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.draftNotFound,
      ));

  ProjectionLayoutManifest requireBaseLayout(StoredLayoutDraft stored) =>
      _transactional(() {
        final state = _load();
        final current = state.drafts[_subjectKey(stored.draft.subject)];
        if (current == null || current.draft.id != stored.draft.id) {
          throw const ExperienceAuthoringStoreFailure(
            ExperienceAuthoringStoreErrorCode.draftNotFound,
          );
        }
        if (current.baseLayoutBlobDigest != stored.baseLayoutBlobDigest) {
          throw const FormatException('Stored base layout CAS link changed');
        }
        return _readBaseLayout(current);
      });

  StoredLayoutDraft replaceDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required Digest expectedDraftDigest,
    required LayoutDraft draft,
  }) => _transactional(() {
    var state = _load();
    final key = _subjectKey(draft.subject);
    final current = state.drafts[key];
    if (current == null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.draftNotFound,
      );
    }
    if (current.ownerPrincipalId != ownerPrincipalId) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.ownerConflict,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    if (current.draft.digest != expectedDraftDigest) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.staleDraft,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    _validateSuccessor(current.draft, draft);
    final baseLayout = _readBaseLayout(current);
    const LayoutDraftEngine().validateDraft(
      draft: draft,
      baseLayout: baseLayout,
    );
    if (current.draft.revision >= maxDraftMutations) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    final next = StoredLayoutDraft(
      ownerPrincipalId: current.ownerPrincipalId,
      draft: draft,
      baseLayoutBlobDigest: current.baseLayoutBlobDigest,
    );
    state =
        _appendEvent(state, _JournalEventType.replaceDraft, <String, Object?>{
          'subject': draft.subject.toJson(),
          'expectedDraftDigest': expectedDraftDigest.value,
          'storedDraft': _storedDraftJson(next),
        });
    _persist(state);
    return state.drafts[key]!;
  });

  void closeDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required AuthoringSubjectRef subject,
    required Digest expectedDraftDigest,
  }) => _transactional(() {
    var state = _load();
    final key = _subjectKey(subject);
    final current = state.drafts[key];
    if (current == null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.draftNotFound,
      );
    }
    if (current.ownerPrincipalId != ownerPrincipalId) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.ownerConflict,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    if (current.draft.digest != expectedDraftDigest) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.staleDraft,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    state = _appendEvent(state, _JournalEventType.closeDraft, <String, Object?>{
      'subject': subject.toJson(),
      'expectedDraftDigest': expectedDraftDigest.value,
    });
    _persist(state);
  });

  LayoutDraftAbandonReceipt abandonDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required LayoutDraftAbandonReceipt receipt,
  }) => _transactional(() {
    var state = _load();
    final existing = state.abandonReceipts
        .where((candidate) => candidate.requestId == receipt.requestId)
        .toList(growable: false);
    if (existing.isNotEmpty) {
      if (existing.single.digest != receipt.digest) {
        throw const ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.requestConflict,
        );
      }
      return existing.single;
    }
    final key = _subjectKey(receipt.subject);
    final current = state.drafts[key];
    if (current == null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.draftNotFound,
      );
    }
    if (current.ownerPrincipalId != ownerPrincipalId) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.ownerConflict,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    if (receipt.draftId != current.draft.id ||
        receipt.finalDraftDigest != current.draft.digest ||
        receipt.finalDraftRevision != current.draft.revision ||
        receipt.sourceDigest != current.draft.baseSourceDigest) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.staleDraft,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    if (state.pendingPromotions.values.any(
      (promotion) => promotion.subject == receipt.subject,
    )) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    state = _appendEvent(
      state,
      _JournalEventType.abandonDraft,
      <String, Object?>{'receipt': receipt.toJson()},
    );
    _persist(state);
    return state.abandonReceipts.last;
  });

  StoredProjectionLayoutPromotion preparePromotion({
    required StoredProjectionLayoutPromotion promotion,
    required List<int> originalSourceBytes,
    required List<int> candidateSourceBytes,
  }) => _transactional(() {
    var state = _load();
    final existing = state.pendingPromotions[promotion.intentId];
    if (existing != null) {
      if (!_storedPromotionEqual(existing, promotion)) {
        throw const ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.requestConflict,
        );
      }
      return existing;
    }
    final committed = state.promotionReceipts
        .where((receipt) => receipt.id == promotion.receipt.id)
        .toList(growable: false);
    if (committed.isNotEmpty) {
      if (committed.single.digest != promotion.receipt.digest) {
        throw const ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.requestConflict,
        );
      }
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    final current = state.drafts[_subjectKey(promotion.subject)];
    if (current == null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.draftNotFound,
      );
    }
    final receipt = promotion.receipt;
    if (receipt.draftId != current.draft.id ||
        receipt.draftDigest != current.draft.digest ||
        receipt.draftRevision != current.draft.revision ||
        receipt.sourceDigest != current.draft.baseSourceDigest ||
        receipt.previousContentSetDigest != current.draft.contentSetDigest ||
        receipt.layoutDigest != current.draft.candidateLayoutDigest) {
      throw ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.staleDraft,
        currentDigest: current.draft.digest,
        currentRevision: current.draft.revision,
      );
    }
    if (state.pendingPromotions.values.any(
      (candidate) =>
          candidate.subject == promotion.subject ||
          _promotionPathConflicts(candidate, promotion),
    )) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    try {
      _validateReceiptChain(
        promotion.receipt,
        state.completedPromotions.values,
      );
    } on FormatException {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    if (state.completedPromotions.values
            .where((receipt) => receipt.subject == promotion.subject)
            .length >=
        maxPromotionReceiptsPerSubject) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    final effectAttempt = promotion.successAttempt;
    if (effectAttempt != null) {
      final grant = state.grants[effectAttempt.grantId!.value];
      if (state.attempts.containsKey(effectAttempt.requestId.value) ||
          state.attempts.length + _pendingEffectCount(state) >=
              maxStoredAttempts ||
          grant == null ||
          grant.state != StoredAuthoringGrantState.active ||
          !_promotionAttemptMatchesGrant(effectAttempt, grant)) {
        throw const ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.grantMismatch,
        );
      }
    }
    _validateRelativeSourcePath(promotion.relativeSourcePath);
    if (originalSourceBytes.length > _maxPromotionSourceBytes ||
        candidateSourceBytes.length > _maxPromotionSourceBytes ||
        Digest.bytes(originalSourceBytes) != promotion.originalSourceDigest ||
        Digest.bytes(candidateSourceBytes) != promotion.candidateSourceDigest ||
        promotion.originalSourceBlobDigest != promotion.originalSourceDigest ||
        promotion.candidateSourceBlobDigest !=
            promotion.candidateSourceDigest) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    _putBlobBounded(originalSourceBytes, maxBytes: _maxPromotionSourceBytes);
    _putBlobBounded(candidateSourceBytes, maxBytes: _maxPromotionSourceBytes);
    state = _appendEvent(
      state,
      _JournalEventType.preparePromotion,
      <String, Object?>{'promotion': _storedPromotionJson(promotion)},
    );
    _persist(state);
    return state.pendingPromotions[promotion.intentId]!;
  });

  List<StoredProjectionLayoutPromotion> pendingPromotions() => _transactional(
    () => List<StoredProjectionLayoutPromotion>.unmodifiable(
      _load().pendingPromotions.values,
    ),
  );

  StoredProjectionLayoutPromotion? findPendingPromotion(String intentId) =>
      _transactional(() => _load().pendingPromotions[intentId]);

  ExperiencePromotionReceipt? findCompletedPromotion(String intentId) =>
      _transactional(() => _load().completedPromotions[intentId]);

  List<int> readPromotionSourceBlob(Digest digest) => _transactional(() {
    final bytes = _readBlobBoundedSafe(
      digest,
      maxBytes: _maxPromotionSourceBytes,
    );
    if (bytes == null || Digest.bytes(bytes) != digest) {
      throw const FormatException('Promotion source CAS blob is missing');
    }
    return List<int>.unmodifiable(bytes);
  });

  ExperiencePromotionReceipt commitPromotion({required String intentId}) =>
      _transactional(() {
        var state = _load();
        final pending = state.pendingPromotions[intentId];
        if (pending == null) {
          final committed = state.completedPromotions[intentId];
          if (committed != null) return committed;
          throw const ExperienceAuthoringStoreFailure(
            ExperienceAuthoringStoreErrorCode.promotionConflict,
          );
        }
        final current = state.drafts[_subjectKey(pending.subject)];
        if (pending.successAttempt != null) {
          throw const ExperienceAuthoringStoreFailure(
            ExperienceAuthoringStoreErrorCode.promotionConflict,
          );
        }
        if (current == null ||
            current.draft.id != pending.receipt.draftId ||
            current.draft.digest != pending.receipt.draftDigest ||
            current.draft.revision != pending.receipt.draftRevision) {
          throw const ExperienceAuthoringStoreFailure(
            ExperienceAuthoringStoreErrorCode.staleDraft,
          );
        }
        state = _appendEvent(
          state,
          _JournalEventType.commitPromotion,
          <String, Object?>{'intentId': intentId},
        );
        _persist(state);
        return state.completedPromotions[intentId]!;
      });

  StoredAuthoringAttempt finalizePromotionEffect({
    required String intentId,
    required StoredPromotionFinalization outcome,
  }) => _transactional(() {
    final state = _load();
    final pending = state.pendingPromotions[intentId];
    if (pending == null) {
      final completed = state.completedPromotions[intentId];
      if (completed != null &&
          outcome == StoredPromotionFinalization.committed) {
        final attempt = state.attempts.values
            .where(
              (candidate) =>
                  candidate.family ==
                      StoredAuthoringAttemptFamily.promotionApply &&
                  !candidate.isError &&
                  ExperiencePromotionApplyResult.fromJson(
                        candidate.terminalJson,
                      ).receipt.digest ==
                      completed.digest,
            )
            .singleOrNull;
        if (attempt != null) return attempt;
      }
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    final attempt = outcome == StoredPromotionFinalization.committed
        ? pending.successAttempt
        : pending.rollbackAttempt;
    if (attempt == null || attempt.grantId == null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    return commitAtomic(
      ExperienceAuthoringAtomicCommit(
        attempt: attempt,
        consumedGrantId: attempt.grantId,
        promotionIntentId: intentId,
        promotionOutcome: outcome,
      ),
    );
  });

  void rollbackPromotion({required String intentId}) => _transactional(() {
    var state = _load();
    final pending = state.pendingPromotions[intentId];
    if (pending == null) return;
    if (pending.successAttempt != null) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    state = _appendEvent(
      state,
      _JournalEventType.rollbackPromotion,
      <String, Object?>{'intentId': intentId},
    );
    _persist(state);
  });

  void resolveFailedPromotion({required String intentId}) => _transactional(() {
    var state = _load();
    final pending = state.pendingPromotions[intentId];
    if (pending == null) return;
    final rollback = pending.rollbackAttempt;
    final terminal = rollback == null
        ? null
        : state.attempts[rollback.requestId.value];
    final grant = rollback?.grantId == null
        ? null
        : state.grants[rollback!.grantId!.value];
    if (rollback == null ||
        terminal == null ||
        !_storedAttemptEqual(terminal, rollback) ||
        grant?.state != StoredAuthoringGrantState.consumed) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.promotionConflict,
      );
    }
    state = _appendEvent(
      state,
      _JournalEventType.resolveFailedPromotion,
      <String, Object?>{'intentId': intentId},
    );
    _persist(state);
  });

  List<ExperiencePromotionReceipt> promotionHistory(
    AuthoringSubjectRef subject, {
    int limit = experienceAuthoringMaxPromotionReceipts,
  }) => _transactional(() {
    if (limit < 1 || limit > experienceAuthoringMaxPromotionReceipts) {
      throw ArgumentError.value(limit, 'limit');
    }
    final matches = _load().promotionReceipts
        .where((receipt) => receipt.subject == subject)
        .toList(growable: false);
    return List<ExperiencePromotionReceipt>.unmodifiable(
      matches.skip(matches.length > limit ? matches.length - limit : 0),
    );
  });

  StoredPromotionReceiptPage promotionHistoryPage(
    AuthoringSubjectRef subject, {
    required int offset,
    required int limit,
  }) => _transactional(() {
    if (offset < 0 ||
        offset > experienceAuthoringMaxSafeInteger ||
        limit < 1 ||
        limit > experienceAuthoringMaxPromotionReceipts) {
      throw ArgumentError('Invalid promotion history page');
    }
    final matches = _load().promotionReceipts
        .where((receipt) => receipt.subject == subject)
        .toList(growable: false);
    if (offset > matches.length || (matches.isEmpty && offset != 0)) {
      throw ArgumentError.value(offset, 'offset');
    }
    final end = offset + limit < matches.length
        ? offset + limit
        : matches.length;
    return StoredPromotionReceiptPage(
      offset: offset,
      limit: limit,
      totalCount: matches.length,
      previousPageReceiptDigest: offset == 0
          ? null
          : matches[offset - 1].digest,
      receipts: matches.sublist(offset, end),
    );
  });

  List<LayoutDraftAbandonReceipt> abandonHistory(
    AuthoringSubjectRef subject, {
    int limit = experienceAuthoringMaxPromotionReceipts,
  }) => _transactional(() {
    if (limit < 1 || limit > experienceAuthoringMaxPromotionReceipts) {
      throw ArgumentError.value(limit, 'limit');
    }
    final matches = _load().abandonReceipts
        .where((receipt) => receipt.subject == subject)
        .toList(growable: false);
    return List<LayoutDraftAbandonReceipt>.unmodifiable(
      matches.skip(matches.length > limit ? matches.length - limit : 0),
    );
  });

  int abandonReceiptCount(AuthoringSubjectRef subject) => _transactional(
    () => _load().abandonReceipts
        .where((receipt) => receipt.subject == subject)
        .length,
  );

  LayoutDraftAbandonReceipt? findAbandonReceipt(AuthoringRequestId requestId) =>
      _transactional(() {
        final matches = _load().abandonReceipts
            .where((receipt) => receipt.requestId == requestId)
            .toList(growable: false);
        if (matches.length > 1) {
          throw const FormatException('Duplicate abandon request receipt');
        }
        return matches.firstOrNull;
      });

  /// Retains an immutable base layout before an atomic authoring transition.
  /// A failed transition may leave an unreachable CAS blob, but can never
  /// expose a draft without its exact base bytes.
  Digest retainBaseLayout(ProjectionLayoutManifest baseLayout) =>
      _transactional(
        () => _putBlobBounded(
          _encodeBaseLayout(baseLayout),
          maxBytes: _maxBaseLayoutBytes,
        ),
      );

  StoredAuthoringAttempt? findAttempt(AuthoringRequestId requestId) =>
      _transactional(() => _load().attempts[requestId.value]);

  StoredAuthoringGrant? findGrant(AuthoringActionGrantId grantId) =>
      _transactional(() => _load().grants[grantId.value]);

  AuthoringGrantIntent grantIntent(StoredAuthoringGrant stored) =>
      decodeStoredAuthoringGrantIntent(stored.intentKind, stored.intentJson);

  ExperienceChangeSet? findChangeSet({
    required AuthoringSubjectRef subject,
    required ExperienceChangeSetId id,
    Digest? expectedDigest,
  }) => _transactional(() {
    final value = _load().changeSets[id.value];
    if (value == null || value.subject != subject) return null;
    if (expectedDigest != null && value.digest != expectedDigest) return null;
    return value;
  });

  ExperienceReviewPacket? findReviewPacket({
    required AuthoringSubjectRef subject,
    required ExperienceReviewPacketId id,
    Digest? expectedDigest,
  }) => _transactional(() {
    final state = _load();
    final ExperienceReviewPacket? value;
    if (expectedDigest != null) {
      value = state.reviewPackets[_reviewKey(id, expectedDigest)];
    } else {
      value = state.latestReviewPackets[id.value];
    }
    return value == null || value.subject != subject ? null : value;
  });

  ExperiencePromotionReceipt? findPromotionReceipt({
    required AuthoringSubjectRef subject,
    required ExperiencePromotionReceiptId id,
    Digest? expectedDigest,
  }) => _transactional(() {
    final matches = _load().completedPromotions.values
        .where(
          (receipt) =>
              receipt.subject == subject &&
              receipt.id == id &&
              (expectedDigest == null || receipt.digest == expectedDigest),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      throw const FormatException('Duplicate promotion receipt ID');
    }
    return matches.firstOrNull;
  });

  ExperienceAuthoringSubjectHead subjectHead(AuthoringSubjectRef subject) =>
      _transactional(() => _load().subjectHead(subject));

  /// Commits grant issuance or one terminal effect as one journal event.
  /// The event owns grant consumption and every public state delta so an
  /// atomic writer that persists and then throws remains exactly replayable.
  StoredAuthoringAttempt commitAtomic(
    ExperienceAuthoringAtomicCommit commit,
  ) => _transactional(() {
    var state = _load();
    final existing = state.attempts[commit.attempt.requestId.value];
    if (existing != null) {
      if (!_storedAttemptEqual(existing, commit.attempt)) {
        throw const ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.requestConflict,
        );
      }
      return existing;
    }
    if (commit.attempt.family == StoredAuthoringAttemptFamily.draftMutation &&
        !commit.attempt.isError &&
        commit.nextDraft != null &&
        commit.expectedDraftDigest != null) {
      final current = state.drafts[_subjectKey(commit.attempt.subject)];
      if (current != null &&
          current.draft.digest == commit.expectedDraftDigest &&
          current.draft.revision >= maxDraftMutations) {
        throw ExperienceAuthoringStoreFailure(
          ExperienceAuthoringStoreErrorCode.quotaExceeded,
          currentDigest: current.draft.digest,
          currentRevision: current.draft.revision,
        );
      }
    }
    final finalizesReservedPromotion =
        commit.promotionIntentId != null &&
        state
                .pendingPromotions[commit.promotionIntentId]
                ?.successAttempt
                ?.requestId ==
            commit.attempt.requestId;
    if (state.attempts.length +
                _pendingEffectCount(state) -
                (finalizesReservedPromotion ? 1 : 0) >=
            maxStoredAttempts ||
        commit.issuedGrant != null && state.grants.length >= maxStoredGrants) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    final additionalReviewObjects =
        (commit.changeSet == null ? 0 : 1) +
        (commit.reviewPacket == null ? 0 : 1);
    if (state.changeSets.length +
            state.reviewPackets.length +
            additionalReviewObjects >
        maxStoredReviewObjects) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    state = _appendEvent(
      state,
      _JournalEventType.atomicCommit,
      _atomicCommitJson(commit),
    );
    _persist(state);
    return state.attempts[commit.attempt.requestId.value]!;
  });

  int revokeAllActive({required String reason, required DateTime at}) =>
      _revokeWhere((_) => true, reason: reason, at: at);

  int revokeAllForSubject(
    AuthoringSubjectRef subject, {
    required String reason,
    required DateTime at,
  }) => _revokeWhere(
    (stored) => stored.grant.subject == subject,
    reason: reason,
    at: at,
  );

  int revokeAllForAuthority(
    AuthoringAuthorityId authorityId, {
    required String reason,
    required DateTime at,
  }) => _revokeWhere(
    (stored) => stored.grant.authorityId == authorityId,
    reason: reason,
    at: at,
  );

  int revokeAllForConnectionEpoch(
    String connectionEpoch, {
    required String reason,
    required DateTime at,
  }) => _revokeWhere(
    (stored) => stored.connectionEpoch == connectionEpoch,
    reason: reason,
    at: at,
  );

  int _revokeWhere(
    bool Function(StoredAuthoringGrant stored) predicate, {
    required String reason,
    required DateTime at,
  }) => _transactional(() {
    if (reason.trim().isEmpty || utf8.encode(reason).length > 128) {
      throw ArgumentError.value(reason, 'reason');
    }
    var state = _load();
    final ids =
        state.grants.values
            .where(
              (stored) =>
                  stored.state == StoredAuthoringGrantState.active &&
                  predicate(stored),
            )
            .map((stored) => stored.grant.id.value)
            .toList(growable: false)
          ..sort();
    if (ids.isEmpty) return 0;
    state = _appendEvent(
      state,
      _JournalEventType.revokeGrants,
      <String, Object?>{
        'grantIds': ids,
        'reason': reason,
        'revokedAt': at.toUtc().toIso8601String(),
      },
    );
    _persist(state);
    return ids.length;
  });

  ProjectionLayoutManifest _readBaseLayout(StoredLayoutDraft stored) {
    final bytes = _readBlobBoundedSafe(
      stored.baseLayoutBlobDigest,
      maxBytes: _maxBaseLayoutBytes,
    );
    if (bytes == null) {
      throw const FormatException('Stored base layout CAS blob is missing');
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Stored base layout is not an object');
    }
    final canonical = const JcsCanonicalizer().canonicalize(decoded);
    if (text != '$canonical\n') {
      throw const FormatException('Stored base layout is not canonical');
    }
    final layout = ProjectionLayoutManifest.fromJson(decoded);
    if (layout.digest != stored.draft.baseLayoutDigest ||
        layout.topologyDigest != stored.draft.topologyDigest ||
        layout.projectionId != stored.draft.subject.projectionId) {
      throw const FormatException('Stored base layout authority is invalid');
    }
    return layout;
  }

  List<int> _encodeBaseLayout(ProjectionLayoutManifest baseLayout) {
    final canonical = const JcsCanonicalizer().canonicalize(
      baseLayout.toJson(),
    );
    final bytes = utf8.encode('$canonical\n');
    if (bytes.length > _maxBaseLayoutBytes) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    return bytes;
  }

  Digest _putBlobBounded(List<int> bytes, {required int maxBytes}) {
    if (bytes.length > maxBytes) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    final digest = Digest.bytes(bytes);
    final relativePath = p.join(
      'cas',
      'sha256',
      digest.value.substring('sha256:'.length),
    );
    final path = p.join(workspaceStore.stateRoot, relativePath);
    final type = _safeEntityType(path);
    var wrote = false;
    if (type == FileSystemEntityType.notFound) {
      _writeDurably(relativePath: relativePath, bytes: bytes);
      wrote = true;
    } else if (type != FileSystemEntityType.file) {
      throw FileSystemException('CAS entry must be a regular file', path);
    }
    final existing = _readBlobBoundedSafe(
      digest,
      maxBytes: maxBytes,
      expectedSize: bytes.length,
    );
    if (existing == null || !_bytesEqual(existing, bytes)) {
      if (wrote) _durabilityUncertain = true;
      throw StateError('CAS corruption at $path');
    }
    return digest;
  }

  List<int>? _readBlobBoundedSafe(
    Digest digest, {
    required int maxBytes,
    int? expectedSize,
  }) {
    final path = p.join(
      workspaceStore.stateRoot,
      'cas',
      'sha256',
      digest.value.substring('sha256:'.length),
    );
    final initialType = _safeEntityType(path);
    if (initialType == FileSystemEntityType.notFound) return null;
    if (initialType != FileSystemEntityType.file) {
      throw FileSystemException('CAS entry must be a regular file', path);
    }
    final file = File(path);
    final initialSize = file.statSync().size;
    if (initialSize > maxBytes ||
        expectedSize != null && initialSize != expectedSize) {
      throw StateError('CAS blob size is outside the bounded read');
    }
    final bytes = workspaceStore.readBlobBounded(
      digest,
      maxBytes: maxBytes,
      expectedSize: expectedSize,
    );
    final finalType = _safeEntityType(path);
    if (finalType != FileSystemEntityType.file ||
        File(path).statSync().size != initialSize) {
      throw StateError('CAS entry changed during the bounded read');
    }
    if (bytes != null) {
      _reproveDurably(
        relativePath: p.join(
          'cas',
          'sha256',
          digest.value.substring('sha256:'.length),
        ),
        bytes: bytes,
      );
    }
    return bytes;
  }

  void _validateSuccessor(LayoutDraft previous, LayoutDraft next) {
    if (next.id != previous.id ||
        next.subject != previous.subject ||
        next.baseLayoutDigest != previous.baseLayoutDigest ||
        next.baseSourceDigest != previous.baseSourceDigest ||
        next.topologyDigest != previous.topologyDigest ||
        next.contentSetDigest != previous.contentSetDigest ||
        next.revision != previous.revision + 1 ||
        next.previousDraftDigest != previous.digest) {
      throw StateError('LayoutDraft does not extend the exact current head');
    }
  }

  _JournalState _appendEvent(
    _JournalState state,
    _JournalEventType type,
    Map<String, Object?> payload,
  ) {
    final appended = state.add(type, payload);
    return appended.entries.length > maxJournalEntries
        ? appended.compact()
        : appended;
  }

  void _validateRelativeSourcePath(String value) {
    final normalized = p.normalize(value);
    if (p.isAbsolute(value) ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized != value) {
      throw ArgumentError.value(value, 'relativeSourcePath');
    }
  }

  _JournalState _load() {
    if (_durabilityUncertain) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unproven,
      );
    }
    final stateType = _safeEntityType(stateFilePath);
    if (stateType != FileSystemEntityType.notFound &&
        stateType != FileSystemEntityType.file) {
      throw FileSystemException(
        'Experience authoring journal must be a regular file',
        stateFilePath,
      );
    }
    final bytes = workspaceStore.readStateBytesBounded(
      statePath,
      maxBytes: _maxStateBytes,
    );
    if (bytes == null) return _JournalState.empty();
    if (bytes.isEmpty) {
      throw const FormatException('Experience authoring journal is empty');
    }
    // Parse into a private candidate only. The candidate does not become
    // authority until every referenced CAS antecedent is re-proven and the
    // journal itself is re-proven last. Reversing that order could make a WAL
    // durable while an unproven CAS dirent is still power-loss-unsafe.
    final text = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> ||
        decoded.length != 3 ||
        decoded['schemaVersion'] != 1 ||
        decoded['kind'] != 'ExperienceAuthoringJournal' ||
        decoded['entries'] is! List<Object?>) {
      throw const FormatException('Invalid Experience authoring journal');
    }
    final canonical = const JcsCanonicalizer().canonicalize(decoded);
    if (text != '$canonical\n') {
      throw const FormatException(
        'Experience authoring journal is not canonical',
      );
    }
    final rawEntries = decoded['entries']! as List<Object?>;
    if (rawEntries.length > maxJournalEntries) {
      throw const FormatException('Experience authoring journal exceeds quota');
    }
    var state = _JournalState.empty();
    for (final raw in rawEntries) {
      final event = _JournalEvent.fromJson(
        raw,
        expectedSequence: state.entries.length + 1,
        expectedPreviousDigest: state.entries.lastOrNull?.digest,
      );
      state = state.replay(event);
    }
    if (state.grants.length > maxStoredGrants ||
        state.attempts.length + _pendingEffectCount(state) >
            maxStoredAttempts ||
        state.changeSets.length + state.reviewPackets.length >
            maxStoredReviewObjects) {
      throw const FormatException(
        'Experience authoring durable authority exceeds quota',
      );
    }
    for (final draft in state.drafts.values) {
      final base = _readBaseLayout(draft);
      const LayoutDraftEngine().validateDraft(
        draft: draft.draft,
        baseLayout: base,
      );
    }
    for (final promotion in state.pendingPromotions.values) {
      for (final digest in <Digest>[
        promotion.originalSourceBlobDigest,
        promotion.candidateSourceBlobDigest,
      ]) {
        final source = _readBlobBoundedSafe(
          digest,
          maxBytes: _maxPromotionSourceBytes,
        );
        if (source == null || Digest.bytes(source) != digest) {
          throw const FormatException('Promotion source CAS is invalid');
        }
      }
    }
    // A visible journal is not necessarily durable. A prior process may have
    // failed after rename but before the parent-directory fsync, and older
    // writers did not prove directory entries at all. This is deliberately
    // the final proof, after all CAS dependencies above.
    _reproveDurably(relativePath: statePath, bytes: bytes);
    return state;
  }

  void _persist(_JournalState state) {
    final document = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'ExperienceAuthoringJournal',
      'entries': state.entries.map((event) => event.toJson()).toList(),
    };
    final canonical = const JcsCanonicalizer().canonicalize(document);
    final bytes = utf8.encode('$canonical\n');
    if (bytes.length > _maxStateBytes) {
      throw const ExperienceAuthoringStoreFailure(
        ExperienceAuthoringStoreErrorCode.quotaExceeded,
      );
    }
    final initialType = _safeEntityType(stateFilePath);
    if (initialType != FileSystemEntityType.notFound &&
        initialType != FileSystemEntityType.file) {
      throw FileSystemException(
        'Experience authoring journal must be a regular file',
        stateFilePath,
      );
    }
    final expectedCurrentBytes = initialType == FileSystemEntityType.file
        ? workspaceStore.readStateBytesBounded(
            statePath,
            maxBytes: _maxStateBytes,
          )
        : null;
    if (initialType == FileSystemEntityType.file &&
        expectedCurrentBytes == null) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unproven,
      );
    }
    _writeDurably(
      relativePath: statePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
    if (_safeEntityType(stateFilePath) != FileSystemEntityType.file) {
      throw FileSystemException(
        'Experience authoring writer did not create a regular file',
        stateFilePath,
      );
    }
    final committed = workspaceStore.readStateBytesBounded(
      statePath,
      maxBytes: bytes.length,
    );
    if (committed == null || !_bytesEqual(committed, bytes)) {
      _durabilityUncertain = true;
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unproven,
      );
    }
  }

  ExperienceAuthoringDurableWriteReceipt _writeDurably({
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    if (!writer.isDurabilitySupported) {
      throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
    }
    try {
      final receipt = writer.write(
        workspaceStore: workspaceStore,
        relativePath: relativePath,
        bytes: bytes,
        expectedCurrentBytes: expectedCurrentBytes,
      );
      if (receipt.protocol != experienceAuthoringDurableWriteProtocol ||
          receipt.workspaceAuthorityDigest !=
              _authoringStateAuthorityDigest(workspaceStore) ||
          receipt.relativePath != relativePath ||
          receipt.digest != Digest.bytes(bytes) ||
          receipt.byteLength != bytes.length) {
        _durabilityUncertain = true;
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      return receipt;
    } on ExperienceAuthoringStateDurabilityFailure {
      _durabilityUncertain = true;
      rethrow;
    }
  }

  ExperienceAuthoringDurableWriteReceipt _reproveDurably({
    required String relativePath,
    required List<int> bytes,
  }) {
    if (!writer.isDurabilitySupported) {
      throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
    }
    try {
      final receipt = writer.reproveExisting(
        workspaceStore: workspaceStore,
        relativePath: relativePath,
        bytes: bytes,
      );
      if (receipt.protocol != experienceAuthoringDurableWriteProtocol ||
          receipt.workspaceAuthorityDigest !=
              _authoringStateAuthorityDigest(workspaceStore) ||
          receipt.relativePath != relativePath ||
          receipt.digest != Digest.bytes(bytes) ||
          receipt.byteLength != bytes.length) {
        _durabilityUncertain = true;
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      return receipt;
    } on ExperienceAuthoringStateDurabilityFailure {
      _durabilityUncertain = true;
      rethrow;
    }
  }

  T _locked<T>(T Function() action) => workspaceStore.withExclusiveLock(() {
    final claim = _acquireInProcessClaim();
    try {
      return action();
    } finally {
      claim.release();
    }
  });

  T _transactional<T>(T Function() action) {
    if (_activeTransaction != null) return _synchronous(action());
    return withTransaction((_) => action());
  }

  T _synchronous<T>(T result) {
    if (result is Future<dynamic>) {
      throw StateError(
        'Experience authoring transactions must remain synchronous',
      );
    }
    return result;
  }

  _LockClaim _acquireInProcessClaim() {
    final bindings = DefaultExperienceAuthoringStateWriter._bindings;
    if (ffi.Abi.current() != ffi.Abi.linuxX64 || bindings == null) {
      throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
    }
    return bindings.acquireGuard(
      workspaceStore: workspaceStore,
      relativePath: p.join('experience-authoring', _guardName),
      timeout: guardTimeout,
      boundaryHook: guardBoundaryHook,
    );
  }

  FileSystemEntityType _safeEntityType(String absolutePath) {
    final normalized = p.normalize(p.absolute(absolutePath));
    final workspaceRoot = p.normalize(workspaceStore.workspaceRoot);
    if (normalized != workspaceRoot && !p.isWithin(workspaceRoot, normalized)) {
      throw FileSystemException(
        'Experience authoring path escapes workspace',
        normalized,
      );
    }
    var current = workspaceRoot;
    final segments = p.split(p.relative(normalized, from: workspaceRoot));
    for (var index = 0; index < segments.length; index += 1) {
      current = p.join(current, segments[index]);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link || Link(current).existsSync()) {
        throw FileSystemException(
          'Symlink forbidden in Experience authoring path',
          current,
        );
      }
      if (index < segments.length - 1 &&
          type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Experience authoring parent must be a directory',
          current,
        );
      }
      if (index == segments.length - 1) return type;
    }
    return FileSystemEntityType.directory;
  }
}

final class ExperienceAuthoringStoreTransaction {
  ExperienceAuthoringStoreTransaction._(this._store);

  final FilesystemExperienceAuthoringStore _store;
  var _active = true;

  void _deactivate() => _active = false;

  T _within<T>(T Function() action) {
    if (!_active) {
      throw StateError('Experience authoring transaction scope has ended');
    }
    return action();
  }

  StoredLayoutDraftOpenResult openOrResumeDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) => _within(
    () => _store.openOrResumeDraft(
      ownerPrincipalId: ownerPrincipalId,
      draft: draft,
      baseLayout: baseLayout,
    ),
  );

  StoredLayoutDraft? findDraft(AuthoringSubjectRef subject) =>
      _within(() => _store.findDraft(subject));

  StoredLayoutDraft? findDraftById(LayoutDraftId draftId) =>
      _within(() => _store.findDraftById(draftId));

  StoredLayoutDraft requireDraft(AuthoringSubjectRef subject) =>
      _within(() => _store.requireDraft(subject));

  ProjectionLayoutManifest requireBaseLayout(StoredLayoutDraft stored) =>
      _within(() => _store.requireBaseLayout(stored));

  StoredLayoutDraft replaceDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required Digest expectedDraftDigest,
    required LayoutDraft draft,
  }) => _within(
    () => _store.replaceDraft(
      ownerPrincipalId: ownerPrincipalId,
      expectedDraftDigest: expectedDraftDigest,
      draft: draft,
    ),
  );

  void closeDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required AuthoringSubjectRef subject,
    required Digest expectedDraftDigest,
  }) => _within(
    () => _store.closeDraft(
      ownerPrincipalId: ownerPrincipalId,
      subject: subject,
      expectedDraftDigest: expectedDraftDigest,
    ),
  );

  LayoutDraftAbandonReceipt abandonDraft({
    required AuthoringPrincipalId ownerPrincipalId,
    required LayoutDraftAbandonReceipt receipt,
  }) => _within(
    () => _store.abandonDraft(
      ownerPrincipalId: ownerPrincipalId,
      receipt: receipt,
    ),
  );

  StoredProjectionLayoutPromotion preparePromotion({
    required StoredProjectionLayoutPromotion promotion,
    required List<int> originalSourceBytes,
    required List<int> candidateSourceBytes,
  }) => _within(
    () => _store.preparePromotion(
      promotion: promotion,
      originalSourceBytes: originalSourceBytes,
      candidateSourceBytes: candidateSourceBytes,
    ),
  );

  List<StoredProjectionLayoutPromotion> pendingPromotions() =>
      _within(_store.pendingPromotions);

  StoredProjectionLayoutPromotion? findPendingPromotion(String intentId) =>
      _within(() => _store.findPendingPromotion(intentId));

  ExperiencePromotionReceipt? findCompletedPromotion(String intentId) =>
      _within(() => _store.findCompletedPromotion(intentId));

  List<int> readPromotionSourceBlob(Digest digest) =>
      _within(() => _store.readPromotionSourceBlob(digest));

  ExperiencePromotionReceipt commitPromotion({required String intentId}) =>
      _within(() => _store.commitPromotion(intentId: intentId));

  StoredAuthoringAttempt finalizePromotionEffect({
    required String intentId,
    required StoredPromotionFinalization outcome,
  }) => _within(
    () => _store.finalizePromotionEffect(intentId: intentId, outcome: outcome),
  );

  void rollbackPromotion({required String intentId}) =>
      _within(() => _store.rollbackPromotion(intentId: intentId));

  void resolveFailedPromotion({required String intentId}) =>
      _within(() => _store.resolveFailedPromotion(intentId: intentId));

  List<ExperiencePromotionReceipt> promotionHistory(
    AuthoringSubjectRef subject, {
    int limit = experienceAuthoringMaxPromotionReceipts,
  }) => _within(() => _store.promotionHistory(subject, limit: limit));

  StoredPromotionReceiptPage promotionHistoryPage(
    AuthoringSubjectRef subject, {
    required int offset,
    required int limit,
  }) => _within(
    () => _store.promotionHistoryPage(subject, offset: offset, limit: limit),
  );

  Digest retainBaseLayout(ProjectionLayoutManifest baseLayout) =>
      _within(() => _store.retainBaseLayout(baseLayout));

  StoredAuthoringAttempt? findAttempt(AuthoringRequestId requestId) =>
      _within(() => _store.findAttempt(requestId));

  StoredAuthoringGrant? findGrant(AuthoringActionGrantId grantId) =>
      _within(() => _store.findGrant(grantId));

  AuthoringGrantIntent grantIntent(StoredAuthoringGrant stored) =>
      _within(() => _store.grantIntent(stored));

  ExperienceChangeSet? findChangeSet({
    required AuthoringSubjectRef subject,
    required ExperienceChangeSetId id,
    Digest? expectedDigest,
  }) => _within(
    () => _store.findChangeSet(
      subject: subject,
      id: id,
      expectedDigest: expectedDigest,
    ),
  );

  ExperienceReviewPacket? findReviewPacket({
    required AuthoringSubjectRef subject,
    required ExperienceReviewPacketId id,
    Digest? expectedDigest,
  }) => _within(
    () => _store.findReviewPacket(
      subject: subject,
      id: id,
      expectedDigest: expectedDigest,
    ),
  );

  ExperiencePromotionReceipt? findPromotionReceipt({
    required AuthoringSubjectRef subject,
    required ExperiencePromotionReceiptId id,
    Digest? expectedDigest,
  }) => _within(
    () => _store.findPromotionReceipt(
      subject: subject,
      id: id,
      expectedDigest: expectedDigest,
    ),
  );

  ExperienceAuthoringSubjectHead subjectHead(AuthoringSubjectRef subject) =>
      _within(() => _store.subjectHead(subject));

  StoredAuthoringAttempt commitAtomic(ExperienceAuthoringAtomicCommit commit) =>
      _within(() => _store.commitAtomic(commit));

  int revokeAllActive({required String reason, required DateTime at}) =>
      _within(() => _store.revokeAllActive(reason: reason, at: at));

  int revokeAllForSubject(
    AuthoringSubjectRef subject, {
    required String reason,
    required DateTime at,
  }) => _within(
    () => _store.revokeAllForSubject(subject, reason: reason, at: at),
  );

  int revokeAllForAuthority(
    AuthoringAuthorityId authorityId, {
    required String reason,
    required DateTime at,
  }) => _within(
    () => _store.revokeAllForAuthority(authorityId, reason: reason, at: at),
  );

  int revokeAllForConnectionEpoch(
    String connectionEpoch, {
    required String reason,
    required DateTime at,
  }) => _within(
    () => _store.revokeAllForConnectionEpoch(
      connectionEpoch,
      reason: reason,
      at: at,
    ),
  );
}

final class _LockClaim {
  _LockClaim(this._release);

  final void Function() _release;
  var _active = true;

  void release() {
    if (!_active) return;
    _active = false;
    _release();
  }
}

enum _JournalEventType {
  checkpoint,
  openDraft,
  replaceDraft,
  closeDraft,
  abandonDraft,
  preparePromotion,
  commitPromotion,
  rollbackPromotion,
  resolveFailedPromotion,
  atomicCommit,
  revokeGrants,
}

final class _JournalEvent {
  _JournalEvent._({
    required this.sequence,
    required this.previousDigest,
    required this.type,
    required this.payload,
  });

  factory _JournalEvent.create({
    required int sequence,
    required Digest? previousDigest,
    required _JournalEventType type,
    required Map<String, Object?> payload,
  }) => _JournalEvent._(
    sequence: sequence,
    previousDigest: previousDigest,
    type: type,
    payload: Map<String, Object?>.unmodifiable(payload),
  );

  final int sequence;
  final Digest? previousDigest;
  final _JournalEventType type;
  final Map<String, Object?> payload;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'sequence': sequence,
    if (previousDigest != null) 'previousDigest': previousDigest!.value,
    'type': type.name,
    'payload': payload,
    if (includeDigest) 'digest': digest.value,
  };

  factory _JournalEvent.fromJson(
    Object? value, {
    required int expectedSequence,
    required Digest? expectedPreviousDigest,
  }) {
    final json = _object(value, 'ExperienceAuthoringJournalEntry');
    _only(json, const <String>{
      'sequence',
      'previousDigest',
      'type',
      'payload',
      'digest',
    }, 'ExperienceAuthoringJournalEntry');
    final sequence = json['sequence'];
    if (sequence is! int || sequence != expectedSequence) {
      throw const FormatException('Invalid authoring journal sequence');
    }
    final previous = json.containsKey('previousDigest')
        ? Digest(_string(json, 'previousDigest', 'AuthoringJournalEntry'))
        : null;
    if (previous != expectedPreviousDigest) {
      throw const FormatException('Broken authoring journal hash chain');
    }
    final rawType = _string(json, 'type', 'AuthoringJournalEntry');
    final type = _JournalEventType.values
        .where((candidate) => candidate.name == rawType)
        .firstOrNull;
    if (type == null) {
      throw const FormatException('Unknown authoring journal event type');
    }
    final event = _JournalEvent._(
      sequence: sequence,
      previousDigest: previous,
      type: type,
      payload: Map<String, Object?>.unmodifiable(
        _object(json['payload'], 'AuthoringJournalEntry.payload'),
      ),
    );
    if (Digest(_string(json, 'digest', 'AuthoringJournalEntry')) !=
        event.digest) {
      throw const FormatException('Authoring journal entry digest mismatch');
    }
    return event;
  }
}

final class _JournalState {
  const _JournalState({
    required this.entries,
    required this.drafts,
    required this.draftIds,
    required this.pendingPromotions,
    required this.completedPromotions,
    required this.abandonReceipts,
    required this.grants,
    required this.attempts,
    required this.changeSets,
    required this.reviewPackets,
    required this.latestReviewPackets,
    required this.currentChangeSetIds,
    required this.currentReviewKeys,
  });

  factory _JournalState.empty() => const _JournalState(
    entries: <_JournalEvent>[],
    drafts: <String, StoredLayoutDraft>{},
    draftIds: <String>{},
    pendingPromotions: <String, StoredProjectionLayoutPromotion>{},
    completedPromotions: <String, ExperiencePromotionReceipt>{},
    abandonReceipts: <LayoutDraftAbandonReceipt>[],
    grants: <String, StoredAuthoringGrant>{},
    attempts: <String, StoredAuthoringAttempt>{},
    changeSets: <String, ExperienceChangeSet>{},
    reviewPackets: <String, ExperienceReviewPacket>{},
    latestReviewPackets: <String, ExperienceReviewPacket>{},
    currentChangeSetIds: <String, String>{},
    currentReviewKeys: <String, String>{},
  );

  final List<_JournalEvent> entries;
  final Map<String, StoredLayoutDraft> drafts;
  final Set<String> draftIds;
  final Map<String, StoredProjectionLayoutPromotion> pendingPromotions;
  final Map<String, ExperiencePromotionReceipt> completedPromotions;
  final List<LayoutDraftAbandonReceipt> abandonReceipts;
  final Map<String, StoredAuthoringGrant> grants;
  final Map<String, StoredAuthoringAttempt> attempts;
  final Map<String, ExperienceChangeSet> changeSets;
  final Map<String, ExperienceReviewPacket> reviewPackets;
  final Map<String, ExperienceReviewPacket> latestReviewPackets;
  final Map<String, String> currentChangeSetIds;
  final Map<String, String> currentReviewKeys;

  ExperienceAuthoringSubjectHead subjectHead(AuthoringSubjectRef subject) {
    final key = _subjectKey(subject);
    final storedDraft = drafts[key];
    final changeSetId = currentChangeSetIds[key];
    final reviewKey = currentReviewKeys[key];
    final changeSet = changeSetId == null ? null : changeSets[changeSetId];
    final review = reviewKey == null ? null : reviewPackets[reviewKey];
    final promotions =
        completedPromotions.values
            .where((receipt) => receipt.subject == subject)
            .toList(growable: false)
          ..sort((left, right) => left.sequence.compareTo(right.sequence));
    return ExperienceAuthoringSubjectHead(
      subject: subject,
      draft: storedDraft == null
          ? null
          : LayoutDraftHeadRef.fromDraft(storedDraft.draft),
      changeSet: changeSet == null
          ? null
          : ExperienceChangeSetHeadRef.fromChangeSet(changeSet),
      review: review == null
          ? null
          : ExperienceReviewHeadRef.fromPacket(review),
      latestPromotion: promotions.isEmpty
          ? null
          : ExperiencePromotionHeadRef.fromReceipt(promotions.last),
    );
  }

  List<ExperiencePromotionReceipt> get promotionReceipts {
    final values = completedPromotions.values.toList(growable: false)
      ..sort((left, right) {
        final bySubject = _subjectKey(
          left.subject,
        ).compareTo(_subjectKey(right.subject));
        return bySubject != 0
            ? bySubject
            : left.sequence.compareTo(right.sequence);
      });
    return List<ExperiencePromotionReceipt>.unmodifiable(values);
  }

  _JournalState add(_JournalEventType type, Map<String, Object?> payload) =>
      replay(
        _JournalEvent.create(
          sequence: entries.length + 1,
          previousDigest: entries.lastOrNull?.digest,
          type: type,
          payload: payload,
        ),
      );

  /// Replaces a long event prefix with one canonical checkpoint linked to the
  /// exact prior head. This preserves terminal/recovery write capacity while
  /// retaining every live authority record and bounded public history.
  _JournalState compact() {
    if (entries.isEmpty) return this;
    final sortedDrafts = drafts.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedPending = pendingPromotions.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedCompleted = completedPromotions.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedGrants = grants.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedAttempts = attempts.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedChangeSets = changeSets.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedReviewPackets = reviewPackets.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedCurrentChangeSets = currentChangeSetIds.entries.toList(
      growable: false,
    )..sort((left, right) => left.key.compareTo(right.key));
    final sortedCurrentReviews = currentReviewKeys.entries.toList(
      growable: false,
    )..sort((left, right) => left.key.compareTo(right.key));
    final sortedIds = draftIds.toList(growable: false)..sort();
    final checkpoint = _JournalEvent.create(
      sequence: 1,
      previousDigest: null,
      type: _JournalEventType.checkpoint,
      payload: <String, Object?>{
        'compactedHeadDigest': entries.last.digest.value,
        'drafts': <Object?>[
          for (final entry in sortedDrafts) _storedDraftJson(entry.value),
        ],
        'draftIds': sortedIds,
        'pendingPromotions': <Object?>[
          for (final entry in sortedPending) _storedPromotionJson(entry.value),
        ],
        'completedPromotions': <Object?>[
          for (final entry in sortedCompleted)
            <String, Object?>{
              'intentId': entry.key,
              'receipt': entry.value.toJson(),
            },
        ],
        'abandonReceipts': <Object?>[
          for (final receipt in abandonReceipts) receipt.toJson(),
        ],
        'grants': <Object?>[
          for (final entry in sortedGrants) _storedGrantJson(entry.value),
        ],
        'attempts': <Object?>[
          for (final entry in sortedAttempts) _storedAttemptJson(entry.value),
        ],
        'changeSets': <Object?>[
          for (final entry in sortedChangeSets) entry.value.toJson(),
        ],
        'reviewPackets': <Object?>[
          for (final entry in sortedReviewPackets) entry.value.toJson(),
        ],
        'currentChangeSetIds': <Object?>[
          for (final entry in sortedCurrentChangeSets)
            <String, Object?>{'subjectKey': entry.key, 'id': entry.value},
        ],
        'currentReviewKeys': <Object?>[
          for (final entry in sortedCurrentReviews)
            <String, Object?>{'subjectKey': entry.key, 'key': entry.value},
        ],
      },
    );
    return _JournalState.empty().replay(checkpoint);
  }

  _JournalState replay(_JournalEvent event) {
    final nextDrafts = Map<String, StoredLayoutDraft>.of(drafts);
    final nextIds = Set<String>.of(draftIds);
    final nextPending = Map<String, StoredProjectionLayoutPromotion>.of(
      pendingPromotions,
    );
    final nextCompleted = Map<String, ExperiencePromotionReceipt>.of(
      completedPromotions,
    );
    var nextAbandons = List<LayoutDraftAbandonReceipt>.of(abandonReceipts);
    final nextGrants = Map<String, StoredAuthoringGrant>.of(grants);
    final nextAttempts = Map<String, StoredAuthoringAttempt>.of(attempts);
    final nextChangeSets = Map<String, ExperienceChangeSet>.of(changeSets);
    final nextReviewPackets = Map<String, ExperienceReviewPacket>.of(
      reviewPackets,
    );
    final nextLatestReviews = Map<String, ExperienceReviewPacket>.of(
      latestReviewPackets,
    );
    final nextCurrentChangeSetIds = Map<String, String>.of(currentChangeSetIds);
    final nextCurrentReviewKeys = Map<String, String>.of(currentReviewKeys);
    switch (event.type) {
      case _JournalEventType.checkpoint:
        if (entries.isNotEmpty ||
            nextDrafts.isNotEmpty ||
            nextIds.isNotEmpty ||
            nextPending.isNotEmpty ||
            nextCompleted.isNotEmpty ||
            nextAbandons.isNotEmpty ||
            nextGrants.isNotEmpty ||
            nextAttempts.isNotEmpty ||
            nextChangeSets.isNotEmpty ||
            nextReviewPackets.isNotEmpty ||
            nextLatestReviews.isNotEmpty ||
            nextCurrentChangeSetIds.isNotEmpty ||
            nextCurrentReviewKeys.isNotEmpty) {
          throw const FormatException(
            'Experience authoring checkpoint must be the first entry',
          );
        }
        _only(event.payload, const <String>{
          'compactedHeadDigest',
          'drafts',
          'draftIds',
          'pendingPromotions',
          'completedPromotions',
          'abandonReceipts',
          'grants',
          'attempts',
          'changeSets',
          'reviewPackets',
          'currentChangeSetIds',
          'currentReviewKeys',
        }, 'checkpoint');
        Digest(_string(event.payload, 'compactedHeadDigest', 'checkpoint'));
        final rawDraftIds = _list(event.payload, 'draftIds', 'checkpoint');
        for (final rawId in rawDraftIds) {
          if (rawId is! String || rawId.isEmpty || !nextIds.add(rawId)) {
            throw const FormatException('Invalid checkpoint draft IDs');
          }
        }
        for (final raw in _list(event.payload, 'drafts', 'checkpoint')) {
          final stored = _storedDraftFromJson(raw);
          final key = _subjectKey(stored.draft.subject);
          if (nextDrafts.containsKey(key) ||
              !nextIds.contains(stored.draft.id.value)) {
            throw const FormatException('Invalid checkpoint draft');
          }
          nextDrafts[key] = stored;
        }
        for (final raw in _list(
          event.payload,
          'pendingPromotions',
          'checkpoint',
        )) {
          final promotion = _storedPromotionFromJson(raw);
          if (nextPending.containsKey(promotion.intentId) ||
              nextPending.values.any(
                (current) =>
                    current.subject == promotion.subject ||
                    _promotionPathConflicts(current, promotion),
              )) {
            throw const FormatException('Invalid checkpoint promotion WAL');
          }
          _validatePromotionAgainstDraft(promotion, nextDrafts);
          nextPending[promotion.intentId] = promotion;
        }
        for (final raw in _list(
          event.payload,
          'completedPromotions',
          'checkpoint',
        )) {
          final value = _object(raw, 'checkpoint.completedPromotion');
          _only(value, const <String>{
            'intentId',
            'receipt',
          }, 'checkpoint.completedPromotion');
          final intentId = _string(
            value,
            'intentId',
            'checkpoint.completedPromotion',
          );
          final receipt = ExperiencePromotionReceipt.fromJson(value['receipt']);
          if (nextCompleted.containsKey(intentId) ||
              nextCompleted.values.any(
                (candidate) => candidate.id == receipt.id,
              )) {
            throw const FormatException(
              'Invalid checkpoint completed promotion',
            );
          }
          nextCompleted[intentId] = receipt;
        }
        _validateCompleteReceiptChains(nextCompleted.values);
        for (final raw in _list(
          event.payload,
          'abandonReceipts',
          'checkpoint',
        )) {
          final receipt = LayoutDraftAbandonReceipt.fromJson(raw);
          if (nextAbandons.any(
            (candidate) =>
                candidate.id == receipt.id ||
                candidate.requestId == receipt.requestId,
          )) {
            throw const FormatException('Invalid checkpoint abandon receipt');
          }
          nextAbandons.add(receipt);
        }
        for (final raw in _list(event.payload, 'grants', 'checkpoint')) {
          final stored = _storedGrantFromJson(raw);
          if (nextGrants.containsKey(stored.grant.id.value)) {
            throw const FormatException('Duplicate checkpoint grant');
          }
          _validateStoredGrant(stored);
          nextGrants[stored.grant.id.value] = stored;
        }
        for (final raw in _list(event.payload, 'attempts', 'checkpoint')) {
          final attempt = _storedAttemptFromJson(raw);
          if (nextAttempts.containsKey(attempt.requestId.value)) {
            throw const FormatException('Duplicate checkpoint attempt');
          }
          _validateAttemptTerminal(attempt);
          nextAttempts[attempt.requestId.value] = attempt;
        }
        for (final raw in _list(event.payload, 'changeSets', 'checkpoint')) {
          final changeSet = ExperienceChangeSet.fromJson(raw);
          if (nextChangeSets.containsKey(changeSet.id.value)) {
            throw const FormatException('Duplicate checkpoint ChangeSet');
          }
          nextChangeSets[changeSet.id.value] = changeSet;
        }
        final reviewList =
            _list(
                event.payload,
                'reviewPackets',
                'checkpoint',
              ).map(ExperienceReviewPacket.fromJson).toList(growable: false)
              ..sort((left, right) {
                final byId = left.id.value.compareTo(right.id.value);
                return byId != 0
                    ? byId
                    : left.revision.compareTo(right.revision);
              });
        for (final packet in reviewList) {
          _retainReviewPacket(
            packet,
            changeSets: nextChangeSets,
            reviewPackets: nextReviewPackets,
            latestReviewPackets: nextLatestReviews,
          );
        }
        for (final raw in _list(
          event.payload,
          'currentChangeSetIds',
          'checkpoint',
        )) {
          final value = _object(raw, 'checkpoint.currentChangeSetId');
          _only(value, const <String>{
            'subjectKey',
            'id',
          }, 'checkpoint.currentChangeSetId');
          final subjectKey = _string(
            value,
            'subjectKey',
            'checkpoint.currentChangeSetId',
          );
          final id = _string(value, 'id', 'checkpoint.currentChangeSetId');
          if (nextCurrentChangeSetIds.containsKey(subjectKey)) {
            throw const FormatException('Duplicate current ChangeSet head');
          }
          nextCurrentChangeSetIds[subjectKey] = id;
        }
        for (final raw in _list(
          event.payload,
          'currentReviewKeys',
          'checkpoint',
        )) {
          final value = _object(raw, 'checkpoint.currentReviewKey');
          _only(value, const <String>{
            'subjectKey',
            'key',
          }, 'checkpoint.currentReviewKey');
          final subjectKey = _string(
            value,
            'subjectKey',
            'checkpoint.currentReviewKey',
          );
          final key = _string(value, 'key', 'checkpoint.currentReviewKey');
          if (nextCurrentReviewKeys.containsKey(subjectKey)) {
            throw const FormatException('Duplicate current review head');
          }
          nextCurrentReviewKeys[subjectKey] = key;
        }
        _validateAuthorityState(
          drafts: nextDrafts,
          pendingPromotions: nextPending,
          completedPromotions: nextCompleted,
          abandonReceipts: nextAbandons,
          grants: nextGrants,
          attempts: nextAttempts,
          changeSets: nextChangeSets,
          reviewPackets: nextReviewPackets,
          currentChangeSetIds: nextCurrentChangeSetIds,
          currentReviewKeys: nextCurrentReviewKeys,
        );
      case _JournalEventType.openDraft:
        _only(event.payload, const <String>{'storedDraft'}, 'openDraft');
        final stored = _storedDraftFromJson(event.payload['storedDraft']);
        final key = _subjectKey(stored.draft.subject);
        if (nextDrafts.containsKey(key) ||
            !nextIds.add(stored.draft.id.value) ||
            stored.draft.revision != 0 ||
            stored.draft.previousDraftDigest != null) {
          throw const FormatException('Invalid openDraft journal transition');
        }
        nextDrafts[key] = stored;
      case _JournalEventType.replaceDraft:
        _only(event.payload, const <String>{
          'subject',
          'expectedDraftDigest',
          'storedDraft',
        }, 'replaceDraft');
        final subject = AuthoringSubjectRef.fromJson(event.payload['subject']);
        final key = _subjectKey(subject);
        final current = nextDrafts[key];
        final expected = Digest(
          _string(event.payload, 'expectedDraftDigest', 'replaceDraft'),
        );
        final stored = _storedDraftFromJson(event.payload['storedDraft']);
        if (current == null ||
            current.draft.digest != expected ||
            stored.ownerPrincipalId != current.ownerPrincipalId ||
            stored.baseLayoutBlobDigest != current.baseLayoutBlobDigest ||
            stored.draft.subject != subject) {
          throw const FormatException(
            'Invalid replaceDraft journal transition',
          );
        }
        _validateReplaySuccessor(current.draft, stored.draft);
        nextDrafts[key] = stored;
        nextCurrentChangeSetIds.remove(key);
        nextCurrentReviewKeys.remove(key);
      case _JournalEventType.closeDraft:
        _only(event.payload, const <String>{
          'subject',
          'expectedDraftDigest',
        }, 'closeDraft');
        final subject = AuthoringSubjectRef.fromJson(event.payload['subject']);
        final key = _subjectKey(subject);
        final current = nextDrafts[key];
        final expected = Digest(
          _string(event.payload, 'expectedDraftDigest', 'closeDraft'),
        );
        if (current == null || current.draft.digest != expected) {
          throw const FormatException('Invalid closeDraft journal transition');
        }
        nextDrafts.remove(key);
        nextCurrentChangeSetIds.remove(key);
        nextCurrentReviewKeys.remove(key);
      case _JournalEventType.abandonDraft:
        _only(event.payload, const <String>{'receipt'}, 'abandonDraft');
        final receipt = LayoutDraftAbandonReceipt.fromJson(
          event.payload['receipt'],
        );
        final key = _subjectKey(receipt.subject);
        final current = nextDrafts[key];
        if (current == null ||
            current.draft.id != receipt.draftId ||
            current.draft.digest != receipt.finalDraftDigest ||
            current.draft.revision != receipt.finalDraftRevision ||
            current.draft.baseSourceDigest != receipt.sourceDigest ||
            nextAbandons.any(
              (candidate) =>
                  candidate.id == receipt.id ||
                  candidate.requestId == receipt.requestId,
            ) ||
            nextPending.values.any(
              (promotion) => promotion.subject == receipt.subject,
            )) {
          throw const FormatException('Invalid abandonDraft transition');
        }
        nextDrafts.remove(key);
        nextCurrentChangeSetIds.remove(key);
        nextCurrentReviewKeys.remove(key);
        nextAbandons = <LayoutDraftAbandonReceipt>[...nextAbandons, receipt];
      case _JournalEventType.preparePromotion:
        _only(event.payload, const <String>{'promotion'}, 'preparePromotion');
        final promotion = _storedPromotionFromJson(event.payload['promotion']);
        if (nextPending.containsKey(promotion.intentId) ||
            nextCompleted.containsKey(promotion.intentId) ||
            nextCompleted.values.any(
              (receipt) => receipt.id == promotion.receipt.id,
            ) ||
            nextPending.values.any(
              (candidate) =>
                  candidate.subject == promotion.subject ||
                  _promotionPathConflicts(candidate, promotion),
            )) {
          throw const FormatException('Invalid preparePromotion transition');
        }
        _validatePromotionAgainstDraft(promotion, nextDrafts);
        _validateReceiptChain(promotion.receipt, nextCompleted.values);
        final successAttempt = promotion.successAttempt;
        if (successAttempt != null) {
          if (nextAttempts.containsKey(successAttempt.requestId.value)) {
            throw const FormatException(
              'Prepared promotion request is already terminal',
            );
          }
          final grant = nextGrants[successAttempt.grantId!.value];
          if (grant == null ||
              grant.state != StoredAuthoringGrantState.active ||
              !_promotionAttemptMatchesGrant(successAttempt, grant)) {
            throw const FormatException(
              'Prepared promotion does not reserve an active exact grant',
            );
          }
          nextGrants[grant.grant.id.value] = grant.withState(
            StoredAuthoringGrantState.inFlight,
            at: promotion.preparedAt,
          );
        }
        nextPending[promotion.intentId] = promotion;
      case _JournalEventType.commitPromotion:
        _only(event.payload, const <String>{'intentId'}, 'commitPromotion');
        final intentId = _string(event.payload, 'intentId', 'commitPromotion');
        final promotion = nextPending.remove(intentId);
        if (promotion == null ||
            promotion.successAttempt != null ||
            nextCompleted.containsKey(intentId)) {
          throw const FormatException('Invalid commitPromotion transition');
        }
        _validatePromotionAgainstDraft(promotion, nextDrafts);
        final subjectKey = _subjectKey(promotion.subject);
        nextDrafts.remove(subjectKey);
        nextCurrentChangeSetIds.remove(subjectKey);
        nextCurrentReviewKeys.remove(subjectKey);
        nextCompleted[intentId] = promotion.receipt;
      case _JournalEventType.rollbackPromotion:
        _only(event.payload, const <String>{'intentId'}, 'rollbackPromotion');
        final intentId = _string(
          event.payload,
          'intentId',
          'rollbackPromotion',
        );
        final rollbackPromotion = nextPending[intentId];
        if (rollbackPromotion == null ||
            rollbackPromotion.successAttempt != null) {
          throw const FormatException('Invalid rollbackPromotion transition');
        }
        nextPending.remove(intentId);
      case _JournalEventType.resolveFailedPromotion:
        _only(event.payload, const <String>{
          'intentId',
        }, 'resolveFailedPromotion');
        final intentId = _string(
          event.payload,
          'intentId',
          'resolveFailedPromotion',
        );
        final promotion = nextPending[intentId];
        final rollback = promotion?.rollbackAttempt;
        final terminal = rollback == null
            ? null
            : nextAttempts[rollback.requestId.value];
        final grant = rollback?.grantId == null
            ? null
            : nextGrants[rollback!.grantId!.value];
        if (promotion == null ||
            rollback == null ||
            terminal == null ||
            !_storedAttemptEqual(terminal, rollback) ||
            grant?.state != StoredAuthoringGrantState.consumed) {
          throw const FormatException('Invalid failed promotion resolution');
        }
        nextPending.remove(intentId);
      case _JournalEventType.atomicCommit:
        final commit = _atomicCommitFromJson(event.payload);
        final attempt = commit.attempt;
        if (nextAttempts.containsKey(attempt.requestId.value)) {
          throw const FormatException('Duplicate authoring attempt');
        }
        _validateAttemptTerminal(attempt);
        final promotionIntentId = commit.promotionIntentId;
        final promotionOutcome = commit.promotionOutcome;
        if ((promotionIntentId == null) != (promotionOutcome == null)) {
          throw const FormatException(
            'Promotion finalization metadata is incomplete',
          );
        }
        final effectPromotion = promotionIntentId == null
            ? null
            : nextPending[promotionIntentId];
        if (promotionIntentId != null) {
          final expectedAttempt =
              promotionOutcome == StoredPromotionFinalization.committed
              ? effectPromotion?.successAttempt
              : effectPromotion?.rollbackAttempt;
          if (effectPromotion == null ||
              expectedAttempt == null ||
              !_storedAttemptEqual(expectedAttempt, attempt)) {
            throw const FormatException(
              'Promotion finalization does not match its prepared request',
            );
          }
        }
        final issued = commit.issuedGrant;
        if (issued != null) {
          if (attempt.family != StoredAuthoringAttemptFamily.grantIssue ||
              attempt.isError ||
              commit.consumedGrantId != null ||
              nextGrants.containsKey(issued.grant.id.value)) {
            throw const FormatException('Invalid durable grant issuance');
          }
          _validateStoredGrant(issued);
          final result = AuthoringGrantResult.fromJson(attempt.terminalJson);
          if (result.grant.digest != issued.grant.digest) {
            throw const FormatException('Grant attempt result is inconsistent');
          }
          nextGrants[issued.grant.id.value] = issued;
        } else if (attempt.family == StoredAuthoringAttemptFamily.grantIssue &&
            !attempt.isError) {
          throw const FormatException('Successful grant attempt has no grant');
        }
        final consumedId = commit.consumedGrantId;
        if (consumedId != null) {
          final stored = nextGrants[consumedId.value];
          final consumableInFlight =
              stored?.state == StoredAuthoringGrantState.inFlight &&
              effectPromotion?.successAttempt?.grantId == consumedId;
          var consumableAfterHeadChange = false;
          if (stored?.state == StoredAuthoringGrantState.revoked &&
              stored?.revocationReason == 'subject-head-changed' &&
              attempt.isError) {
            final error = ExperienceAuthoringError.fromJson(
              attempt.terminalJson,
            );
            final key = _subjectKey(attempt.subject);
            final currentDraftDigest = nextDrafts[key]?.draft.digest;
            final currentReviewKey = nextCurrentReviewKeys[key];
            final currentReviewDigest = currentReviewKey == null
                ? null
                : nextReviewPackets[currentReviewKey]?.digest;
            consumableAfterHeadChange =
                error.code == ExperienceAuthoringErrorCode.stale &&
                error.expectedDigest == stored!.grant.expectedDigest &&
                (currentDraftDigest != null &&
                        error.currentDraftDigest == currentDraftDigest ||
                    currentReviewDigest != null &&
                        error.currentReviewPacketDigest == currentReviewDigest);
          }
          if (attempt.family == StoredAuthoringAttemptFamily.grantIssue ||
              stored == null ||
              stored.state != StoredAuthoringGrantState.active &&
                  !consumableInFlight &&
                  !consumableAfterHeadChange ||
              attempt.grantId != stored.grant.id ||
              attempt.grantDigest != stored.grant.digest ||
              attempt.subject != stored.grant.subject ||
              attempt.effect != stored.grant.effect ||
              attempt.operation != stored.grant.operation ||
              attempt.payloadDigest != stored.grant.payloadDigest) {
            throw const FormatException('Invalid durable grant consumption');
          }
          nextGrants[consumedId.value] = stored.withState(
            StoredAuthoringGrantState.consumed,
            at: attempt.completedAt,
          );
        } else if (attempt.family != StoredAuthoringAttemptFamily.grantIssue) {
          throw const FormatException('Effect attempt did not consume a grant');
        }
        final hasDelta =
            commit.nextDraft != null ||
            commit.removeDraft ||
            commit.clearReviewHead ||
            commit.changeSet != null ||
            commit.reviewPacket != null ||
            commit.abandonReceipt != null ||
            promotionOutcome == StoredPromotionFinalization.committed;
        if (attempt.isError && hasDelta) {
          throw const FormatException(
            'Terminal error contains an effect delta',
          );
        }
        final subjectKey = _subjectKey(attempt.subject);
        final currentDraft = nextDrafts[subjectKey];
        if (commit.nextDraft != null) {
          final replacement = commit.nextDraft!;
          if (replacement.draft.subject != attempt.subject) {
            throw const FormatException(
              'Attempt draft subject is inconsistent',
            );
          }
          if (commit.expectedDraftDigest == null) {
            if (currentDraft != null ||
                replacement.draft.revision != 0 ||
                replacement.draft.previousDraftDigest != null ||
                !nextIds.add(replacement.draft.id.value)) {
              throw const FormatException('Invalid atomic draft open');
            }
          } else {
            if (currentDraft == null ||
                currentDraft.draft.digest != commit.expectedDraftDigest ||
                currentDraft.ownerPrincipalId != replacement.ownerPrincipalId ||
                currentDraft.baseLayoutBlobDigest !=
                    replacement.baseLayoutBlobDigest) {
              throw const FormatException('Invalid atomic draft replacement');
            }
            _validateReplaySuccessor(currentDraft.draft, replacement.draft);
          }
          nextDrafts[subjectKey] = replacement;
        }
        if (commit.removeDraft) {
          final current = nextDrafts[subjectKey];
          if (current == null ||
              commit.expectedDraftDigest == null ||
              current.draft.digest != commit.expectedDraftDigest ||
              commit.nextDraft != null) {
            throw const FormatException('Invalid atomic draft removal');
          }
          nextDrafts.remove(subjectKey);
        }
        if (commit.clearReviewHead) {
          nextCurrentChangeSetIds.remove(subjectKey);
          nextCurrentReviewKeys.remove(subjectKey);
        }
        final changeSet = commit.changeSet;
        if (changeSet != null) {
          final draft = nextDrafts[subjectKey];
          if (changeSet.subject != attempt.subject ||
              draft == null ||
              changeSet.draftDigest != draft.draft.digest ||
              nextChangeSets.containsKey(changeSet.id.value)) {
            throw const FormatException('Invalid atomic ChangeSet retention');
          }
          nextChangeSets[changeSet.id.value] = changeSet;
          nextCurrentChangeSetIds[subjectKey] = changeSet.id.value;
        }
        final packet = commit.reviewPacket;
        if (packet != null) {
          final currentChangeSetId = nextCurrentChangeSetIds[subjectKey];
          if (packet.subject != attempt.subject ||
              currentChangeSetId == null ||
              packet.changeSetId.value != currentChangeSetId) {
            throw const FormatException('Invalid atomic review retention');
          }
          final previous = nextLatestReviews[packet.id.value];
          if (previous == null) {
            if (packet.revision != 0 ||
                packet.previousReviewPacketDigest != null) {
              throw const FormatException('Invalid initial review packet');
            }
          } else if (packet.revision != previous.revision + 1 ||
              packet.previousReviewPacketDigest != previous.digest ||
              packet.changeSetDigest != previous.changeSetDigest) {
            throw const FormatException('Broken review packet revision chain');
          }
          _retainReviewPacket(
            packet,
            changeSets: nextChangeSets,
            reviewPackets: nextReviewPackets,
            latestReviewPackets: nextLatestReviews,
          );
          nextCurrentReviewKeys[subjectKey] = _reviewKey(
            packet.id,
            packet.digest,
          );
        }
        final abandon = commit.abandonReceipt;
        if (abandon != null) {
          if (!commit.removeDraft ||
              abandon.subject != attempt.subject ||
              abandon.requestId != attempt.requestId ||
              abandon.finalDraftDigest != commit.expectedDraftDigest ||
              nextAbandons.any(
                (candidate) =>
                    candidate.id == abandon.id ||
                    candidate.requestId == abandon.requestId,
              )) {
            throw const FormatException('Invalid atomic abandon receipt');
          }
          nextAbandons = <LayoutDraftAbandonReceipt>[...nextAbandons, abandon];
        }
        if (effectPromotion != null) {
          switch (promotionOutcome!) {
            case StoredPromotionFinalization.committed:
              _validatePromotionAgainstDraft(effectPromotion, nextDrafts);
              final promotionSubjectKey = _subjectKey(effectPromotion.subject);
              nextPending.remove(promotionIntentId);
              nextDrafts.remove(promotionSubjectKey);
              nextCurrentChangeSetIds.remove(promotionSubjectKey);
              nextCurrentReviewKeys.remove(promotionSubjectKey);
              nextCompleted[promotionIntentId!] = effectPromotion.receipt;
            case StoredPromotionFinalization.rolledBack:
              nextPending.remove(promotionIntentId);
            case StoredPromotionFinalization.failed:
              // Preserve WAL and CAS after an unsafe third-party divergence.
              // The exact request is nevertheless terminal and its grant is
              // consumed, so reconnect/restart cannot reuse authority.
              break;
          }
        }
        if (hasDelta) {
          for (final entry in nextGrants.entries.toList(growable: false)) {
            final stored = entry.value;
            if (stored.state == StoredAuthoringGrantState.active &&
                stored.grant.subject == attempt.subject) {
              nextGrants[entry.key] = stored.withState(
                StoredAuthoringGrantState.revoked,
                at: attempt.completedAt,
                reason: 'subject-head-changed',
              );
            }
          }
        }
        nextAttempts[attempt.requestId.value] = attempt;
        _validateAtomicFamily(commit);
      case _JournalEventType.revokeGrants:
        _only(event.payload, const <String>{
          'grantIds',
          'reason',
          'revokedAt',
        }, 'revokeGrants');
        final reason = _string(event.payload, 'reason', 'revokeGrants');
        final revokedAt = DateTime.tryParse(
          _string(event.payload, 'revokedAt', 'revokeGrants'),
        );
        if (revokedAt == null || !revokedAt.isUtc) {
          throw const FormatException('Invalid grant revocation timestamp');
        }
        final ids = _list(event.payload, 'grantIds', 'revokeGrants');
        String? previousId;
        for (final rawId in ids) {
          if (rawId is! String ||
              rawId.isEmpty ||
              previousId != null && previousId.compareTo(rawId) >= 0) {
            throw const FormatException('Grant revocation IDs are invalid');
          }
          final stored = nextGrants[rawId];
          if (stored == null ||
              stored.state != StoredAuthoringGrantState.active) {
            throw const FormatException('Grant revocation is not monotonic');
          }
          nextGrants[rawId] = stored.withState(
            StoredAuthoringGrantState.revoked,
            at: revokedAt,
            reason: reason,
          );
          previousId = rawId;
        }
    }
    _validateAuthorityState(
      drafts: nextDrafts,
      pendingPromotions: nextPending,
      completedPromotions: nextCompleted,
      abandonReceipts: nextAbandons,
      grants: nextGrants,
      attempts: nextAttempts,
      changeSets: nextChangeSets,
      reviewPackets: nextReviewPackets,
      currentChangeSetIds: nextCurrentChangeSetIds,
      currentReviewKeys: nextCurrentReviewKeys,
    );
    return _JournalState(
      entries: List<_JournalEvent>.unmodifiable(<_JournalEvent>[
        ...entries,
        event,
      ]),
      drafts: Map<String, StoredLayoutDraft>.unmodifiable(nextDrafts),
      draftIds: Set<String>.unmodifiable(nextIds),
      pendingPromotions:
          Map<String, StoredProjectionLayoutPromotion>.unmodifiable(
            nextPending,
          ),
      completedPromotions: Map<String, ExperiencePromotionReceipt>.unmodifiable(
        nextCompleted,
      ),
      abandonReceipts: List<LayoutDraftAbandonReceipt>.unmodifiable(
        nextAbandons,
      ),
      grants: Map<String, StoredAuthoringGrant>.unmodifiable(nextGrants),
      attempts: Map<String, StoredAuthoringAttempt>.unmodifiable(nextAttempts),
      changeSets: Map<String, ExperienceChangeSet>.unmodifiable(nextChangeSets),
      reviewPackets: Map<String, ExperienceReviewPacket>.unmodifiable(
        nextReviewPackets,
      ),
      latestReviewPackets: Map<String, ExperienceReviewPacket>.unmodifiable(
        nextLatestReviews,
      ),
      currentChangeSetIds: Map<String, String>.unmodifiable(
        nextCurrentChangeSetIds,
      ),
      currentReviewKeys: Map<String, String>.unmodifiable(
        nextCurrentReviewKeys,
      ),
    );
  }
}

Map<String, Object?> _atomicCommitJson(
  ExperienceAuthoringAtomicCommit commit,
) => <String, Object?>{
  'attempt': _storedAttemptJson(commit.attempt),
  if (commit.issuedGrant != null)
    'issuedGrant': _storedGrantJson(commit.issuedGrant!),
  if (commit.consumedGrantId != null)
    'consumedGrantId': commit.consumedGrantId!.value,
  if (commit.expectedDraftDigest != null)
    'expectedDraftDigest': commit.expectedDraftDigest!.value,
  if (commit.nextDraft != null)
    'nextDraft': _storedDraftJson(commit.nextDraft!),
  'removeDraft': commit.removeDraft,
  'clearReviewHead': commit.clearReviewHead,
  if (commit.changeSet != null) 'changeSet': commit.changeSet!.toJson(),
  if (commit.reviewPacket != null)
    'reviewPacket': commit.reviewPacket!.toJson(),
  if (commit.abandonReceipt != null)
    'abandonReceipt': commit.abandonReceipt!.toJson(),
  if (commit.promotionIntentId != null)
    'promotionIntentId': commit.promotionIntentId,
  if (commit.promotionOutcome != null)
    'promotionOutcome': commit.promotionOutcome!.name,
};

ExperienceAuthoringAtomicCommit _atomicCommitFromJson(Object? value) {
  final json = _object(value, 'ExperienceAuthoringAtomicCommit');
  _only(json, const <String>{
    'attempt',
    'issuedGrant',
    'consumedGrantId',
    'expectedDraftDigest',
    'nextDraft',
    'removeDraft',
    'clearReviewHead',
    'changeSet',
    'reviewPacket',
    'abandonReceipt',
    'promotionIntentId',
    'promotionOutcome',
  }, 'ExperienceAuthoringAtomicCommit');
  final promotionOutcomeName = json.containsKey('promotionOutcome')
      ? _string(json, 'promotionOutcome', 'ExperienceAuthoringAtomicCommit')
      : null;
  final promotionOutcome = promotionOutcomeName == null
      ? null
      : StoredPromotionFinalization.values
            .where((candidate) => candidate.name == promotionOutcomeName)
            .firstOrNull;
  if (promotionOutcomeName != null && promotionOutcome == null) {
    throw const FormatException('Unknown promotion finalization outcome');
  }
  return ExperienceAuthoringAtomicCommit(
    attempt: _storedAttemptFromJson(json['attempt']),
    issuedGrant: json.containsKey('issuedGrant')
        ? _storedGrantFromJson(json['issuedGrant'])
        : null,
    consumedGrantId: json.containsKey('consumedGrantId')
        ? AuthoringActionGrantId(
            _string(json, 'consumedGrantId', 'ExperienceAuthoringAtomicCommit'),
          )
        : null,
    expectedDraftDigest: json.containsKey('expectedDraftDigest')
        ? Digest(
            _string(
              json,
              'expectedDraftDigest',
              'ExperienceAuthoringAtomicCommit',
            ),
          )
        : null,
    nextDraft: json.containsKey('nextDraft')
        ? _storedDraftFromJson(json['nextDraft'])
        : null,
    removeDraft: _bool(json, 'removeDraft', 'ExperienceAuthoringAtomicCommit'),
    clearReviewHead: _bool(
      json,
      'clearReviewHead',
      'ExperienceAuthoringAtomicCommit',
    ),
    changeSet: json.containsKey('changeSet')
        ? ExperienceChangeSet.fromJson(json['changeSet'])
        : null,
    reviewPacket: json.containsKey('reviewPacket')
        ? ExperienceReviewPacket.fromJson(json['reviewPacket'])
        : null,
    abandonReceipt: json.containsKey('abandonReceipt')
        ? LayoutDraftAbandonReceipt.fromJson(json['abandonReceipt'])
        : null,
    promotionIntentId: json.containsKey('promotionIntentId')
        ? _string(json, 'promotionIntentId', 'ExperienceAuthoringAtomicCommit')
        : null,
    promotionOutcome: promotionOutcome,
  );
}

Map<String, Object?> _storedGrantJson(StoredAuthoringGrant stored) =>
    <String, Object?>{
      'grant': stored.grant.toJson(),
      'intentKind': stored.intentKind,
      'intent': stored.intentJson,
      'connectionEpoch': stored.connectionEpoch,
      'state': stored.state.name,
      'stateChangedAt': stored.stateChangedAt.toIso8601String(),
      if (stored.revocationReason != null)
        'revocationReason': stored.revocationReason,
    };

StoredAuthoringGrant _storedGrantFromJson(Object? value) {
  final json = _object(value, 'StoredAuthoringGrant');
  _only(json, const <String>{
    'grant',
    'intentKind',
    'intent',
    'connectionEpoch',
    'state',
    'stateChangedAt',
    'revocationReason',
  }, 'StoredAuthoringGrant');
  final stateName = _string(json, 'state', 'StoredAuthoringGrant');
  final state = StoredAuthoringGrantState.values
      .where((candidate) => candidate.name == stateName)
      .firstOrNull;
  final changedAt = DateTime.tryParse(
    _string(json, 'stateChangedAt', 'StoredAuthoringGrant'),
  );
  if (state == null || changedAt == null || !changedAt.isUtc) {
    throw const FormatException('Invalid stored authoring grant state');
  }
  return StoredAuthoringGrant(
    grant: AuthoringActionGrant.fromJson(json['grant']),
    intentKind: _string(json, 'intentKind', 'StoredAuthoringGrant'),
    intentJson: _object(json['intent'], 'StoredAuthoringGrant.intent'),
    connectionEpoch: _string(json, 'connectionEpoch', 'StoredAuthoringGrant'),
    state: state,
    stateChangedAt: changedAt,
    revocationReason: json.containsKey('revocationReason')
        ? _string(json, 'revocationReason', 'StoredAuthoringGrant')
        : null,
  );
}

Map<String, Object?> _storedAttemptJson(
  StoredAuthoringAttempt attempt,
) => <String, Object?>{
  'family': attempt.family.name,
  'requestId': attempt.requestId.value,
  'requestDigest': attempt.requestDigest.value,
  'payloadDigest': attempt.payloadDigest.value,
  'subject': attempt.subject.toJson(),
  'effect': attempt.effect.name,
  'operation': attempt.operation.name,
  if (attempt.grantId != null) 'grantId': attempt.grantId!.value,
  if (attempt.grantDigest != null) 'grantDigest': attempt.grantDigest!.value,
  'isError': attempt.isError,
  'terminal': attempt.terminalJson,
  'completedAt': attempt.completedAt.toIso8601String(),
  'digest': attempt.digest.value,
};

StoredAuthoringAttempt _storedAttemptFromJson(Object? value) {
  final json = _object(value, 'StoredAuthoringAttempt');
  _only(json, const <String>{
    'family',
    'requestId',
    'requestDigest',
    'payloadDigest',
    'subject',
    'effect',
    'operation',
    'grantId',
    'grantDigest',
    'isError',
    'terminal',
    'completedAt',
    'digest',
  }, 'StoredAuthoringAttempt');
  final familyName = _string(json, 'family', 'StoredAuthoringAttempt');
  final family = StoredAuthoringAttemptFamily.values
      .where((candidate) => candidate.name == familyName)
      .firstOrNull;
  final effectName = _string(json, 'effect', 'StoredAuthoringAttempt');
  final effect = AuthoringActionEffect.values
      .where((candidate) => candidate.name == effectName)
      .firstOrNull;
  final operationName = _string(json, 'operation', 'StoredAuthoringAttempt');
  final operation = AuthoringOperation.values
      .where((candidate) => candidate.name == operationName)
      .firstOrNull;
  final completedAt = DateTime.tryParse(
    _string(json, 'completedAt', 'StoredAuthoringAttempt'),
  );
  if (family == null ||
      effect == null ||
      operation == null ||
      completedAt == null ||
      !completedAt.isUtc) {
    throw const FormatException('Invalid stored authoring attempt metadata');
  }
  final attempt = StoredAuthoringAttempt(
    family: family,
    requestId: AuthoringRequestId(
      _string(json, 'requestId', 'StoredAuthoringAttempt'),
    ),
    requestDigest: Digest(
      _string(json, 'requestDigest', 'StoredAuthoringAttempt'),
    ),
    payloadDigest: Digest(
      _string(json, 'payloadDigest', 'StoredAuthoringAttempt'),
    ),
    subject: AuthoringSubjectRef.fromJson(json['subject']),
    effect: effect,
    operation: operation,
    grantId: json.containsKey('grantId')
        ? AuthoringActionGrantId(
            _string(json, 'grantId', 'StoredAuthoringAttempt'),
          )
        : null,
    grantDigest: json.containsKey('grantDigest')
        ? Digest(_string(json, 'grantDigest', 'StoredAuthoringAttempt'))
        : null,
    isError: _bool(json, 'isError', 'StoredAuthoringAttempt'),
    terminalJson: _object(json['terminal'], 'StoredAuthoringAttempt.terminal'),
    completedAt: completedAt,
  );
  if (attempt.digest !=
      Digest(_string(json, 'digest', 'StoredAuthoringAttempt'))) {
    throw const FormatException('Stored authoring attempt digest mismatch');
  }
  return attempt;
}

void _validateStoredGrant(StoredAuthoringGrant stored) {
  final intent = decodeStoredAuthoringGrantIntent(
    stored.intentKind,
    stored.intentJson,
  );
  final grant = stored.grant;
  if (stored.intentJson['kind'] != stored.intentKind ||
      grant.requestId != intent.requestId ||
      grant.requestDigest != intent.digest ||
      grant.payloadDigest != intent.payloadDigest ||
      grant.capabilityDigest != intent.capabilityDigest ||
      grant.subject != intent.subject ||
      grant.effect != intent.effect ||
      grant.operation != intent.operation ||
      grant.expectedDigest != intent.expectedDigest ||
      grant.expectedSourceDigest != intent.expectedSourceDigest ||
      stored.stateChangedAt.isBefore(grant.issuedAt)) {
    throw const FormatException('Stored grant does not match its exact intent');
  }
}

void _validateAttemptTerminal(StoredAuthoringAttempt attempt) {
  if ((attempt.grantId == null) != (attempt.grantDigest == null) ||
      attempt.effect == AuthoringActionEffect.query ||
      attempt.effect != authoringEffectFor(attempt.operation) ||
      (attempt.family == StoredAuthoringAttemptFamily.grantIssue) !=
          (attempt.grantId == null) ||
      utf8.encode(jsonEncode(attempt.terminalJson)).length >
          experienceAuthoringMaxFrameBytes) {
    throw const FormatException('Stored attempt metadata is invalid');
  }
  if (attempt.isError) {
    final error = ExperienceAuthoringError.fromJson(attempt.terminalJson);
    if (error.requestId != attempt.requestId ||
        error.subject != attempt.subject ||
        error.operation != attempt.operation) {
      throw const FormatException('Stored terminal error is inconsistent');
    }
    return;
  }
  final Object result = switch (attempt.family) {
    StoredAuthoringAttemptFamily.grantIssue => AuthoringGrantResult.fromJson(
      attempt.terminalJson,
    ),
    StoredAuthoringAttemptFamily.draftOpen => LayoutDraftOpenResult.fromJson(
      attempt.terminalJson,
    ),
    StoredAuthoringAttemptFamily.draftMutation =>
      LayoutDraftMutationResult.fromJson(attempt.terminalJson),
    StoredAuthoringAttemptFamily.reviewPrepare =>
      ExperienceReviewPrepareResult.fromJson(attempt.terminalJson),
    StoredAuthoringAttemptFamily.reviewAction =>
      ExperienceReviewActionResult.fromJson(attempt.terminalJson),
    StoredAuthoringAttemptFamily.draftAbandon =>
      LayoutDraftAbandonResult.fromJson(attempt.terminalJson),
    StoredAuthoringAttemptFamily.promotionApply =>
      ExperiencePromotionApplyResult.fromJson(attempt.terminalJson),
  };
  final resultRequestId = switch (result) {
    AuthoringGrantResult(:final requestId) => requestId,
    LayoutDraftOpenResult(:final requestId) => requestId,
    LayoutDraftMutationResult(:final requestId) => requestId,
    ExperienceReviewPrepareResult(:final requestId) => requestId,
    ExperienceReviewActionResult(:final requestId) => requestId,
    LayoutDraftAbandonResult(:final requestId) => requestId,
    ExperiencePromotionApplyResult(:final requestId) => requestId,
    _ => throw const FormatException('Unknown stored authoring result'),
  };
  if (resultRequestId != attempt.requestId) {
    throw const FormatException('Stored terminal result request mismatch');
  }
}

void _validateAtomicFamily(ExperienceAuthoringAtomicCommit commit) {
  final hasPromotionFinalization =
      commit.promotionIntentId != null || commit.promotionOutcome != null;
  if (commit.attempt.family != StoredAuthoringAttemptFamily.promotionApply &&
      hasPromotionFinalization) {
    throw const FormatException(
      'Non-promotion attempt contains promotion finalization',
    );
  }
  if (commit.attempt.isError) {
    if (commit.issuedGrant != null ||
        commit.nextDraft != null ||
        commit.removeDraft ||
        commit.clearReviewHead ||
        commit.changeSet != null ||
        commit.reviewPacket != null ||
        commit.abandonReceipt != null ||
        commit.promotionOutcome == StoredPromotionFinalization.committed ||
        (commit.promotionIntentId == null) !=
            (commit.promotionOutcome == null)) {
      throw const FormatException('Error attempt contains a state delta');
    }
    return;
  }
  switch (commit.attempt.family) {
    case StoredAuthoringAttemptFamily.grantIssue:
      final result = AuthoringGrantResult.fromJson(commit.attempt.terminalJson);
      if (commit.issuedGrant == null ||
          result.grant.digest != commit.issuedGrant!.grant.digest ||
          commit.consumedGrantId != null ||
          commit.expectedDraftDigest != null ||
          commit.nextDraft != null ||
          commit.removeDraft ||
          commit.clearReviewHead ||
          commit.changeSet != null ||
          commit.reviewPacket != null ||
          commit.abandonReceipt != null) {
        throw const FormatException('Grant issuance delta is invalid');
      }
    case StoredAuthoringAttemptFamily.draftOpen:
      final result = LayoutDraftOpenResult.fromJson(
        commit.attempt.terminalJson,
      );
      if ((result.resumed && commit.nextDraft != null) ||
          (!result.resumed &&
              (commit.nextDraft == null ||
                  commit.nextDraft!.draft.digest != result.draft.digest)) ||
          commit.removeDraft ||
          commit.clearReviewHead ||
          commit.changeSet != null ||
          commit.reviewPacket != null ||
          commit.abandonReceipt != null) {
        throw const FormatException('Draft open delta is invalid');
      }
    case StoredAuthoringAttemptFamily.draftMutation:
      final result = LayoutDraftMutationResult.fromJson(
        commit.attempt.terminalJson,
      );
      if (commit.nextDraft?.draft.digest != result.draft.digest ||
          commit.expectedDraftDigest == null ||
          !commit.clearReviewHead ||
          commit.removeDraft ||
          commit.changeSet != null ||
          commit.reviewPacket != null ||
          commit.abandonReceipt != null) {
        throw const FormatException('Draft mutation delta is invalid');
      }
    case StoredAuthoringAttemptFamily.reviewPrepare:
      final result = ExperienceReviewPrepareResult.fromJson(
        commit.attempt.terminalJson,
      );
      if (commit.changeSet?.digest != result.changeSet.digest ||
          commit.reviewPacket?.digest != result.reviewPacket.digest ||
          commit.expectedDraftDigest == null ||
          commit.nextDraft != null ||
          commit.removeDraft ||
          commit.clearReviewHead ||
          commit.abandonReceipt != null) {
        throw const FormatException('Review prepare delta is invalid');
      }
    case StoredAuthoringAttemptFamily.reviewAction:
      final result = ExperienceReviewActionResult.fromJson(
        commit.attempt.terminalJson,
      );
      if (commit.reviewPacket?.digest != result.reviewPacket.digest ||
          commit.changeSet != null ||
          commit.expectedDraftDigest != null ||
          commit.nextDraft != null ||
          commit.removeDraft ||
          commit.clearReviewHead ||
          commit.abandonReceipt != null) {
        throw const FormatException('Review action delta is invalid');
      }
    case StoredAuthoringAttemptFamily.draftAbandon:
      final result = LayoutDraftAbandonResult.fromJson(
        commit.attempt.terminalJson,
      );
      if (commit.abandonReceipt?.digest != result.receipt.digest ||
          commit.expectedDraftDigest == null ||
          !commit.removeDraft ||
          !commit.clearReviewHead ||
          commit.nextDraft != null ||
          commit.changeSet != null ||
          commit.reviewPacket != null) {
        throw const FormatException('Draft abandon delta is invalid');
      }
    case StoredAuthoringAttemptFamily.promotionApply:
      final result = ExperiencePromotionApplyResult.fromJson(
        commit.attempt.terminalJson,
      );
      if (commit.promotionIntentId == null ||
          commit.promotionOutcome != StoredPromotionFinalization.committed ||
          commit.consumedGrantId == null ||
          result.receipt.subject != commit.attempt.subject ||
          commit.nextDraft != null ||
          commit.removeDraft ||
          commit.clearReviewHead ||
          commit.expectedDraftDigest != null ||
          commit.issuedGrant != null ||
          commit.changeSet != null ||
          commit.reviewPacket != null ||
          commit.abandonReceipt != null) {
        throw const FormatException('Promotion attempt delta is invalid');
      }
  }
}

void _retainReviewPacket(
  ExperienceReviewPacket packet, {
  required Map<String, ExperienceChangeSet> changeSets,
  required Map<String, ExperienceReviewPacket> reviewPackets,
  required Map<String, ExperienceReviewPacket> latestReviewPackets,
}) {
  final changeSet = changeSets[packet.changeSetId.value];
  if (changeSet == null ||
      packet.subject != changeSet.subject ||
      packet.changeSetDigest != changeSet.digest ||
      packet.comparisonDigest != changeSet.comparison.digest ||
      packet.baseSourceDigest != changeSet.baseSourceDigest) {
    throw const FormatException('Stored review packet has stale fences');
  }
  final key = _reviewKey(packet.id, packet.digest);
  if (reviewPackets.containsKey(key)) {
    throw const FormatException('Duplicate stored review packet');
  }
  final previous = latestReviewPackets[packet.id.value];
  if (previous != null &&
      (packet.revision != previous.revision + 1 ||
          packet.previousReviewPacketDigest != previous.digest)) {
    throw const FormatException('Stored review packet chain is broken');
  }
  reviewPackets[key] = packet;
  latestReviewPackets[packet.id.value] = packet;
}

void _validateAuthorityState({
  required Map<String, StoredLayoutDraft> drafts,
  required Map<String, StoredProjectionLayoutPromotion> pendingPromotions,
  required Map<String, ExperiencePromotionReceipt> completedPromotions,
  required List<LayoutDraftAbandonReceipt> abandonReceipts,
  required Map<String, StoredAuthoringGrant> grants,
  required Map<String, StoredAuthoringAttempt> attempts,
  required Map<String, ExperienceChangeSet> changeSets,
  required Map<String, ExperienceReviewPacket> reviewPackets,
  required Map<String, String> currentChangeSetIds,
  required Map<String, String> currentReviewKeys,
}) {
  for (final entry in currentChangeSetIds.entries) {
    final draft = drafts[entry.key];
    final changeSet = changeSets[entry.value];
    if (draft == null ||
        changeSet == null ||
        _subjectKey(changeSet.subject) != entry.key ||
        changeSet.draftDigest != draft.draft.digest) {
      throw const FormatException('Current ChangeSet head is invalid');
    }
  }
  for (final entry in currentReviewKeys.entries) {
    final packet = reviewPackets[entry.value];
    final changeSetId = currentChangeSetIds[entry.key];
    if (packet == null ||
        changeSetId == null ||
        packet.changeSetId.value != changeSetId ||
        _subjectKey(packet.subject) != entry.key) {
      throw const FormatException('Current review head is invalid');
    }
  }
  for (final attempt in attempts.values) {
    _validateAttemptTerminal(attempt);
    if (!attempt.isError) {
      _validateTerminalResultLinks(
        attempt,
        completedPromotions: completedPromotions,
        abandonReceipts: abandonReceipts,
        changeSets: changeSets,
        reviewPackets: reviewPackets,
      );
    }
    if (attempt.family == StoredAuthoringAttemptFamily.grantIssue) {
      if (!attempt.isError) {
        final result = AuthoringGrantResult.fromJson(attempt.terminalJson);
        final stored = grants[result.grant.id.value];
        if (stored == null ||
            stored.grant.digest != result.grant.digest ||
            !_issuanceAttemptMatchesGrant(attempt, stored)) {
          throw const FormatException(
            'Successful grant issuance has no exact durable grant',
          );
        }
      }
      continue;
    }
    final grantId = attempt.grantId;
    final stored = grantId == null ? null : grants[grantId.value];
    if (stored == null ||
        stored.state != StoredAuthoringGrantState.consumed ||
        !_effectAttemptMatchesGrant(attempt, stored)) {
      throw const FormatException(
        'Effect attempt does not bind one consumed exact grant',
      );
    }
  }
  for (final grant in grants.values) {
    _validateStoredGrant(grant);
    final issuance = attempts[grant.grant.requestId.value];
    if (issuance == null || !_issuanceAttemptMatchesGrant(issuance, grant)) {
      throw const FormatException(
        'Durable grant does not bind its exact issuance attempt',
      );
    }
    if (issuance.completedAt != grant.grant.issuedAt) {
      throw const FormatException('Grant issuance time is inconsistent');
    }
    final effectAttempts = attempts.values
        .where(
          (attempt) =>
              attempt.family != StoredAuthoringAttemptFamily.grantIssue &&
              attempt.grantId == grant.grant.id,
        )
        .toList(growable: false);
    if (grant.state == StoredAuthoringGrantState.consumed) {
      if (effectAttempts.length != 1 ||
          !_effectAttemptMatchesGrant(effectAttempts.single, grant) ||
          grant.stateChangedAt != effectAttempts.single.completedAt) {
        throw const FormatException(
          'Consumed grant does not bind exactly one terminal effect',
        );
      }
    } else if (effectAttempts.isNotEmpty) {
      throw const FormatException(
        'Non-consumed grant unexpectedly binds a terminal effect',
      );
    }
    if (grant.state == StoredAuthoringGrantState.inFlight) {
      final matches = pendingPromotions.values.where(
        (promotion) =>
            promotion.successAttempt?.grantId == grant.grant.id &&
            promotion.successAttempt?.grantDigest == grant.grant.digest,
      );
      if (matches.length != 1) {
        throw const FormatException(
          'In-flight grant does not bind exactly one promotion WAL',
        );
      }
      if (grant.stateChangedAt != matches.single.preparedAt) {
        throw const FormatException('In-flight grant time is inconsistent');
      }
    } else if (grant.state == StoredAuthoringGrantState.active &&
        grant.stateChangedAt != grant.grant.issuedAt) {
      throw const FormatException('Active grant time is inconsistent');
    }
  }
  for (final promotion in pendingPromotions.values.where(
    (candidate) => candidate.successAttempt != null,
  )) {
    final grant = grants[promotion.successAttempt!.grantId!.value];
    final terminal = attempts[promotion.successAttempt!.requestId.value];
    if (grant == null ||
        !_promotionAttemptMatchesGrant(promotion.successAttempt!, grant) ||
        terminal == null && grant.state != StoredAuthoringGrantState.inFlight ||
        terminal != null &&
            (grant.state != StoredAuthoringGrantState.consumed ||
                !_storedAttemptEqual(terminal, promotion.rollbackAttempt!))) {
      throw const FormatException('Promotion effect WAL authority is invalid');
    }
  }
  final pending = pendingPromotions.values.toList(growable: false);
  for (var left = 0; left < pending.length; left += 1) {
    for (var right = left + 1; right < pending.length; right += 1) {
      if (pending[left].subject == pending[right].subject ||
          _promotionPathConflicts(pending[left], pending[right])) {
        throw const FormatException('Promotion WAL paths conflict');
      }
    }
  }
}

void _validateTerminalResultLinks(
  StoredAuthoringAttempt attempt, {
  required Map<String, ExperiencePromotionReceipt> completedPromotions,
  required List<LayoutDraftAbandonReceipt> abandonReceipts,
  required Map<String, ExperienceChangeSet> changeSets,
  required Map<String, ExperienceReviewPacket> reviewPackets,
}) {
  switch (attempt.family) {
    case StoredAuthoringAttemptFamily.grantIssue:
    case StoredAuthoringAttemptFamily.draftOpen:
    case StoredAuthoringAttemptFamily.draftMutation:
      return;
    case StoredAuthoringAttemptFamily.reviewPrepare:
      final result = ExperienceReviewPrepareResult.fromJson(
        attempt.terminalJson,
      );
      if (changeSets[result.changeSet.id.value]?.digest !=
              result.changeSet.digest ||
          reviewPackets[_reviewKey(
                    result.reviewPacket.id,
                    result.reviewPacket.digest,
                  )]
                  ?.digest !=
              result.reviewPacket.digest) {
        throw const FormatException(
          'Review preparation attempt lost its immutable result objects',
        );
      }
      return;
    case StoredAuthoringAttemptFamily.reviewAction:
      final result = ExperienceReviewActionResult.fromJson(
        attempt.terminalJson,
      );
      if (reviewPackets[_reviewKey(
                result.reviewPacket.id,
                result.reviewPacket.digest,
              )]
              ?.digest !=
          result.reviewPacket.digest) {
        throw const FormatException(
          'Review action attempt lost its immutable result packet',
        );
      }
      return;
    case StoredAuthoringAttemptFamily.draftAbandon:
      final result = LayoutDraftAbandonResult.fromJson(attempt.terminalJson);
      if (!abandonReceipts.any(
        (receipt) => receipt.digest == result.receipt.digest,
      )) {
        throw const FormatException(
          'Draft abandon attempt lost its durable receipt',
        );
      }
      return;
    case StoredAuthoringAttemptFamily.promotionApply:
      final result = ExperiencePromotionApplyResult.fromJson(
        attempt.terminalJson,
      );
      if (!completedPromotions.values.any(
        (receipt) => receipt.digest == result.receipt.digest,
      )) {
        throw const FormatException(
          'Promotion attempt lost its durable receipt',
        );
      }
      return;
  }
}

bool _issuanceAttemptMatchesGrant(
  StoredAuthoringAttempt attempt,
  StoredAuthoringGrant stored,
) {
  if (attempt.family != StoredAuthoringAttemptFamily.grantIssue ||
      attempt.isError ||
      attempt.grantId != null ||
      attempt.grantDigest != null ||
      attempt.requestId != stored.grant.requestId ||
      attempt.requestDigest != stored.grant.requestDigest ||
      attempt.payloadDigest != stored.grant.payloadDigest ||
      attempt.subject != stored.grant.subject ||
      attempt.effect != stored.grant.effect ||
      attempt.operation != stored.grant.operation) {
    return false;
  }
  final result = AuthoringGrantResult.fromJson(attempt.terminalJson);
  return result.grant.digest == stored.grant.digest;
}

bool _effectAttemptMatchesGrant(
  StoredAuthoringAttempt attempt,
  StoredAuthoringGrant stored,
) =>
    attempt.family != StoredAuthoringAttemptFamily.grantIssue &&
    attempt.grantId == stored.grant.id &&
    attempt.grantDigest == stored.grant.digest &&
    attempt.subject == stored.grant.subject &&
    attempt.effect == stored.grant.effect &&
    attempt.operation == stored.grant.operation &&
    attempt.payloadDigest == stored.grant.payloadDigest;

bool _storedAttemptEqual(
  StoredAuthoringAttempt left,
  StoredAuthoringAttempt right,
) => left.digest == right.digest;

String _reviewKey(ExperienceReviewPacketId id, Digest digest) =>
    '${id.value}@${digest.value}';

Map<String, Object?> _storedDraftJson(StoredLayoutDraft stored) =>
    <String, Object?>{
      'ownerPrincipalId': stored.ownerPrincipalId.value,
      'draft': stored.draft.toJson(),
      'baseLayoutBlobDigest': stored.baseLayoutBlobDigest.value,
    };

StoredLayoutDraft _storedDraftFromJson(Object? value) {
  final json = _object(value, 'StoredLayoutDraft');
  _only(json, const <String>{
    'ownerPrincipalId',
    'draft',
    'baseLayoutBlobDigest',
  }, 'StoredLayoutDraft');
  return StoredLayoutDraft(
    ownerPrincipalId: AuthoringPrincipalId(
      _string(json, 'ownerPrincipalId', 'StoredLayoutDraft'),
    ),
    draft: LayoutDraft.fromJson(json['draft']),
    baseLayoutBlobDigest: Digest(
      _string(json, 'baseLayoutBlobDigest', 'StoredLayoutDraft'),
    ),
  );
}

Map<String, Object?> _storedPromotionJson(
  StoredProjectionLayoutPromotion promotion,
) => <String, Object?>{
  'intentId': promotion.intentId,
  'subject': promotion.subject.toJson(),
  'relativeSourcePath': promotion.relativeSourcePath,
  'replaceProtocol': promotion.replaceProtocol,
  'replaceProviderKind': promotion.replaceProviderKind,
  'recoverySlot': promotion.recoverySlot,
  'configurationAuthorityDigest': promotion.configurationAuthorityDigest.value,
  'sourceMetadataDigest': promotion.sourceMetadataDigest.value,
  'originalSourceBlobDigest': promotion.originalSourceBlobDigest.value,
  'candidateSourceBlobDigest': promotion.candidateSourceBlobDigest.value,
  'originalCompiledCorpusDigest': promotion.originalCompiledCorpusDigest.value,
  'candidateCompiledCorpusDigest':
      promotion.candidateCompiledCorpusDigest.value,
  'receipt': promotion.receipt.toJson(),
  'grantDigest': promotion.grantDigest.value,
  if (promotion.successAttempt != null)
    'successAttempt': _storedAttemptJson(promotion.successAttempt!),
  if (promotion.rollbackAttempt != null)
    'rollbackAttempt': _storedAttemptJson(promotion.rollbackAttempt!),
  'preparedAt': promotion.preparedAt.toIso8601String(),
};

StoredProjectionLayoutPromotion _storedPromotionFromJson(Object? value) {
  final json = _object(value, 'StoredProjectionLayoutPromotion');
  _only(json, const <String>{
    'intentId',
    'subject',
    'relativeSourcePath',
    'replaceProtocol',
    'replaceProviderKind',
    'recoverySlot',
    'configurationAuthorityDigest',
    'sourceMetadataDigest',
    'originalSourceBlobDigest',
    'candidateSourceBlobDigest',
    'originalCompiledCorpusDigest',
    'candidateCompiledCorpusDigest',
    'receipt',
    'grantDigest',
    'successAttempt',
    'rollbackAttempt',
    'preparedAt',
  }, 'StoredProjectionLayoutPromotion');
  final preparedAt = DateTime.tryParse(
    _string(json, 'preparedAt', 'StoredProjectionLayoutPromotion'),
  );
  if (preparedAt == null || !preparedAt.isUtc) {
    throw const FormatException('Invalid stored promotion timestamp');
  }
  late final StoredProjectionLayoutPromotion promotion;
  try {
    promotion = StoredProjectionLayoutPromotion(
      intentId: _string(json, 'intentId', 'StoredProjectionLayoutPromotion'),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      relativeSourcePath: _string(
        json,
        'relativeSourcePath',
        'StoredProjectionLayoutPromotion',
      ),
      replaceProtocol: _string(
        json,
        'replaceProtocol',
        'StoredProjectionLayoutPromotion',
      ),
      replaceProviderKind: _string(
        json,
        'replaceProviderKind',
        'StoredProjectionLayoutPromotion',
      ),
      recoverySlot: _string(
        json,
        'recoverySlot',
        'StoredProjectionLayoutPromotion',
      ),
      configurationAuthorityDigest: Digest(
        _string(
          json,
          'configurationAuthorityDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      sourceMetadataDigest: Digest(
        _string(
          json,
          'sourceMetadataDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      originalSourceBlobDigest: Digest(
        _string(
          json,
          'originalSourceBlobDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      candidateSourceBlobDigest: Digest(
        _string(
          json,
          'candidateSourceBlobDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      originalCompiledCorpusDigest: Digest(
        _string(
          json,
          'originalCompiledCorpusDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      candidateCompiledCorpusDigest: Digest(
        _string(
          json,
          'candidateCompiledCorpusDigest',
          'StoredProjectionLayoutPromotion',
        ),
      ),
      receipt: ExperiencePromotionReceipt.fromJson(json['receipt']),
      grantDigest: Digest(
        _string(json, 'grantDigest', 'StoredProjectionLayoutPromotion'),
      ),
      successAttempt: json.containsKey('successAttempt')
          ? _storedAttemptFromJson(json['successAttempt'])
          : null,
      rollbackAttempt: json.containsKey('rollbackAttempt')
          ? _storedAttemptFromJson(json['rollbackAttempt'])
          : null,
      preparedAt: preparedAt,
    );
  } on ArgumentError {
    throw const FormatException('Invalid stored promotion authority');
  }
  final normalized = p.normalize(promotion.relativeSourcePath);
  if (p.isAbsolute(promotion.relativeSourcePath) ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized != promotion.relativeSourcePath) {
    throw const FormatException('Stored promotion path is not confined');
  }
  return promotion;
}

bool _storedPromotionEqual(
  StoredProjectionLayoutPromotion left,
  StoredProjectionLayoutPromotion right,
) =>
    const JcsCanonicalizer().canonicalize(_storedPromotionJson(left)) ==
    const JcsCanonicalizer().canonicalize(_storedPromotionJson(right));

bool _promotionPathConflicts(
  StoredProjectionLayoutPromotion left,
  StoredProjectionLayoutPromotion right,
) =>
    left.relativeSourcePath == right.relativeSourcePath ||
    left.recoverySlot == right.recoverySlot ||
    left.relativeSourcePath == right.recoverySlot ||
    left.recoverySlot == right.relativeSourcePath;

void _validatePromotionAgainstDraft(
  StoredProjectionLayoutPromotion promotion,
  Map<String, StoredLayoutDraft> drafts,
) {
  final current = drafts[_subjectKey(promotion.subject)];
  final receipt = promotion.receipt;
  if (current == null ||
      receipt.subject != promotion.subject ||
      receipt.draftId != current.draft.id ||
      receipt.draftDigest != current.draft.digest ||
      receipt.draftRevision != current.draft.revision ||
      receipt.sourceDigest != current.draft.baseSourceDigest ||
      receipt.resultSourceDigest != promotion.candidateSourceDigest ||
      receipt.previousContentSetDigest != current.draft.contentSetDigest ||
      receipt.layoutDigest != current.draft.candidateLayoutDigest ||
      promotion.originalSourceBlobDigest != receipt.sourceDigest ||
      promotion.candidateSourceBlobDigest != receipt.resultSourceDigest) {
    throw const FormatException('Promotion WAL does not bind the draft head');
  }
  final success = promotion.successAttempt;
  final rollback = promotion.rollbackAttempt;
  if (success != null && rollback != null) {
    _validateAttemptTerminal(success);
    _validateAttemptTerminal(rollback);
    final result = ExperiencePromotionApplyResult.fromJson(
      success.terminalJson,
    );
    final error = ExperienceAuthoringError.fromJson(rollback.terminalJson);
    if (result.receipt.digest != receipt.digest ||
        result.head.latestPromotion?.digest != receipt.digest ||
        error.code != ExperienceAuthoringErrorCode.unavailable ||
        error.requestId != success.requestId ||
        error.subject != promotion.subject ||
        error.operation != AuthoringOperation.promote) {
      throw const FormatException('Promotion effect WAL is inconsistent');
    }
  }
}

bool _promotionAttemptMatchesGrant(
  StoredAuthoringAttempt attempt,
  StoredAuthoringGrant stored,
) =>
    attempt.family == StoredAuthoringAttemptFamily.promotionApply &&
    attempt.grantId == stored.grant.id &&
    attempt.grantDigest == stored.grant.digest &&
    attempt.subject == stored.grant.subject &&
    attempt.effect == stored.grant.effect &&
    attempt.operation == stored.grant.operation &&
    attempt.payloadDigest == stored.grant.payloadDigest;

int _pendingEffectCount(_JournalState state) => state.pendingPromotions.values
    .where(
      (promotion) =>
          promotion.successAttempt != null &&
          !state.attempts.containsKey(
            promotion.successAttempt!.requestId.value,
          ),
    )
    .length;

void _validateReceiptChain(
  ExperiencePromotionReceipt receipt,
  Iterable<ExperiencePromotionReceipt> completed,
) {
  final history =
      completed
          .where((candidate) => candidate.subject == receipt.subject)
          .toList(growable: false)
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
  final previous = history.lastOrNull;
  if (receipt.sequence != (previous?.sequence ?? 0) + 1 ||
      receipt.previousReceiptDigest != previous?.digest) {
    throw const FormatException('Broken promotion receipt chain');
  }
}

void _validateCompleteReceiptChains(
  Iterable<ExperiencePromotionReceipt> completed,
) {
  final bySubject = <String, List<ExperiencePromotionReceipt>>{};
  for (final receipt in completed) {
    bySubject
        .putIfAbsent(
          _subjectKey(receipt.subject),
          () => <ExperiencePromotionReceipt>[],
        )
        .add(receipt);
  }
  for (final history in bySubject.values) {
    history.sort((left, right) => left.sequence.compareTo(right.sequence));
    Digest? previous;
    for (var index = 0; index < history.length; index += 1) {
      final receipt = history[index];
      if (receipt.sequence != index + 1 ||
          receipt.previousReceiptDigest != previous) {
        throw const FormatException('Broken promotion receipt history');
      }
      previous = receipt.digest;
    }
  }
}

void _validateReplaySuccessor(LayoutDraft previous, LayoutDraft next) {
  if (next.id != previous.id ||
      next.subject != previous.subject ||
      next.baseLayoutDigest != previous.baseLayoutDigest ||
      next.baseSourceDigest != previous.baseSourceDigest ||
      next.topologyDigest != previous.topologyDigest ||
      next.contentSetDigest != previous.contentSetDigest ||
      next.revision != previous.revision + 1 ||
      next.previousDraftDigest != previous.digest) {
    throw const FormatException('Broken LayoutDraft revision chain');
  }
}

String _subjectKey(AuthoringSubjectRef subject) =>
    const JcsCanonicalizer().canonicalize(subject.toJson());

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

bool _bool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be a list');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// glibc Linux x64 bindings for durable Host state replacement.
///
/// Every path component is resolved relative to a no-follow directory FD. A
/// successful receipt means: each newly-created directory entry was flushed,
/// the staging inode was flushed, the destination was installed with
/// `RENAME_NOREPLACE` or updated with `RENAME_EXCHANGE`, and the destination
/// parent was flushed. Updates retain one bounded private previous-value slot.
/// CAS receipts therefore precede the WAL receipt that may refer to them, and
/// a promotion never reaches its source exchange without a durable prepare
/// WAL. Cooperating writers share the kernel guard and require a stable workspace
/// root. The root is rebound before install and before receipt; this protocol
/// does not claim exclusion against a same-uid process that bypasses the guard
/// and mutates an already-open private inode.
final class _LinuxX64AuthoringStateBindings {
  _LinuxX64AuthoringStateBindings(this.library)
    : open = library.lookupFunction<_AuthoringOpenNative, _AuthoringOpenDart>(
        'open',
      ),
      openAt = library
          .lookupFunction<_AuthoringOpenAtNative, _AuthoringOpenAtDart>(
            'openat',
          ),
      close = library
          .lookupFunction<_AuthoringCloseNative, _AuthoringCloseDart>('close'),
      fstat = library
          .lookupFunction<_AuthoringFstatNative, _AuthoringFstatDart>('fstat'),
      fstatAt = library
          .lookupFunction<_AuthoringFstatAtNative, _AuthoringFstatAtDart>(
            'fstatat',
          ),
      pwrite = library
          .lookupFunction<_AuthoringPwriteNative, _AuthoringPwriteDart>(
            'pwrite',
          ),
      pread = library
          .lookupFunction<_AuthoringPreadNative, _AuthoringPreadDart>('pread'),
      fsync = library
          .lookupFunction<_AuthoringFsyncNative, _AuthoringFsyncDart>('fsync'),
      ftruncate = library
          .lookupFunction<_AuthoringFtruncateNative, _AuthoringFtruncateDart>(
            'ftruncate',
          ),
      fchmod = library
          .lookupFunction<_AuthoringFchmodNative, _AuthoringFchmodDart>(
            'fchmod',
          ),
      mkdirAt = library
          .lookupFunction<_AuthoringMkdirAtNative, _AuthoringMkdirAtDart>(
            'mkdirat',
          ),
      renameAt2 = library
          .lookupFunction<_AuthoringRenameAt2Native, _AuthoringRenameAt2Dart>(
            'renameat2',
          ),
      unlinkAt = library
          .lookupFunction<_AuthoringUnlinkAtNative, _AuthoringUnlinkAtDart>(
            'unlinkat',
          ),
      flock = library
          .lookupFunction<_AuthoringFlockNative, _AuthoringFlockDart>('flock'),
      effectiveUserId = library
          .lookupFunction<_AuthoringGeteuidNative, _AuthoringGeteuidDart>(
            'geteuid',
          ),
      errnoLocation = library
          .lookupFunction<
            _AuthoringErrnoLocationNative,
            _AuthoringErrnoLocationDart
          >('__errno_location');

  static _LinuxX64AuthoringStateBindings? tryLoad() {
    if (ffi.Abi.current() != ffi.Abi.linuxX64 ||
        ffi.sizeOf<_AuthoringLinuxStat>() != 144) {
      return null;
    }
    try {
      return _LinuxX64AuthoringStateBindings(ffi.DynamicLibrary.process());
    } on Object {
      return null;
    }
  }

  final ffi.DynamicLibrary library;
  final _AuthoringOpenDart open;
  final _AuthoringOpenAtDart openAt;
  final _AuthoringCloseDart close;
  final _AuthoringFstatDart fstat;
  final _AuthoringFstatAtDart fstatAt;
  final _AuthoringPwriteDart pwrite;
  final _AuthoringPreadDart pread;
  final _AuthoringFsyncDart fsync;
  final _AuthoringFtruncateDart ftruncate;
  final _AuthoringFchmodDart fchmod;
  final _AuthoringMkdirAtDart mkdirAt;
  final _AuthoringRenameAt2Dart renameAt2;
  final _AuthoringUnlinkAtDart unlinkAt;
  final _AuthoringFlockDart flock;
  final _AuthoringGeteuidDart effectiveUserId;
  final _AuthoringErrnoLocationDart errnoLocation;

  static const int _oReadOnly = 0;
  static const int _oReadWrite = 0x2;
  static const int _oCreate = 0x40;
  static const int _oExclusive = 0x80;
  static const int _oNonBlock = 0x800;
  static const int _oDirectory = 0x10000;
  static const int _oNoFollow = 0x20000;
  static const int _oCloseOnExec = 0x80000;
  static const int _atSymlinkNoFollow = 0x100;
  static const int _renameNoReplace = 0x1;
  static const int _renameExchange = 0x2;
  static const int _regularFileMode = 0x8000;
  static const int _directoryMode = 0x4000;
  static const int _fileTypeMask = 0xf000;
  static const int _privateDirectoryPermissions = 0x1c0; // 0700
  static const int _privateFilePermissions = 0x180; // 0600
  static const int _lockExclusive = 2;
  static const int _lockNonBlocking = 4;
  static const int _lockUnlock = 8;
  static const Set<int> _unsupportedErrnos = <int>{22, 38, 95};

  int get _errno => errnoLocation().value;

  _LockClaim acquireGuard({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required Duration timeout,
    required ExperienceAuthoringGuardBoundaryHook? boundaryHook,
  }) {
    final request = _resolveRequest(workspaceStore, relativePath);
    final descriptors = <int>[];
    try {
      var parentFd = _openDirectoryTree(request.workspaceRoot, descriptors);
      final workspaceRootStat = _readStat(parentFd);
      for (final segment in request.segments.take(
        request.segments.length - 1,
      )) {
        var next = _openDirectoryAtOptional(parentFd, segment);
        if (next == null) {
          _mkdirAtChecked(parentFd, segment);
          next = _openDirectoryAt(parentFd, segment);
        }
        descriptors.add(next);
        _fsyncChecked(
          parentFd,
          target: ExperienceAuthoringStateFsyncTarget.stateDirectoryParent,
          beforeFsync: null,
        );
        parentFd = next;
      }
      _requirePrivateDirectory(parentFd);
      final guardName = request.segments.last;
      final guardFd = _openAtCreate(
        parentFd,
        guardName,
        _oReadWrite | _oCreate | _oNonBlock | _oNoFollow | _oCloseOnExec,
        _privateFilePermissions,
      );
      descriptors.add(guardFd);
      final guardStat = _requirePrivateGuard(guardFd);
      if (guardStat.size != 0 ||
          _readEntryStatAt(parentFd, guardName) != guardStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      _fsyncChecked(
        guardFd,
        target: ExperienceAuthoringStateFsyncTarget.stagingFile,
        beforeFsync: null,
      );
      _fsyncChecked(
        parentFd,
        target: ExperienceAuthoringStateFsyncTarget.destinationParent,
        beforeFsync: null,
      );
      boundaryHook?.call(
        ExperienceAuthoringGuardBoundary.afterCreateBeforeWrite,
      );
      final waiting = Stopwatch()..start();
      while (flock(guardFd, _lockExclusive | _lockNonBlocking) != 0) {
        final errno = _errno;
        if (errno != 11 && errno != 4) _throwErrno(null, errno);
        if (waiting.elapsed >= timeout) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          );
        }
        if (_readEntryStatAt(parentFd, guardName) != guardStat) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        sleep(const Duration(milliseconds: 1));
      }
      if (_requirePrivateGuard(guardFd) != guardStat ||
          _readEntryStatAt(parentFd, guardName) != guardStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      boundaryHook?.call(ExperienceAuthoringGuardBoundary.afterAcquire);
      if (_requirePrivateGuard(guardFd) != guardStat ||
          _readEntryStatAt(parentFd, guardName) != guardStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      _requireDirectoryTreeRebound(request.workspaceRoot, workspaceRootStat);
      return _LockClaim(
        () => _releaseGuard(
          descriptors: descriptors,
          parentFd: parentFd,
          guardFd: guardFd,
          guardName: guardName,
          guardStat: guardStat,
          workspaceRoot: request.workspaceRoot,
          workspaceRootStat: workspaceRootStat,
          boundaryHook: boundaryHook,
        ),
      );
    } on Object catch (error, stackTrace) {
      final failure = _sanitize(error);
      for (final descriptor in descriptors.reversed) {
        close(descriptor);
      }
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  void _releaseGuard({
    required List<int> descriptors,
    required int parentFd,
    required int guardFd,
    required String guardName,
    required _AuthoringLinuxFileStat guardStat,
    required String workspaceRoot,
    required _AuthoringLinuxFileStat workspaceRootStat,
    required ExperienceAuthoringGuardBoundaryHook? boundaryHook,
  }) {
    Object? failure;
    StackTrace? failureStack;
    try {
      boundaryHook?.call(ExperienceAuthoringGuardBoundary.beforeRelease);
      _requireDirectoryTreeRebound(workspaceRoot, workspaceRootStat);
      if (_requirePrivateGuard(guardFd) != guardStat ||
          _readEntryStatAt(parentFd, guardName) != guardStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      if (flock(guardFd, _lockUnlock) != 0) _throwErrno(null, _errno);
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    for (final descriptor in descriptors.reversed) {
      if (close(descriptor) != 0 && failure == null) {
        failure = ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          diagnosticErrno: _errno,
        );
        failureStack = StackTrace.current;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    required List<int>? expectedCurrentBytes,
    required ExperienceAuthoringStateFsyncHook? beforeFsync,
  }) {
    final request = _resolveRequest(workspaceStore, relativePath);
    final workspaceRoot = request.workspaceRoot;
    final segments = request.segments;

    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    ExperienceAuthoringDurableWriteReceipt? receipt;
    int? destinationParentFd;
    int? stagingFd;
    int? destinationFd;
    String? stagingName;
    String? destinationName;
    var installedNew = false;
    var exchanged = false;
    var postExchangeCallbackBoundary = false;
    try {
      var parentFd = _openDirectoryTree(workspaceRoot, descriptors);
      final workspaceRootStat = _readStat(parentFd);
      for (final segment in segments.take(segments.length - 1)) {
        var next = _openDirectoryAtOptional(parentFd, segment);
        if (next == null) {
          _mkdirAtChecked(parentFd, segment);
          next = _openDirectoryAt(parentFd, segment);
        }
        descriptors.add(next);
        // Flush every traversed dirent, not only directories created here.
        // FileSystemWorkspaceStore may have just created the state root for
        // its process lock, and that creation must be part of this proof.
        _fsyncChecked(
          parentFd,
          target: ExperienceAuthoringStateFsyncTarget.stateDirectoryParent,
          beforeFsync: beforeFsync,
        );
        parentFd = next;
      }
      destinationParentFd = parentFd;
      destinationName = segments.last;
      if (expectedCurrentBytes == null) {
        final existingFd = _openAtOptionalFile(
          parentFd,
          destinationName,
          _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
        );
        if (existingFd != null) {
          descriptors.add(existingFd);
          _regularSingleLinkStat(existingFd);
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        final token =
            '$pid-${DateTime.now().microsecondsSinceEpoch}-'
            '${identityHashCode(Object())}';
        stagingName = '.$destinationName.authoring-stage-$token';
        stagingFd = _openAtCreateExclusive(
          parentFd,
          stagingName,
          _oReadWrite |
              _oCreate |
              _oExclusive |
              _oNonBlock |
              _oNoFollow |
              _oCloseOnExec,
          _privateFilePermissions,
        );
        descriptors.add(stagingFd);
        _writeAll(stagingFd, bytes);
        final stagingStat = _regularSingleLinkStat(stagingFd);
        if (stagingStat.size != bytes.length) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          );
        }
        _fsyncChecked(
          stagingFd,
          target: ExperienceAuthoringStateFsyncTarget.stagingFile,
          beforeFsync: beforeFsync,
        );
        _readAndRequireExactStable(stagingFd, bytes, stagingStat);
        if (_readEntryStatAt(parentFd, stagingName) != stagingStat) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        _requireDirectoryTreeRebound(workspaceRoot, workspaceRootStat);
        _renameAt2Checked(
          parentFd,
          stagingName,
          parentFd,
          destinationName,
          _renameNoReplace,
        );
        installedNew = true;
        if (beforeFsync != null) postExchangeCallbackBoundary = true;
        _fsyncChecked(
          parentFd,
          target: ExperienceAuthoringStateFsyncTarget.destinationParent,
          beforeFsync: beforeFsync,
        );
        final committedFd = _openRegularAt(parentFd, destinationName);
        descriptors.add(committedFd);
        final committedStat = _regularSingleLinkStat(committedFd);
        if (!_sameStableEntity(committedStat, stagingStat)) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        _readAndRequireExactStable(committedFd, bytes, committedStat);
      } else {
        _requirePrivateDirectory(parentFd);
        destinationFd = _openRegularAt(parentFd, destinationName);
        descriptors.add(destinationFd);
        final destinationStat = _regularSingleLinkStat(destinationFd);
        _readAndRequireExactStable(
          destinationFd,
          expectedCurrentBytes,
          destinationStat,
        );
        stagingName = '.$destinationName.authoring-previous';
        stagingFd = _openAtOptionalFile(
          parentFd,
          stagingName,
          _oReadWrite | _oNonBlock | _oNoFollow | _oCloseOnExec,
        );
        stagingFd ??= _openAtCreateExclusive(
          parentFd,
          stagingName,
          _oReadWrite |
              _oCreate |
              _oExclusive |
              _oNonBlock |
              _oNoFollow |
              _oCloseOnExec,
          _privateFilePermissions,
        );
        descriptors.add(stagingFd);
        final slotBefore = _requirePrivateStateSlot(stagingFd);
        if (slotBefore.device == destinationStat.device &&
            slotBefore.inode == destinationStat.inode) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
          );
        }
        if (ftruncate(stagingFd, 0) != 0) _throwErrno(stagingName, _errno);
        _writeAll(stagingFd, bytes);
        if (ftruncate(stagingFd, bytes.length) != 0) {
          _throwErrno(stagingName, _errno);
        }
        if (fchmod(stagingFd, _privateFilePermissions) != 0) {
          _throwErrno(stagingName, _errno);
        }
        final stagedStat = _requirePrivateStateSlot(stagingFd);
        _fsyncChecked(
          stagingFd,
          target: ExperienceAuthoringStateFsyncTarget.stagingFile,
          beforeFsync: beforeFsync,
        );
        _readAndRequireExactStable(stagingFd, bytes, stagedStat);
        final reboundDestination = _readEntryStatAt(parentFd, destinationName);
        final reboundSlot = _readEntryStatAt(parentFd, stagingName);
        if (reboundDestination != destinationStat ||
            reboundSlot != stagedStat) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        _readAndRequireExactStable(
          destinationFd,
          expectedCurrentBytes,
          destinationStat,
        );
        _requireDirectoryTreeRebound(workspaceRoot, workspaceRootStat);
        _renameAt2Checked(
          parentFd,
          destinationName,
          parentFd,
          stagingName,
          _renameExchange,
        );
        exchanged = true;
        // A journal produced by an older writer may have been 0644. Once its
        // inode is displaced into the private previous-value slot, normalize
        // it before proving the slot durable. The parent is already 0700 and
        // the inode remains open, single-linked, and owned by this process.
        if (fchmod(destinationFd, _privateFilePermissions) != 0) {
          _throwErrno(stagingName, _errno);
        }
        _fsyncChecked(
          destinationFd,
          target: ExperienceAuthoringStateFsyncTarget.stagingFile,
          beforeFsync: null,
        );
        if (beforeFsync != null) postExchangeCallbackBoundary = true;
        _fsyncChecked(
          parentFd,
          target: ExperienceAuthoringStateFsyncTarget.destinationParent,
          beforeFsync: beforeFsync,
        );
        final installedStat = _regularSingleLinkStat(stagingFd);
        final displacedStat = _regularSingleLinkStat(destinationFd);
        _readAndRequireExactStable(stagingFd, bytes, installedStat);
        _readAndRequireExactStable(
          destinationFd,
          expectedCurrentBytes,
          displacedStat,
        );
        if (_readEntryStatAt(parentFd, destinationName) != installedStat ||
            _readEntryStatAt(parentFd, stagingName) != displacedStat) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
      }
      try {
        _requireDirectoryTreeRebound(workspaceRoot, workspaceRootStat);
      } on Object {
        if (exchanged) postExchangeCallbackBoundary = true;
        rethrow;
      }
      receipt = ExperienceAuthoringDurableWriteReceipt._(
        protocol: experienceAuthoringDurableWriteProtocol,
        workspaceAuthorityDigest: _authoringStateAuthorityDigest(
          workspaceStore,
        ),
        relativePath: relativePath,
        digest: Digest.bytes(bytes),
        byteLength: bytes.length,
      );
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
      if (exchanged &&
          !postExchangeCallbackBoundary &&
          destinationParentFd != null &&
          destinationFd != null &&
          stagingFd != null &&
          stagingName != null &&
          destinationName != null &&
          expectedCurrentBytes != null) {
        try {
          final installedStat = _regularSingleLinkStat(stagingFd);
          final displacedStat = _regularSingleLinkStat(destinationFd);
          _readAndRequireExactStable(stagingFd, bytes, installedStat);
          _readAndRequireExactStable(
            destinationFd,
            expectedCurrentBytes,
            displacedStat,
          );
          if (_readEntryStatAt(destinationParentFd, destinationName) !=
                  installedStat ||
              _readEntryStatAt(destinationParentFd, stagingName) !=
                  displacedStat) {
            throw const ExperienceAuthoringStateDurabilityFailure._(
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            );
          }
          _renameAt2Checked(
            destinationParentFd,
            destinationName,
            destinationParentFd,
            stagingName,
            _renameExchange,
          );
          _fsyncChecked(
            destinationParentFd,
            target: ExperienceAuthoringStateFsyncTarget.destinationParent,
            beforeFsync: null,
          );
          if (_readEntryStatAt(destinationParentFd, destinationName) !=
                  displacedStat ||
              _readEntryStatAt(destinationParentFd, stagingName) !=
                  installedStat) {
            throw const ExperienceAuthoringStateDurabilityFailure._(
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            );
          }
        } on Object catch (rollbackError, rollbackStack) {
          failure = _sanitize(rollbackError);
          failureStack = rollbackStack;
        }
      } else if (!installedNew &&
          !exchanged &&
          destinationParentFd != null &&
          stagingFd != null &&
          stagingName != null &&
          expectedCurrentBytes == null) {
        try {
          _discardCreatedStagingExact(
            destinationParentFd,
            stagingName,
            stagingFd,
          );
        } on Object catch (cleanupError, cleanupStack) {
          failure = _sanitize(cleanupError);
          failureStack = cleanupStack;
        }
      }
    }
    for (final descriptor in descriptors.reversed) {
      if (close(descriptor) != 0 && failure == null) {
        failure = ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          diagnosticErrno: _errno,
        );
        failureStack = StackTrace.current;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    return receipt!;
  }

  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    required ExperienceAuthoringStateFsyncHook? beforeFsync,
  }) {
    final request = _resolveRequest(workspaceStore, relativePath);
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    ExperienceAuthoringDurableWriteReceipt? receipt;
    try {
      var parentFd = _openDirectoryTree(request.workspaceRoot, descriptors);
      final workspaceRootStat = _readStat(parentFd);
      for (final segment in request.segments.take(
        request.segments.length - 1,
      )) {
        final next = _openDirectoryAt(parentFd, segment);
        descriptors.add(next);
        // Re-flush every visible ancestor dirent. This converts state created
        // by an older/non-probatory writer into a current durable antecedent.
        _fsyncChecked(
          parentFd,
          target: ExperienceAuthoringStateFsyncTarget.stateDirectoryParent,
          beforeFsync: beforeFsync,
        );
        parentFd = next;
      }
      final existingFd = _openRegularAt(parentFd, request.segments.last);
      descriptors.add(existingFd);
      final initialStat = _regularSingleLinkStat(existingFd);
      if (initialStat.size != bytes.length) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      // Run the deterministic boundary hook before the first proof. Never
      // fsync bytes that have already diverged from the captured bounded read.
      beforeFsync?.call(ExperienceAuthoringStateFsyncTarget.existingFile);
      _readAndRequireExactStable(existingFd, bytes, initialStat);
      _fsyncChecked(
        existingFd,
        target: ExperienceAuthoringStateFsyncTarget.existingFile,
        beforeFsync: null,
      );
      _readAndRequireExactStable(existingFd, bytes, initialStat);
      _fsyncChecked(
        parentFd,
        target: ExperienceAuthoringStateFsyncTarget.existingParent,
        beforeFsync: beforeFsync,
      );
      if (_regularSingleLinkStat(existingFd) != initialStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      // The first FD proves an inode, while the receipt authorizes a name.
      // Re-open the basename after the parent fsync so a replacement during
      // the proof cannot make us bless a detached old inode.
      final reboundFd = _openRegularAt(parentFd, request.segments.last);
      descriptors.add(reboundFd);
      final reboundStat = _regularSingleLinkStat(reboundFd);
      if (reboundStat != initialStat) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      _readAndRequireExactStable(reboundFd, bytes, reboundStat);
      _requireDirectoryTreeRebound(request.workspaceRoot, workspaceRootStat);
      receipt = ExperienceAuthoringDurableWriteReceipt._(
        protocol: experienceAuthoringDurableWriteProtocol,
        workspaceAuthorityDigest: _authoringStateAuthorityDigest(
          workspaceStore,
        ),
        relativePath: relativePath,
        digest: Digest.bytes(bytes),
        byteLength: bytes.length,
      );
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    for (final descriptor in descriptors.reversed) {
      if (close(descriptor) != 0 && failure == null) {
        failure = ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          diagnosticErrno: _errno,
        );
        failureStack = StackTrace.current;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    return receipt!;
  }

  ({String workspaceRoot, List<String> segments}) _resolveRequest(
    FileSystemWorkspaceStore workspaceStore,
    String relativePath,
  ) {
    final normalizedRelative = p.normalize(relativePath);
    final workspaceRoot = p.normalize(p.absolute(workspaceStore.workspaceRoot));
    final stateRoot = p.normalize(p.absolute(workspaceStore.stateRoot));
    final destinationPath = p.normalize(p.join(stateRoot, normalizedRelative));
    if (relativePath.contains('\u0000') ||
        p.isAbsolute(relativePath) ||
        normalizedRelative == '.' ||
        normalizedRelative == '..' ||
        normalizedRelative.startsWith('../') ||
        normalizedRelative != relativePath ||
        !p.isWithin(workspaceRoot, stateRoot) ||
        !p.isWithin(stateRoot, destinationPath)) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
    final stateRelative = p.relative(stateRoot, from: workspaceRoot);
    final segments = p.split(p.join(stateRelative, normalizedRelative));
    if (segments.length < 2 ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains('\u0000'),
        )) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
    return (workspaceRoot: workspaceRoot, segments: segments);
  }

  int _openDirectory(String path) {
    final pointer = path.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = open(
        pointer,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        0,
      );
      if (descriptor < 0) _throwErrno(path, _errno);
      try {
        _requireDirectory(descriptor);
        return descriptor;
      } on Object {
        close(descriptor);
        rethrow;
      }
    } finally {
      calloc.free(pointer);
    }
  }

  int _openDirectoryTree(String absolutePath, List<int> descriptors) {
    var current = _openDirectory('/');
    descriptors.add(current);
    for (final segment in p.posix.split(absolutePath)) {
      if (segment == '/' || segment == '.' || segment.isEmpty) continue;
      final next = _openDirectoryAt(current, segment);
      descriptors.add(next);
      current = next;
    }
    return current;
  }

  void _requireDirectoryTreeRebound(
    String absolutePath,
    _AuthoringLinuxFileStat expectedRoot,
  ) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    try {
      final rebound = _openDirectoryTree(absolutePath, descriptors);
      final reboundStat = _readStat(rebound);
      if (!_sameDirectoryIdentity(reboundStat, expectedRoot)) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    for (final descriptor in descriptors.reversed) {
      if (close(descriptor) != 0 && failure == null) {
        failure = ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          diagnosticErrno: _errno,
        );
        failureStack = StackTrace.current;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  int _openDirectoryAt(int parentFd, String name) {
    final descriptor = _openAtChecked(
      parentFd,
      name,
      _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      0,
    );
    try {
      _requireDirectory(descriptor);
      return descriptor;
    } on Object {
      close(descriptor);
      rethrow;
    }
  }

  int? _openDirectoryAtOptional(int parentFd, String name) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(
        parentFd,
        pointer,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        0,
      );
      if (descriptor >= 0) {
        try {
          _requireDirectory(descriptor);
          return descriptor;
        } on Object {
          close(descriptor);
          rethrow;
        }
      }
      final errno = _errno;
      if (errno == 2) return null;
      _throwErrno(name, errno);
    } finally {
      calloc.free(pointer);
    }
  }

  int _openRegularAt(int parentFd, String name) {
    final descriptor = _openAtChecked(
      parentFd,
      name,
      _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      0,
    );
    try {
      _regularSingleLinkStat(descriptor);
      return descriptor;
    } on Object {
      close(descriptor);
      rethrow;
    }
  }

  int? _openAtOptionalFile(int parentFd, String name, int flags) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(parentFd, pointer, flags, 0);
      if (descriptor >= 0) return descriptor;
      final errno = _errno;
      if (errno == 2) return null;
      _throwErrno(name, errno);
    } finally {
      calloc.free(pointer);
    }
  }

  int _openAtCreateExclusive(int parentFd, String name, int flags, int mode) =>
      _openAtChecked(parentFd, name, flags, mode);

  int _openAtCreate(int parentFd, String name, int flags, int mode) =>
      _openAtChecked(parentFd, name, flags, mode);

  int _openAtChecked(int parentFd, String name, int flags, int mode) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(parentFd, pointer, flags, mode);
      if (descriptor < 0) _throwErrno(name, _errno);
      return descriptor;
    } finally {
      calloc.free(pointer);
    }
  }

  void _mkdirAtChecked(int parentFd, String name) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      if (mkdirAt(parentFd, pointer, _privateDirectoryPermissions) != 0) {
        _throwErrno(name, _errno);
      }
    } finally {
      calloc.free(pointer);
    }
  }

  void _renameAt2Checked(
    int oldParentFd,
    String oldName,
    int newParentFd,
    String newName,
    int flags,
  ) {
    final oldPointer = oldName.toNativeUtf8(allocator: calloc);
    final newPointer = newName.toNativeUtf8(allocator: calloc);
    try {
      if (renameAt2(oldParentFd, oldPointer, newParentFd, newPointer, flags) !=
          0) {
        final errno = _errno;
        if (errno == 17) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
        _throwErrno(null, errno);
      }
    } finally {
      calloc.free(newPointer);
      calloc.free(oldPointer);
    }
  }

  void _discardCreatedStagingExact(int parentFd, String name, int stagingFd) {
    final expected = _regularSingleLinkStat(stagingFd);
    final pointer = name.toNativeUtf8(allocator: calloc);
    int? reboundFd;
    try {
      reboundFd = openAt(
        parentFd,
        pointer,
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
        0,
      );
      if (reboundFd < 0) {
        final errno = _errno;
        if (errno == 2) return;
        _throwErrno(name, errno);
      }
      final rebound = _regularSingleLinkStat(reboundFd);
      if (rebound != expected) {
        throw const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.unproven,
        );
      }
      if (unlinkAt(parentFd, pointer, 0) != 0) {
        _throwErrno(name, _errno);
      }
      _fsyncChecked(
        parentFd,
        target: ExperienceAuthoringStateFsyncTarget.destinationParent,
        beforeFsync: null,
      );
    } finally {
      if (reboundFd != null && close(reboundFd) != 0) {
        throw ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          diagnosticErrno: _errno,
        );
      }
      calloc.free(pointer);
    }
  }

  void _writeAll(int descriptor, List<int> bytes) {
    if (bytes.isEmpty) return;
    final pointer = calloc<ffi.Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final count = pwrite(
          descriptor,
          (pointer + offset).cast(),
          bytes.length - offset,
          offset,
        );
        if (count < 0 && _errno == 4) continue;
        if (count <= 0) _throwErrno(null, count < 0 ? _errno : 5);
        offset += count;
      }
    } finally {
      calloc.free(pointer);
    }
  }

  void _readAndRequireExactStable(
    int descriptor,
    List<int> expected,
    _AuthoringLinuxFileStat initialStat,
  ) {
    if (initialStat.size != expected.length) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unproven,
      );
    }
    if (expected.isNotEmpty) {
      final pointer = calloc<ffi.Uint8>(expected.length);
      try {
        var offset = 0;
        while (offset < expected.length) {
          final count = pread(
            descriptor,
            (pointer + offset).cast(),
            expected.length - offset,
            offset,
          );
          if (count < 0 && _errno == 4) continue;
          if (count <= 0) _throwErrno(null, count < 0 ? _errno : 5);
          offset += count;
        }
        if (!_bytesEqual(pointer.asTypedList(expected.length), expected)) {
          throw const ExperienceAuthoringStateDurabilityFailure._(
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          );
        }
      } finally {
        calloc.free(pointer);
      }
    }
    if (_regularSingleLinkStat(descriptor) != initialStat) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unproven,
      );
    }
  }

  void _fsyncChecked(
    int descriptor, {
    required ExperienceAuthoringStateFsyncTarget target,
    required ExperienceAuthoringStateFsyncHook? beforeFsync,
  }) {
    beforeFsync?.call(target);
    if (fsync(descriptor) != 0) _throwErrno(null, _errno);
  }

  _AuthoringLinuxFileStat _regularSingleLinkStat(int descriptor) {
    final stat = _readStat(descriptor);
    if ((stat.mode & _fileTypeMask) != _regularFileMode ||
        stat.linkCount != 1 ||
        stat.size < 0) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  bool _sameStableEntity(
    _AuthoringLinuxFileStat left,
    _AuthoringLinuxFileStat right,
  ) =>
      left.device == right.device &&
      left.inode == right.inode &&
      left.linkCount == right.linkCount &&
      left.mode == right.mode &&
      left.userId == right.userId &&
      left.groupId == right.groupId &&
      left.size == right.size;

  bool _sameDirectoryIdentity(
    _AuthoringLinuxFileStat left,
    _AuthoringLinuxFileStat right,
  ) =>
      (left.mode & _fileTypeMask) == _directoryMode &&
      (right.mode & _fileTypeMask) == _directoryMode &&
      left.device == right.device &&
      left.inode == right.inode;

  _AuthoringLinuxFileStat _requirePrivateGuard(int descriptor) {
    final stat = _regularSingleLinkStat(descriptor);
    if (stat.userId != effectiveUserId() ||
        (stat.mode & 0xfff) != _privateFilePermissions ||
        stat.size != 0) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  _AuthoringLinuxFileStat _requirePrivateStateSlot(int descriptor) {
    final stat = _regularSingleLinkStat(descriptor);
    if (stat.userId != effectiveUserId() ||
        (stat.mode & 0xfff) != _privateFilePermissions) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  void _requireDirectory(int descriptor) {
    if ((_readStat(descriptor).mode & _fileTypeMask) != _directoryMode) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
  }

  void _requirePrivateDirectory(int descriptor) {
    final stat = _readStat(descriptor);
    if ((stat.mode & _fileTypeMask) != _directoryMode ||
        stat.userId != effectiveUserId() ||
        (stat.mode & 0xfff) != _privateDirectoryPermissions) {
      throw const ExperienceAuthoringStateDurabilityFailure._(
        ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
      );
    }
  }

  _AuthoringLinuxFileStat _readEntryStatAt(int parentFd, String name) {
    final namePointer = name.toNativeUtf8(allocator: calloc);
    final statPointer = calloc<_AuthoringLinuxStat>();
    try {
      if (fstatAt(parentFd, namePointer, statPointer, _atSymlinkNoFollow) !=
          0) {
        _throwErrno(name, _errno);
      }
      return _authoringLinuxFileStat(statPointer.ref);
    } finally {
      calloc.free(statPointer);
      calloc.free(namePointer);
    }
  }

  _AuthoringLinuxFileStat _readStat(int descriptor) {
    final pointer = calloc<_AuthoringLinuxStat>();
    try {
      if (fstat(descriptor, pointer) != 0) _throwErrno(null, _errno);
      return _authoringLinuxFileStat(pointer.ref);
    } finally {
      calloc.free(pointer);
    }
  }

  Never _throwErrno(String? path, int errno) {
    final code = _unsupportedErrnos.contains(errno)
        ? ExperienceAuthoringStateDurabilityFailureCode.unsupported
        : errno == 20 || errno == 40
        ? ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity
        : ExperienceAuthoringStateDurabilityFailureCode.ioFailure;
    throw ExperienceAuthoringStateDurabilityFailure._(
      code,
      diagnosticPath: path,
      diagnosticErrno: errno,
    );
  }

  ExperienceAuthoringStateDurabilityFailure _sanitize(Object error) =>
      error is ExperienceAuthoringStateDurabilityFailure
      ? error
      : const ExperienceAuthoringStateDurabilityFailure._(
          ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
        );
}

final class _AuthoringLinuxFileStat {
  const _AuthoringLinuxFileStat({
    required this.device,
    required this.inode,
    required this.linkCount,
    required this.mode,
    required this.userId,
    required this.groupId,
    required this.size,
    required this.modifiedSeconds,
    required this.modifiedNanoseconds,
    required this.changedSeconds,
    required this.changedNanoseconds,
  });

  final int device;
  final int inode;
  final int linkCount;
  final int mode;
  final int userId;
  final int groupId;
  final int size;
  final int modifiedSeconds;
  final int modifiedNanoseconds;
  final int changedSeconds;
  final int changedNanoseconds;

  @override
  int get hashCode => Object.hash(
    device,
    inode,
    linkCount,
    mode,
    userId,
    groupId,
    size,
    modifiedSeconds,
    modifiedNanoseconds,
    changedSeconds,
    changedNanoseconds,
  );

  @override
  bool operator ==(Object other) =>
      other is _AuthoringLinuxFileStat &&
      other.device == device &&
      other.inode == inode &&
      other.linkCount == linkCount &&
      other.mode == mode &&
      other.userId == userId &&
      other.groupId == groupId &&
      other.size == size &&
      other.modifiedSeconds == modifiedSeconds &&
      other.modifiedNanoseconds == modifiedNanoseconds &&
      other.changedSeconds == changedSeconds &&
      other.changedNanoseconds == changedNanoseconds;
}

_AuthoringLinuxFileStat _authoringLinuxFileStat(_AuthoringLinuxStat stat) =>
    _AuthoringLinuxFileStat(
      device: stat.device,
      inode: stat.inode,
      linkCount: stat.linkCount,
      mode: stat.mode,
      userId: stat.userId,
      groupId: stat.groupId,
      size: stat.size,
      modifiedSeconds: stat.modified.seconds,
      modifiedNanoseconds: stat.modified.nanoseconds,
      changedSeconds: stat.changed.seconds,
      changedNanoseconds: stat.changed.nanoseconds,
    );

final class _AuthoringLinuxTimespec extends ffi.Struct {
  @ffi.Int64()
  external int seconds;

  @ffi.Int64()
  external int nanoseconds;
}

/// glibc Linux x64 `struct stat` layout. Every other ABI is unsupported.
final class _AuthoringLinuxStat extends ffi.Struct {
  @ffi.Uint64()
  external int device;

  @ffi.Uint64()
  external int inode;

  @ffi.Uint64()
  external int linkCount;

  @ffi.Uint32()
  external int mode;

  @ffi.Uint32()
  external int userId;

  @ffi.Uint32()
  external int groupId;

  @ffi.Int32()
  external int padding;

  @ffi.Uint64()
  external int deviceType;

  @ffi.Int64()
  external int size;

  @ffi.Int64()
  external int blockSize;

  @ffi.Int64()
  external int blockCount;

  external _AuthoringLinuxTimespec accessed;
  external _AuthoringLinuxTimespec modified;
  external _AuthoringLinuxTimespec changed;

  @ffi.Array.multi(<int>[3])
  external ffi.Array<ffi.Int64> reserved;
}

typedef _AuthoringOpenNative =
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint32);
typedef _AuthoringOpenDart = int Function(ffi.Pointer<Utf8>, int, int);
typedef _AuthoringOpenAtNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint32);
typedef _AuthoringOpenAtDart = int Function(int, ffi.Pointer<Utf8>, int, int);
typedef _AuthoringCloseNative = ffi.Int32 Function(ffi.Int32);
typedef _AuthoringCloseDart = int Function(int);
typedef _AuthoringFstatNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<_AuthoringLinuxStat>);
typedef _AuthoringFstatDart =
    int Function(int, ffi.Pointer<_AuthoringLinuxStat>);
typedef _AuthoringFstatAtNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Pointer<_AuthoringLinuxStat>,
      ffi.Int32,
    );
typedef _AuthoringFstatAtDart =
    int Function(int, ffi.Pointer<Utf8>, ffi.Pointer<_AuthoringLinuxStat>, int);
typedef _AuthoringPwriteNative =
    ffi.IntPtr Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Int64);
typedef _AuthoringPwriteDart =
    int Function(int, ffi.Pointer<ffi.Void>, int, int);
typedef _AuthoringPreadNative =
    ffi.IntPtr Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Int64);
typedef _AuthoringPreadDart =
    int Function(int, ffi.Pointer<ffi.Void>, int, int);
typedef _AuthoringFsyncNative = ffi.Int32 Function(ffi.Int32);
typedef _AuthoringFsyncDart = int Function(int);
typedef _AuthoringFtruncateNative = ffi.Int32 Function(ffi.Int32, ffi.Int64);
typedef _AuthoringFtruncateDart = int Function(int, int);
typedef _AuthoringFchmodNative = ffi.Int32 Function(ffi.Int32, ffi.Uint32);
typedef _AuthoringFchmodDart = int Function(int, int);
typedef _AuthoringMkdirAtNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Uint32);
typedef _AuthoringMkdirAtDart = int Function(int, ffi.Pointer<Utf8>, int);
typedef _AuthoringRenameAt2Native =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Uint32,
    );
typedef _AuthoringRenameAt2Dart =
    int Function(int, ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>, int);
typedef _AuthoringUnlinkAtNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32);
typedef _AuthoringUnlinkAtDart = int Function(int, ffi.Pointer<Utf8>, int);
typedef _AuthoringFlockNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _AuthoringFlockDart = int Function(int, int);
typedef _AuthoringGeteuidNative = ffi.Uint32 Function();
typedef _AuthoringGeteuidDart = int Function();
typedef _AuthoringErrnoLocationNative = ffi.Pointer<ffi.Int32> Function();
typedef _AuthoringErrnoLocationDart = ffi.Pointer<ffi.Int32> Function();

Digest _authoringStateAuthorityDigest(
  FileSystemWorkspaceStore workspaceStore,
) => Digest.semantic(<String, Object?>{
  'protocol': experienceAuthoringDurableWriteProtocol,
  'workspaceRoot': p.normalize(p.absolute(workspaceStore.workspaceRoot)),
  'stateRoot': p.normalize(p.absolute(workspaceStore.stateRoot)),
});
