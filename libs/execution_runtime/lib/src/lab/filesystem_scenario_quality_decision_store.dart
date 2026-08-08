import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';

import '../storage/filesystem_workspace_store.dart';

final class ScenarioQualityDecisionStoreFailure implements Exception {
  const ScenarioQualityDecisionStoreFailure(
    this.code, {
    this.currentQualityDigest,
    this.currentDecisionDigest,
  });

  final ScenarioQualityDecisionErrorCode code;
  final Digest? currentQualityDigest;
  final Digest? currentDecisionDigest;
}

final class ScenarioQualityDecisionHistory {
  ScenarioQualityDecisionHistory({
    required this.quality,
    required Iterable<HumanDecisionRecord> records,
    required Map<Digest, ScenarioQualityDecisionAttribution> attributions,
    required Map<Digest, ScenarioQualityReviewDescriptor> reviewDescriptors,
  }) : records = List<HumanDecisionRecord>.unmodifiable(records),
       attributions =
           Map<Digest, ScenarioQualityDecisionAttribution>.unmodifiable(
             attributions,
           ),
       reviewDescriptors =
           Map<Digest, ScenarioQualityReviewDescriptor>.unmodifiable(
             reviewDescriptors,
           ) {
    if (this.records.any(
          (record) =>
              !this.attributions.containsKey(record.digest) ||
              !this.reviewDescriptors.containsKey(record.digest),
        ) ||
        this.attributions.length != this.records.length ||
        this.reviewDescriptors.length != this.records.length) {
      throw ArgumentError('Decision history attribution is incomplete');
    }
  }

  final ScenarioQualitySnapshot quality;
  final List<HumanDecisionRecord> records;
  final Map<Digest, ScenarioQualityDecisionAttribution> attributions;
  final Map<Digest, ScenarioQualityReviewDescriptor> reviewDescriptors;

  HumanDecisionRecord? get head => records.lastOrNull;

  ScenarioQualityDecisionView? view(Digest digest) {
    final index = records.indexWhere((record) => record.digest == digest);
    if (index < 0) return null;
    final record = records[index];
    final attribution = attributions[record.digest]!;
    final descriptor = reviewDescriptors[record.digest]!;
    if (index + 1 < records.length) {
      return ScenarioQualityDecisionView(
        record: record,
        projection: HumanDecisionProjection(
          state: HumanDecisionState.superseded,
          decisionDigest: record.digest,
          supersededByDecisionDigest: records[index + 1].digest,
        ),
        attribution: attribution,
        reviewDescriptor: descriptor,
      );
    }
    return ScenarioQualityDecisionView(
      record: record,
      projection: HumanDecisionProjection(
        state: switch (record.decision) {
          HumanDecision.approved => HumanDecisionState.approved,
          HumanDecision.rejected => HumanDecisionState.rejected,
        },
        decisionDigest: record.digest,
      ),
      attribution: attribution,
      reviewDescriptor: descriptor,
    );
  }
}

/// Durable JCS/hash-chain authority for grants and human decisions.
final class FilesystemScenarioQualityDecisionStore {
  FilesystemScenarioQualityDecisionStore({
    required this.workspaceStore,
    this.maxDecisionsPerRun = 100,
    this.maxGrantsPerRun = 1000,
    this.maxActiveGrants = 64,
    this.maxJournalEntries = 100000,
  }) {
    if (maxDecisionsPerRun < 1 ||
        maxDecisionsPerRun > 100 ||
        maxGrantsPerRun < 1 ||
        maxActiveGrants < 1 ||
        maxJournalEntries < maxDecisionsPerRun + maxGrantsPerRun) {
      throw ArgumentError('Scenario Quality store quotas are invalid');
    }
    _locked(() => _load());
  }

  static const String statePath =
      'scenario-quality/human-decisions.journal.json';
  static const int _maxStateBytes = 64 * 1024 * 1024;
  static const int _terminalEntryReserveBytes = 256 * 1024;

  final FileSystemWorkspaceStore workspaceStore;
  final int maxDecisionsPerRun;
  final int maxGrantsPerRun;
  final int maxActiveGrants;
  final int maxJournalEntries;

  ScenarioQualityDecisionHistory history({
    required ScenarioQualitySnapshot baseQuality,
    required ScenarioLabRunResult result,
  }) => _locked(() {
    final state = _load();
    return _history(state, baseQuality: baseQuality, result: result);
  });

  ScenarioQualityDecisionGrant? replayGrant(
    ScenarioQualityDecisionGrantRequest request,
  ) => _locked(() {
    final prior = _load().requestById[request.requestId.value];
    if (prior == null) return null;
    if (prior.requestDigest != request.digest || prior.grant == null) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.requestConflict,
      );
    }
    return prior.grant;
  });

  ScenarioQualityDecisionAppendResult? replayAppend(
    ScenarioQualityDecisionAppendRequest request,
  ) => _locked(() {
    final prior = _load().requestById[request.requestId.value];
    if (prior == null) return null;
    if (prior.requestDigest != request.digest) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.requestConflict,
      );
    }
    if (prior.appendResult case final result?) return result;
    if (prior.appendError case final error?) {
      throw ScenarioQualityDecisionStoreFailure(
        error.code,
        currentQualityDigest: error.currentQualityDigest,
        currentDecisionDigest: error.currentDecisionDigest,
      );
    }
    throw const ScenarioQualityDecisionStoreFailure(
      ScenarioQualityDecisionErrorCode.requestConflict,
    );
  });

  /// Validates the bearer binding before any mutable Host/environment fence.
  /// A structurally valid request that identifies a real grant is one attempt:
  /// expiry or any request/grant divergence is durably consumed here.
  void prepareAppendAttempt({
    required ScenarioQualityDecisionAppendRequest request,
    required DateTime now,
  }) => _locked(() {
    final state = _load();
    final prior = state.requestById[request.requestId.value];
    if (prior != null) {
      if (prior.requestDigest != request.digest) {
        throw const ScenarioQualityDecisionStoreFailure(
          ScenarioQualityDecisionErrorCode.requestConflict,
        );
      }
      if (prior.appendError case final error?) {
        throw ScenarioQualityDecisionStoreFailure(
          error.code,
          currentQualityDigest: error.currentQualityDigest,
          currentDecisionDigest: error.currentDecisionDigest,
        );
      }
      if (prior.appendResult != null) return;
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.requestConflict,
      );
    }
    final stored = state.grants[request.grantId.value];
    if (stored == null || stored.grant.digest != request.grantDigest) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantMismatch,
      );
    }
    if (stored.revoked) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantRevoked,
      );
    }
    if (stored.expired) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantExpired,
      );
    }
    if (stored.consumed) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantConsumed,
      );
    }
    final instant = now.toUtc();
    if (!_requestMatchesStoredGrant(request, stored.grant)) {
      _consumeAttempt(
        state,
        request: request,
        grant: stored.grant,
        consumedAt: instant,
        code: ScenarioQualityDecisionErrorCode.grantMismatch,
      );
    }
    if (instant.isBefore(stored.grant.issuedAt)) {
      _consumeAttempt(
        state,
        request: request,
        grant: stored.grant,
        consumedAt: instant,
        code: ScenarioQualityDecisionErrorCode.grantExpired,
      );
    }
    if (!instant.isBefore(stored.grant.expiresAt)) {
      final expired = state.add(_JournalEventType.expire, <String, Object?>{
        'grantId': stored.grant.id.value,
        'expiredAt': stored.grant.expiresAt.toIso8601String(),
      });
      _persist(expired);
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantExpired,
      );
    }
  });

  /// Terminalizes an environmental failure discovered only after the exact
  /// bearer/request binding above was established.
  Never consumePreparedAttempt({
    required ScenarioQualityDecisionAppendRequest request,
    required DateTime now,
    required ScenarioQualityDecisionErrorCode code,
    Digest? currentQualityDigest,
    Digest? currentDecisionDigest,
  }) => _locked(() {
    final state = _load();
    final stored = state.grants[request.grantId.value];
    if (stored == null ||
        stored.revoked ||
        stored.expired ||
        stored.consumed ||
        !_requestMatchesStoredGrant(request, stored.grant)) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantMismatch,
      );
    }
    _consumeAttempt(
      state,
      request: request,
      grant: stored.grant,
      consumedAt: now.toUtc(),
      code: code,
      currentQualityDigest: currentQualityDigest,
      currentDecisionDigest: currentDecisionDigest,
    );
  });

  ScenarioQualityDecisionGrant issueGrant({
    required ScenarioQualityDecisionGrantRequest request,
    required ScenarioQualitySnapshot baseQuality,
    required ScenarioLabRunResult result,
    required ScenarioQualityReviewDescriptor reviewDescriptor,
    required DateTime now,
    required ScenarioQualityDecisionGrant Function(
      ScenarioQualitySnapshot quality,
      HumanDecisionRecord? head,
    )
    createGrant,
  }) => _locked(() {
    var state = _load();
    final prior = state.requestById[request.requestId.value];
    if (prior != null) {
      if (prior.requestDigest != request.digest || prior.grant == null) {
        throw const ScenarioQualityDecisionStoreFailure(
          ScenarioQualityDecisionErrorCode.requestConflict,
        );
      }
      return prior.grant!;
    }
    state = _expireOutstanding(state, now.toUtc());
    final history = _history(state, baseQuality: baseQuality, result: result);
    _validateGrantRequest(
      request,
      history: history,
      result: result,
      reviewDescriptor: reviewDescriptor,
    );
    final grantsForRun = state.grants.values
        .where((grant) => grant.grant.runId == request.runId)
        .length;
    final activeGrants = state.grants.values
        .where(
          (grant) =>
              !grant.revoked &&
              !grant.expired &&
              !grant.consumed &&
              now.toUtc().isBefore(grant.grant.expiresAt),
        )
        .length;
    if (grantsForRun >= maxGrantsPerRun ||
        activeGrants >= maxActiveGrants ||
        state.entries.length >= maxJournalEntries) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    final grant = createGrant(history.quality, history.head);
    _validateCreatedGrant(
      grant,
      request: request,
      history: history,
      result: result,
      reviewDescriptor: reviewDescriptor,
      now: now.toUtc(),
    );
    if (state.grants.containsKey(grant.id.value)) {
      throw StateError('Scenario Quality grant ID collision');
    }
    final next = state.add(_JournalEventType.grant, <String, Object?>{
      'request': request.toJson(),
      'grant': grant.toJson(),
      'reviewDescriptor': reviewDescriptor.toJson(),
    });
    final outstandingGrants = next.grants.values
        .where(
          (stored) => !stored.revoked && !stored.expired && !stored.consumed,
        )
        .length;
    if (next.entries.length + outstandingGrants > maxJournalEntries ||
        _encodedStateBytes(next).length +
                (outstandingGrants * _terminalEntryReserveBytes) >
            _maxStateBytes) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    _persist(next);
    return grant;
  });

  ScenarioQualityDecisionAppendResult append({
    required ScenarioQualityDecisionAppendRequest request,
    required ScenarioQualitySnapshot baseQuality,
    required ScenarioLabRunResult result,
    ScenarioQualityReviewDescriptor? reviewDescriptor,
    required ScenarioQualityDecisionErrorCode? preflightRejection,
    required ScenarioQualityAuthorityId? currentAuthorityId,
    required ScenarioQualityAccessPolicyId? currentAccessPolicyId,
    required ScenarioQualityPrincipalId? currentPrincipalId,
    required ScenarioQualityDecisionRole? currentRole,
    required bool decisionCurrentlyAllowed,
    required DateTime now,
    required HumanDecisionRecordId Function() createRecordId,
    required bool Function(ScenarioQualityDecisionAppendResult result)
    canReturnResult,
  }) => _locked(() {
    final state = _load();
    final prior = state.requestById[request.requestId.value];
    if (prior != null) {
      if (prior.requestDigest != request.digest) {
        throw const ScenarioQualityDecisionStoreFailure(
          ScenarioQualityDecisionErrorCode.requestConflict,
        );
      }
      final result = prior.appendResult;
      if (result != null) return result;
      final error = prior.appendError;
      if (error != null) {
        throw ScenarioQualityDecisionStoreFailure(
          error.code,
          currentQualityDigest: error.currentQualityDigest,
          currentDecisionDigest: error.currentDecisionDigest,
        );
      }
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.requestConflict,
      );
    }

    final history = _history(state, baseQuality: baseQuality, result: result);
    final grantState = state.grants[request.grantId.value];
    if (grantState == null || grantState.grant.digest != request.grantDigest) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantMismatch,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    if (grantState.revoked) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantRevoked,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    if (grantState.expired) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantExpired,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    if (grantState.consumed) {
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.grantConsumed,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }

    ScenarioQualityDecisionErrorCode? rejected;
    final grant = grantState.grant;
    if (!_appendMatchesGrantBase(request, grant: grant, result: result)) {
      rejected = ScenarioQualityDecisionErrorCode.grantMismatch;
    } else if (now.toUtc().isBefore(grant.issuedAt) ||
        !now.toUtc().isBefore(grant.expiresAt)) {
      rejected = ScenarioQualityDecisionErrorCode.grantExpired;
    } else if (preflightRejection != null) {
      rejected = preflightRejection;
    } else if (reviewDescriptor == null ||
        request.expectedReviewDescriptorDigest != reviewDescriptor.digest) {
      rejected = ScenarioQualityDecisionErrorCode.grantMismatch;
    } else if (grant.authorityId != currentAuthorityId ||
        grant.accessPolicyId != currentAccessPolicyId ||
        grant.principalId != currentPrincipalId ||
        grant.role != currentRole) {
      rejected = ScenarioQualityDecisionErrorCode.policyDenied;
    } else if (!decisionCurrentlyAllowed) {
      rejected = ScenarioQualityDecisionErrorCode.decisionDenied;
    } else if (request.expectedQualityDigest != history.quality.digest) {
      rejected = ScenarioQualityDecisionErrorCode.staleQuality;
    } else if (request.expectedPreviousDecisionDigest != history.head?.digest) {
      rejected = ScenarioQualityDecisionErrorCode.stalePreviousDecision;
    }
    if (rejected != null) {
      final error = ScenarioQualityDecisionError(
        operation: ScenarioQualityDecisionOperation.append,
        code: rejected,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
      if (state.entries.length >= maxJournalEntries) {
        throw const ScenarioQualityDecisionStoreFailure(
          ScenarioQualityDecisionErrorCode.quotaExceeded,
        );
      }
      _persist(
        state.add(_JournalEventType.consume, <String, Object?>{
          'request': request.toJson(),
          'grantId': grant.id.value,
          'consumedAt': now.toUtc().toIso8601String(),
          'error': error.toJson(),
        }),
      );
      throw ScenarioQualityDecisionStoreFailure(
        rejected,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }

    if (history.records.length >= maxDecisionsPerRun ||
        state.entries.length >= maxJournalEntries) {
      final error = ScenarioQualityDecisionError(
        operation: ScenarioQualityDecisionOperation.append,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
      if (state.entries.length < maxJournalEntries) {
        _persist(
          state.add(_JournalEventType.consume, <String, Object?>{
            'request': request.toJson(),
            'grantId': grant.id.value,
            'consumedAt': now.toUtc().toIso8601String(),
            'error': error.toJson(),
          }),
        );
      }
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }

    final decidedAt = _strictDecisionTime(now.toUtc(), history.head);
    final record = HumanDecisionRecord(
      id: createRecordId(),
      subjectDigest: result.digest,
      principalId: grant.principalId,
      decision: request.decision,
      decidedAt: decidedAt,
      supersedesDecisionDigest: history.head?.digest,
    );
    if (state.recordIds.contains(record.id.value)) {
      throw StateError('Scenario Quality decision record ID collision');
    }
    if (history.head case final previous?) record.validateSupersedes(previous);
    final quality = _qualityWithRecord(baseQuality, record);
    quality.validateAgainstResult(result);
    final appendResult = ScenarioQualityDecisionAppendResult(
      requestId: request.requestId,
      requestDigest: request.digest,
      attribution: ScenarioQualityDecisionAttribution(
        runId: grant.runId,
        runResultDigest: grant.runResultDigest,
        reviewDescriptorDigest: grant.reviewDescriptorDigest,
        requirementId: grant.requirementId,
        requirementScope: grant.requirementScope,
        reviewGuideId: grant.reviewGuideId,
        reviewGuideStepId: grant.reviewGuideStepId,
        authorityId: grant.authorityId,
        accessPolicyId: grant.accessPolicyId,
        principalId: grant.principalId,
        role: grant.role,
        grantDigest: grant.digest,
        grantRequestDigest: grant.requestDigest,
        decisionRequestDigest: request.digest,
      ),
      record: record,
      quality: quality,
    );
    if (!canReturnResult(appendResult)) {
      final error = ScenarioQualityDecisionError(
        operation: ScenarioQualityDecisionOperation.append,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
      _persist(
        state.add(_JournalEventType.consume, <String, Object?>{
          'request': request.toJson(),
          'grantId': grant.id.value,
          'consumedAt': now.toUtc().toIso8601String(),
          'error': error.toJson(),
        }),
      );
      throw ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
        currentQualityDigest: history.quality.digest,
        currentDecisionDigest: history.head?.digest,
      );
    }
    final next = state.add(_JournalEventType.append, <String, Object?>{
      'request': request.toJson(),
      'grantId': grant.id.value,
      'consumedAt': now.toUtc().toIso8601String(),
      'result': appendResult.toJson(),
    });
    _persist(next);
    return appendResult;
  });

  bool revokeGrant({
    required ScenarioQualityDecisionGrantId grantId,
    required DateTime revokedAt,
  }) => _locked(() {
    final state = _load();
    final grant = state.grants[grantId.value];
    if (grant == null) return false;
    if (grant.revoked || grant.expired || grant.consumed) return false;
    if (state.entries.length >= maxJournalEntries) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
      );
    }
    _persist(
      state.add(_JournalEventType.revoke, <String, Object?>{
        'grantId': grantId.value,
        'revokedAt': revokedAt.toUtc().toIso8601String(),
      }),
    );
    return true;
  });

  ScenarioQualityDecisionView? getDecision({
    required ScenarioQualitySnapshot baseQuality,
    required ScenarioLabRunResult result,
    required Digest decisionDigest,
  }) => history(baseQuality: baseQuality, result: result).view(decisionDigest);

  T _locked<T>(T Function() action) => workspaceStore.withExclusiveLock(action);

  _JournalState _load() {
    final bytes = workspaceStore.readStateBytesBounded(
      statePath,
      maxBytes: _maxStateBytes,
    );
    if (bytes == null) return _JournalState.empty();
    if (bytes.isEmpty || bytes.length > _maxStateBytes) {
      throw const FormatException('Scenario Quality journal size is invalid');
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> ||
        decoded.length != 3 ||
        decoded['schemaVersion'] != 1 ||
        decoded['kind'] != 'ScenarioQualityDecisionJournal' ||
        decoded['entries'] is! List<Object?>) {
      throw const FormatException('Invalid Scenario Quality journal');
    }
    final rawEntries = decoded['entries']! as List<Object?>;
    if (rawEntries.length > maxJournalEntries) {
      throw const FormatException('Scenario Quality journal exceeds quota');
    }
    final canonical = const JcsCanonicalizer().canonicalize(decoded);
    if (text != '$canonical\n') {
      throw const FormatException('Scenario Quality journal is not canonical');
    }
    var state = _JournalState.empty();
    for (final raw in rawEntries) {
      final entry = _JournalEntry.fromJson(
        raw,
        expectedSequence: state.entries.length,
        expectedPrevious: state.entries.lastOrNull?.digest,
      );
      state = state.replay(entry);
    }
    return state;
  }

  void _persist(_JournalState state) {
    final bytes = _encodedStateBytes(state);
    if (bytes.length > _maxStateBytes) {
      throw const ScenarioQualityDecisionStoreFailure(
        ScenarioQualityDecisionErrorCode.quotaExceeded,
      );
    }
    workspaceStore.atomicWrite(statePath, bytes);
  }

  List<int> _encodedStateBytes(_JournalState state) {
    final document = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'ScenarioQualityDecisionJournal',
      'entries': state.entries.map((entry) => entry.toJson()).toList(),
    };
    final canonical = const JcsCanonicalizer().canonicalize(document);
    return utf8.encode('$canonical\n');
  }

  Never _consumeAttempt(
    _JournalState state, {
    required ScenarioQualityDecisionAppendRequest request,
    required ScenarioQualityDecisionGrant grant,
    required DateTime consumedAt,
    required ScenarioQualityDecisionErrorCode code,
    Digest? currentQualityDigest,
    Digest? currentDecisionDigest,
  }) {
    final error = ScenarioQualityDecisionError(
      operation: ScenarioQualityDecisionOperation.append,
      code: code,
      runId: request.runId,
      expectedRunResultDigest: request.expectedRunResultDigest,
      requestId: request.requestId,
      currentQualityDigest: currentQualityDigest,
      currentDecisionDigest: currentDecisionDigest,
    );
    _persist(
      state.add(_JournalEventType.consume, <String, Object?>{
        'request': request.toJson(),
        'grantId': grant.id.value,
        'consumedAt': consumedAt.toUtc().toIso8601String(),
        'error': error.toJson(),
      }),
    );
    throw ScenarioQualityDecisionStoreFailure(
      code,
      currentQualityDigest: currentQualityDigest,
      currentDecisionDigest: currentDecisionDigest,
    );
  }

  _JournalState _expireOutstanding(_JournalState state, DateTime now) {
    var next = state;
    final expired =
        state.grants.values
            .where(
              (stored) =>
                  !stored.revoked &&
                  !stored.expired &&
                  !stored.consumed &&
                  !now.isBefore(stored.grant.expiresAt),
            )
            .toList()
          ..sort(
            (left, right) =>
                left.grant.id.value.compareTo(right.grant.id.value),
          );
    for (final stored in expired) {
      next = next.add(_JournalEventType.expire, <String, Object?>{
        'grantId': stored.grant.id.value,
        'expiredAt': stored.grant.expiresAt.toIso8601String(),
      });
    }
    return next;
  }

  ScenarioQualityDecisionHistory _history(
    _JournalState state, {
    required ScenarioQualitySnapshot baseQuality,
    required ScenarioLabRunResult result,
  }) {
    baseQuality.validateAgainstResult(result);
    if (baseQuality.humanDecision.state != HumanDecisionState.unreviewed) {
      throw ArgumentError('Base Quality must be unreviewed');
    }
    final records =
        state.recordsBySubject[result.digest.value] ??
        const <HumanDecisionRecord>[];
    final quality = records.isEmpty
        ? baseQuality
        : _qualityWithRecord(baseQuality, records.last);
    final stored = state.qualityBySubject[result.digest.value];
    if (stored != null && stored.digest != quality.digest) {
      throw const FormatException('Stored Quality projection is inconsistent');
    }
    quality.validateAgainstResult(result);
    return ScenarioQualityDecisionHistory(
      quality: quality,
      records: records,
      attributions: <Digest, ScenarioQualityDecisionAttribution>{
        for (final record in records)
          record.digest:
              state.attributionByRecordDigest[record.digest.value] ??
              (throw const FormatException(
                'Stored decision attribution is missing',
              )),
      },
      reviewDescriptors: <Digest, ScenarioQualityReviewDescriptor>{
        for (final record in records)
          record.digest:
              state.reviewDescriptorByRecordDigest[record.digest.value] ??
              (throw const FormatException(
                'Stored review descriptor is missing',
              )),
      },
    );
  }
}

DateTime _strictDecisionTime(DateTime now, HumanDecisionRecord? head) {
  final previous = head?.decidedAt;
  if (previous == null || now.isAfter(previous)) return now;
  return previous.add(const Duration(microseconds: 1));
}

ScenarioQualitySnapshot _qualityWithRecord(
  ScenarioQualitySnapshot base,
  HumanDecisionRecord record,
) => ScenarioQualitySnapshot(
  subjectDigest: base.subjectDigest,
  runId: base.runId,
  scenarioId: base.scenarioId,
  verificationState: base.verificationState,
  humanDecision: HumanDecisionProjection(
    state: switch (record.decision) {
      HumanDecision.approved => HumanDecisionState.approved,
      HumanDecision.rejected => HumanDecisionState.rejected,
    },
    decisionDigest: record.digest,
  ),
  requiredEvidence: base.requiredEvidence,
  comparisonResultDigests: base.comparisonResultDigests,
);

void _validateGrantRequest(
  ScenarioQualityDecisionGrantRequest request, {
  required ScenarioQualityDecisionHistory history,
  required ScenarioLabRunResult result,
  required ScenarioQualityReviewDescriptor reviewDescriptor,
}) {
  if (request.runId != result.finalSnapshot.runId ||
      request.expectedRunResultDigest != result.digest) {
    throw const ScenarioQualityDecisionStoreFailure(
      ScenarioQualityDecisionErrorCode.subjectMismatch,
    );
  }
  if (request.expectedQualityDigest != history.quality.digest) {
    throw ScenarioQualityDecisionStoreFailure(
      ScenarioQualityDecisionErrorCode.staleQuality,
      currentQualityDigest: history.quality.digest,
      currentDecisionDigest: history.head?.digest,
    );
  }
  if (request.expectedPreviousDecisionDigest != history.head?.digest) {
    throw ScenarioQualityDecisionStoreFailure(
      ScenarioQualityDecisionErrorCode.stalePreviousDecision,
      currentQualityDigest: history.quality.digest,
      currentDecisionDigest: history.head?.digest,
    );
  }
  if (request.expectedReviewDescriptorDigest != reviewDescriptor.digest ||
      reviewDescriptor.runId != request.runId ||
      reviewDescriptor.runResultDigest != result.digest ||
      reviewDescriptor.qualityDigest != history.quality.digest) {
    throw ScenarioQualityDecisionStoreFailure(
      ScenarioQualityDecisionErrorCode.grantMismatch,
      currentQualityDigest: history.quality.digest,
      currentDecisionDigest: history.head?.digest,
    );
  }
}

void _validateCreatedGrant(
  ScenarioQualityDecisionGrant grant, {
  required ScenarioQualityDecisionGrantRequest request,
  required ScenarioQualityDecisionHistory history,
  required ScenarioLabRunResult result,
  required ScenarioQualityReviewDescriptor reviewDescriptor,
  required DateTime now,
}) {
  if (grant.requestId != request.requestId ||
      grant.requestDigest != request.digest ||
      grant.runId != request.runId ||
      grant.runResultDigest != result.digest ||
      grant.qualityDigest != history.quality.digest ||
      grant.reviewDescriptorDigest != reviewDescriptor.digest ||
      grant.requirementId != reviewDescriptor.requirementId ||
      grant.requirementScope != reviewDescriptor.requirementScope ||
      grant.reviewGuideId != reviewDescriptor.reviewGuideId ||
      grant.reviewGuideStepId != reviewDescriptor.reviewGuideStepId ||
      grant.expectedPreviousDecisionDigest != history.head?.digest ||
      grant.decision != request.decision ||
      grant.issuedAt != now ||
      !grant.expiresAt.isAfter(now)) {
    throw ArgumentError('Host-created Scenario Quality grant is inconsistent');
  }
}

bool _appendMatchesGrantBase(
  ScenarioQualityDecisionAppendRequest request, {
  required ScenarioQualityDecisionGrant grant,
  required ScenarioLabRunResult result,
}) =>
    request.runId == grant.runId &&
    request.runId == result.finalSnapshot.runId &&
    request.expectedRunResultDigest == grant.runResultDigest &&
    request.expectedRunResultDigest == result.digest &&
    request.expectedQualityDigest == grant.qualityDigest &&
    request.expectedReviewDescriptorDigest == grant.reviewDescriptorDigest &&
    request.expectedPreviousDecisionDigest ==
        grant.expectedPreviousDecisionDigest &&
    request.decision == grant.decision;

enum _JournalEventType { grant, revoke, expire, append, consume }

final class _JournalEntry {
  _JournalEntry({
    required this.sequence,
    required this.type,
    required this.previousEntryDigest,
    required this.payload,
  });

  final int sequence;
  final _JournalEventType type;
  final Digest? previousEntryDigest;
  final Map<String, Object?> payload;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'sequence': sequence,
    'type': type.name,
    if (previousEntryDigest != null)
      'previousEntryDigest': previousEntryDigest!.value,
    ...payload,
    if (includeDigest) 'digest': digest.value,
  };

  factory _JournalEntry.fromJson(
    Object? value, {
    required int expectedSequence,
    required Digest? expectedPrevious,
  }) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Scenario Quality journal entry is invalid');
    }
    final typeValue = value['type'];
    final type = _JournalEventType.values
        .where((candidate) => candidate.name == typeValue)
        .firstOrNull;
    if (type == null || value['sequence'] != expectedSequence) {
      throw const FormatException(
        'Scenario Quality journal sequence is invalid',
      );
    }
    final previousValue = value['previousEntryDigest'];
    final previous = previousValue == null
        ? null
        : previousValue is String
        ? Digest(previousValue)
        : (throw const FormatException('Invalid previous entry digest'));
    if (previous != expectedPrevious ||
        (expectedSequence == 0) != (previous == null)) {
      throw const FormatException('Scenario Quality hash chain is invalid');
    }
    final required = switch (type) {
      _JournalEventType.grant => const <String>{
        'request',
        'grant',
        'reviewDescriptor',
      },
      _JournalEventType.revoke => const <String>{'grantId', 'revokedAt'},
      _JournalEventType.expire => const <String>{'grantId', 'expiredAt'},
      _JournalEventType.append => const <String>{
        'request',
        'grantId',
        'consumedAt',
        'result',
      },
      _JournalEventType.consume => const <String>{
        'request',
        'grantId',
        'consumedAt',
        'error',
      },
    };
    final allowed = <String>{
      'sequence',
      'type',
      'previousEntryDigest',
      'digest',
      ...required,
    };
    if (!value.keys.toSet().containsAll(<String>{
          'sequence',
          'type',
          'digest',
          ...required,
        }) ||
        value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Scenario Quality journal entry is open');
    }
    final entry = _JournalEntry(
      sequence: expectedSequence,
      type: type,
      previousEntryDigest: previous,
      payload: <String, Object?>{for (final key in required) key: value[key]},
    );
    if (value['digest'] != entry.digest.value) {
      throw const FormatException('Scenario Quality entry digest mismatch');
    }
    return entry;
  }
}

final class _JournalState {
  _JournalState({
    required this.entries,
    required this.grants,
    required this.requestById,
    required this.recordsBySubject,
    required this.qualityBySubject,
    required this.attributionByRecordDigest,
    required this.reviewDescriptorByRecordDigest,
    required this.recordIds,
  });

  factory _JournalState.empty() => _JournalState(
    entries: const <_JournalEntry>[],
    grants: const <String, _StoredGrant>{},
    requestById: const <String, _StoredRequest>{},
    recordsBySubject: const <String, List<HumanDecisionRecord>>{},
    qualityBySubject: const <String, ScenarioQualitySnapshot>{},
    attributionByRecordDigest:
        const <String, ScenarioQualityDecisionAttribution>{},
    reviewDescriptorByRecordDigest:
        const <String, ScenarioQualityReviewDescriptor>{},
    recordIds: const <String>{},
  );

  final List<_JournalEntry> entries;
  final Map<String, _StoredGrant> grants;
  final Map<String, _StoredRequest> requestById;
  final Map<String, List<HumanDecisionRecord>> recordsBySubject;
  final Map<String, ScenarioQualitySnapshot> qualityBySubject;
  final Map<String, ScenarioQualityDecisionAttribution>
  attributionByRecordDigest;
  final Map<String, ScenarioQualityReviewDescriptor>
  reviewDescriptorByRecordDigest;
  final Set<String> recordIds;

  _JournalState add(_JournalEventType type, Map<String, Object?> payload) =>
      replay(
        _JournalEntry(
          sequence: entries.length,
          type: type,
          previousEntryDigest: entries.lastOrNull?.digest,
          payload: payload,
        ),
      );

  _JournalState replay(_JournalEntry entry) {
    final nextEntries = <_JournalEntry>[...entries, entry];
    final nextGrants = <String, _StoredGrant>{...grants};
    final nextRequests = <String, _StoredRequest>{...requestById};
    final nextRecords = <String, List<HumanDecisionRecord>>{
      for (final item in recordsBySubject.entries)
        item.key: List<HumanDecisionRecord>.of(item.value),
    };
    final nextQuality = <String, ScenarioQualitySnapshot>{...qualityBySubject};
    final nextAttributions = <String, ScenarioQualityDecisionAttribution>{
      ...attributionByRecordDigest,
    };
    final nextReviewDescriptors = <String, ScenarioQualityReviewDescriptor>{
      ...reviewDescriptorByRecordDigest,
    };
    final nextRecordIds = <String>{...recordIds};

    switch (entry.type) {
      case _JournalEventType.grant:
        final request = ScenarioQualityDecisionGrantRequest.fromJson(
          entry.payload['request'],
        );
        final grant = ScenarioQualityDecisionGrant.fromJson(
          entry.payload['grant'],
        );
        final reviewDescriptor = ScenarioQualityReviewDescriptor.fromJson(
          entry.payload['reviewDescriptor'],
        );
        if (requestById.containsKey(request.requestId.value) ||
            grants.containsKey(grant.id.value) ||
            grant.requestId != request.requestId ||
            grant.requestDigest != request.digest ||
            grant.runId != request.runId ||
            grant.runResultDigest != request.expectedRunResultDigest ||
            grant.qualityDigest != request.expectedQualityDigest ||
            grant.reviewDescriptorDigest !=
                request.expectedReviewDescriptorDigest ||
            grant.expectedPreviousDecisionDigest !=
                request.expectedPreviousDecisionDigest ||
            grant.decision != request.decision ||
            reviewDescriptor.digest != grant.reviewDescriptorDigest ||
            reviewDescriptor.runId != grant.runId ||
            reviewDescriptor.runResultDigest != grant.runResultDigest ||
            reviewDescriptor.qualityDigest != grant.qualityDigest ||
            reviewDescriptor.requirementId != grant.requirementId ||
            reviewDescriptor.requirementScope != grant.requirementScope ||
            reviewDescriptor.reviewGuideId != grant.reviewGuideId ||
            reviewDescriptor.reviewGuideStepId != grant.reviewGuideStepId) {
          throw const FormatException('Stored grant binding is invalid');
        }
        nextGrants[grant.id.value] = _StoredGrant(
          grant: grant,
          reviewDescriptor: reviewDescriptor,
        );
        nextRequests[request.requestId.value] = _StoredRequest(
          requestDigest: request.digest,
          grant: grant,
        );
      case _JournalEventType.revoke:
        final id = entry.payload['grantId'];
        final revokedAt = entry.payload['revokedAt'];
        if (id is! String ||
            revokedAt is! String ||
            DateTime.tryParse(revokedAt) == null ||
            !revokedAt.endsWith('Z')) {
          throw const FormatException('Stored grant revocation is invalid');
        }
        final stored = nextGrants[id];
        if (stored == null ||
            stored.revoked ||
            stored.expired ||
            stored.consumed) {
          throw const FormatException(
            'Stored grant revocation is inconsistent',
          );
        }
        nextGrants[id] = stored.copyWith(revoked: true);
      case _JournalEventType.expire:
        final id = entry.payload['grantId'];
        final expiredAt = entry.payload['expiredAt'];
        final stored = id is String ? nextGrants[id] : null;
        if (stored == null ||
            stored.revoked ||
            stored.expired ||
            stored.consumed ||
            expiredAt != stored.grant.expiresAt.toIso8601String()) {
          throw const FormatException('Stored grant expiry is inconsistent');
        }
        nextGrants[id as String] = stored.copyWith(expired: true);
      case _JournalEventType.append:
        final request = ScenarioQualityDecisionAppendRequest.fromJson(
          entry.payload['request'],
        );
        final result = ScenarioQualityDecisionAppendResult.fromJson(
          entry.payload['result'],
        );
        final id = entry.payload['grantId'];
        _validateConsumedAt(entry.payload['consumedAt']);
        final stored = id is String ? nextGrants[id] : null;
        if (stored == null ||
            stored.revoked ||
            stored.expired ||
            stored.consumed ||
            requestById.containsKey(request.requestId.value) ||
            !_requestMatchesStoredGrant(request, stored.grant) ||
            result.requestId != request.requestId ||
            result.requestDigest != request.digest ||
            result.attribution.requirementId != stored.grant.requirementId ||
            result.attribution.runId != stored.grant.runId ||
            result.attribution.runResultDigest !=
                stored.grant.runResultDigest ||
            result.attribution.reviewDescriptorDigest !=
                stored.grant.reviewDescriptorDigest ||
            result.attribution.requirementScope !=
                stored.grant.requirementScope ||
            result.attribution.reviewGuideId != stored.grant.reviewGuideId ||
            result.attribution.reviewGuideStepId !=
                stored.grant.reviewGuideStepId ||
            result.attribution.authorityId != stored.grant.authorityId ||
            result.attribution.accessPolicyId != stored.grant.accessPolicyId ||
            result.attribution.principalId != stored.grant.principalId ||
            result.attribution.role != stored.grant.role ||
            result.attribution.grantDigest != stored.grant.digest ||
            result.attribution.grantRequestDigest !=
                stored.grant.requestDigest ||
            result.attribution.decisionRequestDigest != request.digest ||
            result.record.subjectDigest != stored.grant.runResultDigest ||
            result.record.principalId != stored.grant.principalId ||
            result.record.decision != stored.grant.decision ||
            result.record.supersedesDecisionDigest !=
                stored.grant.expectedPreviousDecisionDigest ||
            request.expectedReviewDescriptorDigest !=
                stored.grant.reviewDescriptorDigest ||
            nextRecordIds.contains(result.record.id.value)) {
          throw const FormatException('Stored decision append is invalid');
        }
        final grantId = id as String;
        final subject = result.record.subjectDigest.value;
        final records = nextRecords.putIfAbsent(
          subject,
          () => <HumanDecisionRecord>[],
        );
        if (records.lastOrNull case final previous?) {
          result.record.validateSupersedes(previous);
        } else if (result.record.supersedesDecisionDigest != null) {
          throw const FormatException('Initial decision cannot supersede');
        }
        records.add(result.record);
        nextRecordIds.add(result.record.id.value);
        nextQuality[subject] = result.quality;
        nextAttributions[result.record.digest.value] = result.attribution;
        nextReviewDescriptors[result.record.digest.value] =
            stored.reviewDescriptor;
        nextGrants[grantId] = stored.copyWith(consumed: true);
        nextRequests[request.requestId.value] = _StoredRequest(
          requestDigest: request.digest,
          appendResult: result,
        );
      case _JournalEventType.consume:
        final request = ScenarioQualityDecisionAppendRequest.fromJson(
          entry.payload['request'],
        );
        final error = ScenarioQualityDecisionError.fromJson(
          entry.payload['error'],
        );
        final id = entry.payload['grantId'];
        _validateConsumedAt(entry.payload['consumedAt']);
        final stored = id is String ? nextGrants[id] : null;
        final exactBinding =
            stored != null && _requestMatchesStoredGrant(request, stored.grant);
        final mismatchConsumption =
            stored != null &&
            error.code == ScenarioQualityDecisionErrorCode.grantMismatch &&
            _requestIdentifiesStoredGrant(request, stored.grant) &&
            !exactBinding;
        if (stored == null ||
            stored.revoked ||
            stored.expired ||
            stored.consumed ||
            requestById.containsKey(request.requestId.value) ||
            (!exactBinding && !mismatchConsumption) ||
            error.operation != ScenarioQualityDecisionOperation.append ||
            error.requestId != request.requestId ||
            error.runId != request.runId ||
            error.expectedRunResultDigest != request.expectedRunResultDigest) {
          throw const FormatException('Stored grant consumption is invalid');
        }
        final grantId = id as String;
        nextGrants[grantId] = stored.copyWith(consumed: true);
        nextRequests[request.requestId.value] = _StoredRequest(
          requestDigest: request.digest,
          appendError: error,
        );
    }
    return _JournalState(
      entries: List<_JournalEntry>.unmodifiable(nextEntries),
      grants: Map<String, _StoredGrant>.unmodifiable(nextGrants),
      requestById: Map<String, _StoredRequest>.unmodifiable(nextRequests),
      recordsBySubject: Map<String, List<HumanDecisionRecord>>.unmodifiable(
        <String, List<HumanDecisionRecord>>{
          for (final item in nextRecords.entries)
            item.key: List<HumanDecisionRecord>.unmodifiable(item.value),
        },
      ),
      qualityBySubject: Map<String, ScenarioQualitySnapshot>.unmodifiable(
        nextQuality,
      ),
      attributionByRecordDigest:
          Map<String, ScenarioQualityDecisionAttribution>.unmodifiable(
            nextAttributions,
          ),
      reviewDescriptorByRecordDigest:
          Map<String, ScenarioQualityReviewDescriptor>.unmodifiable(
            nextReviewDescriptors,
          ),
      recordIds: Set<String>.unmodifiable(nextRecordIds),
    );
  }
}

final class _StoredGrant {
  const _StoredGrant({
    required this.grant,
    required this.reviewDescriptor,
    this.revoked = false,
    this.expired = false,
    this.consumed = false,
  });

  final ScenarioQualityDecisionGrant grant;
  final ScenarioQualityReviewDescriptor reviewDescriptor;
  final bool revoked;
  final bool expired;
  final bool consumed;

  _StoredGrant copyWith({bool? revoked, bool? expired, bool? consumed}) =>
      _StoredGrant(
        grant: grant,
        reviewDescriptor: reviewDescriptor,
        revoked: revoked ?? this.revoked,
        expired: expired ?? this.expired,
        consumed: consumed ?? this.consumed,
      );
}

final class _StoredRequest {
  const _StoredRequest({
    required this.requestDigest,
    this.grant,
    this.appendResult,
    this.appendError,
  });

  final Digest requestDigest;
  final ScenarioQualityDecisionGrant? grant;
  final ScenarioQualityDecisionAppendResult? appendResult;
  final ScenarioQualityDecisionError? appendError;
}

void _validateConsumedAt(Object? value) {
  if (value is! String ||
      DateTime.tryParse(value) == null ||
      !value.endsWith('Z')) {
    throw const FormatException('Stored grant consumption time is invalid');
  }
}

bool _requestMatchesStoredGrant(
  ScenarioQualityDecisionAppendRequest request,
  ScenarioQualityDecisionGrant grant,
) =>
    request.grantId == grant.id &&
    request.grantDigest == grant.digest &&
    request.runId == grant.runId &&
    request.expectedRunResultDigest == grant.runResultDigest &&
    request.expectedQualityDigest == grant.qualityDigest &&
    request.expectedReviewDescriptorDigest == grant.reviewDescriptorDigest &&
    request.expectedPreviousDecisionDigest ==
        grant.expectedPreviousDecisionDigest &&
    request.decision == grant.decision;

bool _requestIdentifiesStoredGrant(
  ScenarioQualityDecisionAppendRequest request,
  ScenarioQualityDecisionGrant grant,
) => request.grantId == grant.id && request.grantDigest == grant.digest;
