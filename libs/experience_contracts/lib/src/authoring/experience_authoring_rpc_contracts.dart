part of 'experience_authoring_contracts.dart';

/// Closed JSON-RPC method surface for Experience Authoring v1.
abstract final class ExperienceAuthoringRpcMethod {
  static const String describe = 'experience.authoring.describe';
  static const String getSubjectHead = 'experience.authoring.getSubjectHead';
  static const String openDraft = 'experience.authoring.openDraft';
  static const String getDraft = 'experience.authoring.getDraft';
  static const String requestGrant = 'experience.authoring.requestGrant';
  static const String mutateDraft = 'experience.authoring.mutateDraft';
  static const String prepareReview = 'experience.authoring.prepareReview';
  static const String getChangeSet = 'experience.authoring.getChangeSet';
  static const String getReview = 'experience.authoring.getReview';
  static const String reviewAction = 'experience.authoring.reviewAction';
  static const String requestDecisionGrant =
      'experience.authoring.requestDecisionGrant';
  static const String abandonDraft = 'experience.authoring.abandonDraft';
  static const String requestPromotionGrant =
      'experience.authoring.requestPromotionGrant';
  static const String applyPromotion = 'experience.authoring.applyPromotion';
  static const String getPromotion = 'experience.authoring.getPromotion';
  static const String getPromotionHistory =
      'experience.authoring.getPromotionHistory';

  static const Set<String> values = <String>{
    describe,
    getSubjectHead,
    openDraft,
    getDraft,
    requestGrant,
    mutateDraft,
    prepareReview,
    getChangeSet,
    getReview,
    reviewAction,
    requestDecisionGrant,
    abandonDraft,
    requestPromotionGrant,
    applyPromotion,
    getPromotion,
    getPromotionHistory,
  };
}

enum LayoutDraftMutation { applyMove, undo, redo, reset }

enum ExperienceAuthoringAvailability { available, policyDenied, unsupported }

enum ExperienceAuthoringErrorCode {
  stale,
  policyDenied,
  ownerDenied,
  capabilityUnavailable,
  grantExpired,
  grantRevoked,
  grantConsumed,
  grantMismatch,
  requestConflict,
  unsupported,
  quotaExceeded,
  unavailable,
  invalidRequest,
}

final class ExperienceAuthoringDescribeRequest {
  ExperienceAuthoringDescribeRequest({
    required this.requestId,
    required this.subject,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceAuthoringDescribeRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringDescribeRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceAuthoringDescribeRequest',
      const <String>{'requestId', 'subject'},
    );
    final result = ExperienceAuthoringDescribeRequest(
      requestId: AuthoringRequestId(
        _authoringString(
          json,
          'requestId',
          'ExperienceAuthoringDescribeRequest',
        ),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceAuthoringDescribeRequest',
    );
    return result;
  }
}

final class ExperienceAuthoringDescription {
  ExperienceAuthoringDescription({
    required this.requestId,
    required this.subject,
    required this.availability,
    required this.capability,
    required Set<AuthoringActionEffect> allowedEffects,
    required Set<AuthoringOperation> allowedOperations,
    required this.currentContentSetDigest,
    required this.currentSourceDigest,
    required this.currentTopologyDigest,
    required this.currentLayoutDigest,
    this.maxFrameBytes = experienceAuthoringMaxFrameBytes,
  }) : allowedEffects = Set<AuthoringActionEffect>.unmodifiable(allowedEffects),
       allowedOperations = Set<AuthoringOperation>.unmodifiable(
         allowedOperations,
       ) {
    if (maxFrameBytes <= 0 ||
        maxFrameBytes > experienceAuthoringMaxFrameBytes) {
      throw ArgumentError('Invalid authoring frame budget');
    }
    if ((availability == ExperienceAuthoringAvailability.unsupported) !=
        (currentSourceDigest == null)) {
      throw ArgumentError(
        'Only unsupported source-less descriptions omit source identity',
      );
    }
    final impliedEffects = this.allowedOperations
        .map(authoringEffectFor)
        .toSet();
    final unsupported =
        availability == ExperienceAuthoringAvailability.unsupported;
    final policyDenied =
        availability == ExperienceAuthoringAvailability.policyDenied;
    if (unsupported != (capability == null) ||
        (unsupported &&
            (this.allowedEffects.isNotEmpty ||
                this.allowedOperations.isNotEmpty)) ||
        (!unsupported && this.allowedOperations.isEmpty) ||
        (availability == ExperienceAuthoringAvailability.available &&
            (!this.allowedEffects.any(
                  (effect) => effect != AuthoringActionEffect.query,
                ) ||
                !this.allowedOperations.any(
                  (operation) =>
                      authoringEffectFor(operation) !=
                      AuthoringActionEffect.query,
                ))) ||
        (policyDenied &&
            (this.allowedEffects.length != 1 ||
                !this.allowedEffects.contains(AuthoringActionEffect.query) ||
                this.allowedOperations.any(
                  (operation) =>
                      authoringEffectFor(operation) !=
                      AuthoringActionEffect.query,
                ))) ||
        (capability != null &&
            (!capability!.effects.containsAll(this.allowedEffects) ||
                !capability!.operations.containsAll(this.allowedOperations) ||
                capability!.subject != subject)) ||
        !this.allowedEffects.containsAll(impliedEffects) ||
        !impliedEffects.containsAll(this.allowedEffects)) {
      throw ArgumentError('Authoring availability projection is inconsistent');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final ExperienceAuthoringAvailability availability;
  final AuthoringCapability? capability;
  final Set<AuthoringActionEffect> allowedEffects;
  final Set<AuthoringOperation> allowedOperations;
  final Digest currentContentSetDigest;
  final Digest? currentSourceDigest;
  final Digest currentTopologyDigest;
  final Digest currentLayoutDigest;
  final int maxFrameBytes;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceAuthoringDescription',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'availability': availability.name,
    if (capability != null) 'capability': capability!.toJson(),
    'allowedEffects': allowedEffects.map((value) => value.name).toList()
      ..sort(),
    'allowedOperations': allowedOperations.map((value) => value.name).toList()
      ..sort(),
    'currentContentSetDigest': currentContentSetDigest.value,
    if (currentSourceDigest != null)
      'currentSourceDigest': currentSourceDigest!.value,
    'currentTopologyDigest': currentTopologyDigest.value,
    'currentLayoutDigest': currentLayoutDigest.value,
    'maxFrameBytes': maxFrameBytes,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringDescription.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceAuthoringDescription',
      const <String>{
        'requestId',
        'subject',
        'availability',
        'capability',
        'allowedEffects',
        'allowedOperations',
        'currentContentSetDigest',
        'currentSourceDigest',
        'currentTopologyDigest',
        'currentLayoutDigest',
        'maxFrameBytes',
      },
    );
    final result = ExperienceAuthoringDescription(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceAuthoringDescription'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      availability: _authoringEnum(
        ExperienceAuthoringAvailability.values,
        _authoringString(
          json,
          'availability',
          'ExperienceAuthoringDescription',
        ),
        'ExperienceAuthoringDescription.availability',
      ),
      capability: json.containsKey('capability')
          ? AuthoringCapability.fromJson(json['capability'])
          : null,
      allowedEffects: _authoringOptionalEnumSet(
        AuthoringActionEffect.values,
        json['allowedEffects'],
        'ExperienceAuthoringDescription.allowedEffects',
      ),
      allowedOperations: _authoringOptionalEnumSet(
        AuthoringOperation.values,
        json['allowedOperations'],
        'ExperienceAuthoringDescription.allowedOperations',
      ),
      currentContentSetDigest: _authoringDigest(
        json,
        'currentContentSetDigest',
        'ExperienceAuthoringDescription',
      ),
      currentSourceDigest: _authoringOptionalDigest(
        json,
        'currentSourceDigest',
        'ExperienceAuthoringDescription',
      ),
      currentTopologyDigest: _authoringDigest(
        json,
        'currentTopologyDigest',
        'ExperienceAuthoringDescription',
      ),
      currentLayoutDigest: _authoringDigest(
        json,
        'currentLayoutDigest',
        'ExperienceAuthoringDescription',
      ),
      maxFrameBytes: _authoringInt(
        json,
        'maxFrameBytes',
        'ExperienceAuthoringDescription',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceAuthoringDescription',
    );
    return result;
  }

  void validateAgainst(ExperienceAuthoringDescribeRequest request) {
    if (requestId != request.requestId || subject != request.subject) {
      throw StateError('Authoring description does not match its request');
    }
  }
}

final class LayoutDraftOpenRequest {
  LayoutDraftOpenRequest({
    required this.requestId,
    required this.subject,
    required this.expectedContentSetDigest,
    required this.expectedSourceDigest,
    required this.grantId,
    required this.grantDigest,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final Digest expectedContentSetDigest;
  final Digest expectedSourceDigest;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
  });

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftOpenRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftOpenRequest.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'LayoutDraftOpenRequest', const <String>{
          'requestId',
          'subject',
          'expectedContentSetDigest',
          'expectedSourceDigest',
          'grantId',
          'grantDigest',
          'payloadDigest',
        });
    final result = LayoutDraftOpenRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftOpenRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'LayoutDraftOpenRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'LayoutDraftOpenRequest',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'LayoutDraftOpenRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'LayoutDraftOpenRequest',
      ),
    );
    if (_authoringDigest(json, 'payloadDigest', 'LayoutDraftOpenRequest') !=
        result.payloadDigest) {
      throw const FormatException('LayoutDraftOpenRequest payload mismatch');
    }
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftOpenRequest');
    return result;
  }

  void validateAgainstGrantIntent(AuthoringGrantIntent intent) {
    if (subject != intent.subject ||
        intent.effect != AuthoringActionEffect.authoring ||
        intent.operation != AuthoringOperation.openDraft ||
        intent.expectedDigest != expectedContentSetDigest ||
        intent.expectedSourceDigest != expectedSourceDigest ||
        intent.payloadDigest != payloadDigest) {
      throw StateError('Draft open request differs from its grant intent');
    }
  }
}

final class LayoutDraftOpenResult {
  LayoutDraftOpenResult({
    required this.requestId,
    required this.draft,
    required this.resumed,
    required this.head,
  }) {
    if (head.subject != draft.subject ||
        head.draft?.id != draft.id ||
        head.draft?.digest != draft.digest ||
        head.draft?.revision != draft.revision) {
      throw ArgumentError('Open result head must expose the returned draft');
    }
    if (!resumed &&
        (draft.revision != 0 || draft.previousDraftDigest != null)) {
      throw ArgumentError('A newly opened draft must start at revision zero');
    }
    if (!resumed && (head.changeSet != null || head.review != null)) {
      throw ArgumentError(
        'A newly opened draft cannot expose prior review heads',
      );
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final LayoutDraft draft;
  final bool resumed;
  final ExperienceAuthoringSubjectHead head;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftOpenResult',
    'requestId': requestId.value,
    'draft': draft.toJson(),
    'resumed': resumed,
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftOpenResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'LayoutDraftOpenResult',
      const <String>{'requestId', 'draft', 'resumed', 'head'},
    );
    final result = LayoutDraftOpenResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftOpenResult'),
      ),
      draft: LayoutDraft.fromJson(json['draft']),
      resumed: _authoringBool(json, 'resumed', 'LayoutDraftOpenResult'),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftOpenResult');
    return result;
  }

  void validateAgainst(LayoutDraftOpenRequest request) {
    if (requestId != request.requestId ||
        draft.subject != request.subject ||
        draft.contentSetDigest != request.expectedContentSetDigest ||
        draft.baseSourceDigest != request.expectedSourceDigest) {
      throw StateError('Layout draft open result does not match its request');
    }
  }
}

final class LayoutDraftGetRequest {
  LayoutDraftGetRequest({
    required this.requestId,
    required this.subject,
    required this.draftId,
    this.expectedDraftDigest,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest? expectedDraftDigest;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftGetRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    if (expectedDraftDigest != null)
      'expectedDraftDigest': expectedDraftDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftGetRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'LayoutDraftGetRequest',
      const <String>{'requestId', 'subject', 'draftId', 'expectedDraftDigest'},
    );
    final result = LayoutDraftGetRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftGetRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'LayoutDraftGetRequest'),
      ),
      expectedDraftDigest: _authoringOptionalDigest(
        json,
        'expectedDraftDigest',
        'LayoutDraftGetRequest',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftGetRequest');
    return result;
  }
}

final class LayoutDraftGetResult {
  LayoutDraftGetResult({
    required this.requestId,
    required this.draft,
    required this.head,
  }) {
    if (head.subject != draft.subject ||
        head.draft?.id != draft.id ||
        head.draft?.digest != draft.digest ||
        head.draft?.revision != draft.revision) {
      throw ArgumentError('Get result head must expose the returned draft');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final LayoutDraft draft;
  final ExperienceAuthoringSubjectHead head;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftGetResult',
    'requestId': requestId.value,
    'draft': draft.toJson(),
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftGetResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'LayoutDraftGetResult',
      const <String>{'requestId', 'draft', 'head'},
    );
    final result = LayoutDraftGetResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftGetResult'),
      ),
      draft: LayoutDraft.fromJson(json['draft']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftGetResult');
    return result;
  }

  void validateAgainst(LayoutDraftGetRequest request) {
    if (requestId != request.requestId ||
        draft.id != request.draftId ||
        draft.subject != request.subject ||
        (request.expectedDraftDigest != null &&
            draft.digest != request.expectedDraftDigest)) {
      throw StateError('Layout draft get result does not match its request');
    }
  }
}

final class AuthoringGrantRequest implements AuthoringGrantIntent {
  AuthoringGrantRequest({
    required this.requestId,
    required this.capabilityDigest,
    required this.subject,
    required this.effect,
    required this.operation,
    required this.expectedDigest,
    required this.expectedSourceDigest,
    required this.payloadDigest,
  }) {
    if (effect == AuthoringActionEffect.query ||
        operation == AuthoringOperation.decideReview ||
        operation == AuthoringOperation.promote ||
        effect != authoringEffectFor(operation)) {
      throw ArgumentError(
        'Generic grant request cannot bypass a specialized grant intent',
      );
    }
  }

  static const int schemaVersion = 1;
  @override
  final AuthoringRequestId requestId;
  @override
  final Digest capabilityDigest;
  @override
  final AuthoringSubjectRef subject;
  @override
  final AuthoringActionEffect effect;
  @override
  final AuthoringOperation operation;
  @override
  final Digest expectedDigest;
  @override
  final Digest expectedSourceDigest;
  @override
  final Digest payloadDigest;

  @override
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AuthoringGrantRequest',
    'requestId': requestId.value,
    'capabilityDigest': capabilityDigest.value,
    'subject': subject.toJson(),
    'effect': effect.name,
    'operation': operation.name,
    'expectedDigest': expectedDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory AuthoringGrantRequest.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'AuthoringGrantRequest', const <String>{
          'requestId',
          'capabilityDigest',
          'subject',
          'effect',
          'operation',
          'expectedDigest',
          'expectedSourceDigest',
          'payloadDigest',
        });
    final result = AuthoringGrantRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'AuthoringGrantRequest'),
      ),
      capabilityDigest: _authoringDigest(
        json,
        'capabilityDigest',
        'AuthoringGrantRequest',
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      effect: _authoringEnum(
        AuthoringActionEffect.values,
        _authoringString(json, 'effect', 'AuthoringGrantRequest'),
        'AuthoringGrantRequest.effect',
      ),
      operation: _authoringEnum(
        AuthoringOperation.values,
        _authoringString(json, 'operation', 'AuthoringGrantRequest'),
        'AuthoringGrantRequest.operation',
      ),
      expectedDigest: _authoringDigest(
        json,
        'expectedDigest',
        'AuthoringGrantRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'AuthoringGrantRequest',
      ),
      payloadDigest: _authoringDigest(
        json,
        'payloadDigest',
        'AuthoringGrantRequest',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'AuthoringGrantRequest');
    return result;
  }
}

final class AuthoringGrantResult {
  AuthoringGrantResult({required this.requestId, required this.grant});

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringActionGrant grant;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AuthoringGrantResult',
    'requestId': requestId.value,
    'grant': grant.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory AuthoringGrantResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'AuthoringGrantResult',
      const <String>{'requestId', 'grant'},
    );
    final result = AuthoringGrantResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'AuthoringGrantResult'),
      ),
      grant: AuthoringActionGrant.fromJson(json['grant']),
    );
    _authoringVerifyDigest(json, result.digest, 'AuthoringGrantResult');
    return result;
  }

  void validateAgainst(AuthoringGrantIntent request) {
    if (requestId != request.requestId ||
        grant.requestId != request.requestId ||
        grant.requestDigest != request.digest ||
        grant.capabilityDigest != request.capabilityDigest ||
        grant.subject != request.subject ||
        grant.effect != request.effect ||
        grant.operation != request.operation ||
        grant.expectedDigest != request.expectedDigest ||
        grant.expectedSourceDigest != request.expectedSourceDigest ||
        grant.payloadDigest != request.payloadDigest) {
      throw StateError('Authoring grant result does not match its intent');
    }
  }
}

final class LayoutDraftMutationRequest {
  LayoutDraftMutationRequest({
    required this.requestId,
    required this.draftId,
    required this.expectedDraftDigest,
    required this.expectedDraftRevision,
    required this.grantId,
    required this.grantDigest,
    required this.mutation,
    this.move,
  }) {
    if ((mutation == LayoutDraftMutation.applyMove) != (move != null)) {
      throw ArgumentError('Only applyMove accepts a move payload');
    }
    if (expectedDraftRevision < 0 ||
        expectedDraftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Expected draft revision must be a safe integer');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final LayoutDraftId draftId;
  final Digest expectedDraftDigest;
  final int expectedDraftRevision;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;
  final LayoutDraftMutation mutation;
  final LayoutMoveNodeInput? move;

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'mutation': mutation.name,
    if (move != null) 'move': move!.toJson(),
  });
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftMutationRequest',
    'requestId': requestId.value,
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'mutation': mutation.name,
    if (move != null) 'move': move!.toJson(),
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftMutationRequest.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'LayoutDraftMutationRequest', const <String>{
          'requestId',
          'draftId',
          'expectedDraftDigest',
          'expectedDraftRevision',
          'grantId',
          'grantDigest',
          'mutation',
          'move',
          'payloadDigest',
        });
    final result = LayoutDraftMutationRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftMutationRequest'),
      ),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'LayoutDraftMutationRequest'),
      ),
      expectedDraftDigest: _authoringDigest(
        json,
        'expectedDraftDigest',
        'LayoutDraftMutationRequest',
      ),
      expectedDraftRevision: _authoringInt(
        json,
        'expectedDraftRevision',
        'LayoutDraftMutationRequest',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'LayoutDraftMutationRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'LayoutDraftMutationRequest',
      ),
      mutation: _authoringEnum(
        LayoutDraftMutation.values,
        _authoringString(json, 'mutation', 'LayoutDraftMutationRequest'),
        'LayoutDraftMutationRequest.mutation',
      ),
      move: json.containsKey('move')
          ? LayoutMoveNodeInput.fromJson(json['move'])
          : null,
    );
    if (_authoringDigest(json, 'payloadDigest', 'LayoutDraftMutationRequest') !=
        result.payloadDigest) {
      throw const FormatException(
        'LayoutDraftMutationRequest payload mismatch',
      );
    }
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftMutationRequest');
    return result;
  }

  void validateAgainstGrantIntent(
    AuthoringGrantIntent intent, {
    required LayoutDraft draft,
  }) {
    final expectedOperation = switch (mutation) {
      LayoutDraftMutation.applyMove => AuthoringOperation.moveNode,
      LayoutDraftMutation.undo => AuthoringOperation.undo,
      LayoutDraftMutation.redo => AuthoringOperation.redo,
      LayoutDraftMutation.reset => AuthoringOperation.reset,
    };
    if (draft.id != draftId ||
        draft.digest != expectedDraftDigest ||
        draft.revision != expectedDraftRevision ||
        intent.subject != draft.subject ||
        intent.effect != AuthoringActionEffect.authoring ||
        intent.operation != expectedOperation ||
        intent.expectedDigest != expectedDraftDigest ||
        intent.expectedSourceDigest != draft.baseSourceDigest ||
        intent.payloadDigest != payloadDigest) {
      throw StateError('Draft mutation differs from its grant intent');
    }
  }
}

final class LayoutDraftMutationResult {
  LayoutDraftMutationResult({
    required this.requestId,
    required this.draft,
    required this.head,
  }) {
    if (head.subject != draft.subject ||
        head.draft?.id != draft.id ||
        head.draft?.digest != draft.digest ||
        head.draft?.revision != draft.revision ||
        head.changeSet != null ||
        head.review != null) {
      throw ArgumentError('Draft mutation must invalidate prior review heads');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final LayoutDraft draft;
  final ExperienceAuthoringSubjectHead head;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftMutationResult',
    'requestId': requestId.value,
    'draft': draft.toJson(),
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftMutationResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'LayoutDraftMutationResult',
      const <String>{'requestId', 'draft', 'head'},
    );
    final result = LayoutDraftMutationResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftMutationResult'),
      ),
      draft: LayoutDraft.fromJson(json['draft']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftMutationResult');
    return result;
  }

  void validateAgainst(
    LayoutDraftMutationRequest request, {
    required LayoutDraft previousDraft,
  }) {
    if (requestId != request.requestId ||
        previousDraft.id != request.draftId ||
        previousDraft.digest != request.expectedDraftDigest ||
        previousDraft.revision != request.expectedDraftRevision ||
        draft.id != previousDraft.id ||
        draft.subject != previousDraft.subject ||
        draft.baseLayoutDigest != previousDraft.baseLayoutDigest ||
        draft.baseSourceDigest != previousDraft.baseSourceDigest ||
        draft.contentSetDigest != previousDraft.contentSetDigest ||
        draft.topologyDigest != previousDraft.topologyDigest ||
        draft.revision != previousDraft.revision + 1 ||
        draft.previousDraftDigest != previousDraft.digest) {
      throw StateError('Layout mutation result breaks its draft head fence');
    }
    switch (request.mutation) {
      case LayoutDraftMutation.applyMove:
        if (draft.cursor != previousDraft.cursor + 1 ||
            draft.history.length != previousDraft.cursor + 1 ||
            !_sameOperationPrefix(
              draft.history,
              previousDraft.history,
              previousDraft.cursor,
            ) ||
            draft.history.last.nodeInstanceId != request.move!.nodeInstanceId ||
            draft.history.last.toX != request.move!.toX ||
            draft.history.last.toY != request.move!.toY) {
          throw StateError('Move result does not match its typed payload');
        }
      case LayoutDraftMutation.undo:
        if (previousDraft.cursor == 0 ||
            draft.cursor != previousDraft.cursor - 1 ||
            !_sameOperationHistory(draft.history, previousDraft.history)) {
          throw StateError('Undo result is not the next draft revision');
        }
      case LayoutDraftMutation.redo:
        if (previousDraft.cursor >= previousDraft.history.length ||
            draft.cursor != previousDraft.cursor + 1 ||
            !_sameOperationHistory(draft.history, previousDraft.history)) {
          throw StateError('Redo result is not the next draft revision');
        }
      case LayoutDraftMutation.reset:
        if (previousDraft.history.isEmpty ||
            draft.cursor != 0 ||
            draft.history.isNotEmpty ||
            draft.candidateLayoutDigest != draft.baseLayoutDigest) {
          throw StateError('Reset result did not clear the draft');
        }
    }
  }
}

bool _sameOperationPrefix(
  List<LayoutMoveNodeOperation> left,
  List<LayoutMoveNodeOperation> right,
  int length,
) {
  if (left.length < length || right.length < length) return false;
  for (var index = 0; index < length; index += 1) {
    if (left[index].digest != right[index].digest) return false;
  }
  return true;
}

bool _sameOperationHistory(
  List<LayoutMoveNodeOperation> left,
  List<LayoutMoveNodeOperation> right,
) =>
    left.length == right.length &&
    _sameOperationPrefix(left, right, left.length);

final class ExperienceAuthoringError {
  ExperienceAuthoringError({
    required this.code,
    required this.requestId,
    required this.subject,
    this.operation,
    this.mutation,
    this.draftId,
    this.changeSetId,
    this.reviewPacketId,
    this.expectedDigest,
    this.currentDraftDigest,
    this.currentChangeSetDigest,
    this.currentContentSetDigest,
    this.currentSourceDigest,
    this.currentReviewPacketDigest,
  }) {
    if (code == ExperienceAuthoringErrorCode.stale && expectedDigest == null) {
      throw ArgumentError('Stale errors require their expected digest');
    }
    if (code == ExperienceAuthoringErrorCode.stale &&
        currentDraftDigest == null &&
        currentChangeSetDigest == null &&
        currentContentSetDigest == null &&
        currentSourceDigest == null &&
        currentReviewPacketDigest == null) {
      throw ArgumentError('Stale errors must disclose a current digest fence');
    }
  }

  static const int schemaVersion = 1;
  static const int jsonRpcCode = -32130;
  final ExperienceAuthoringErrorCode code;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final AuthoringOperation? operation;
  final LayoutDraftMutation? mutation;
  final LayoutDraftId? draftId;
  final ExperienceChangeSetId? changeSetId;
  final ExperienceReviewPacketId? reviewPacketId;
  final Digest? expectedDigest;
  final Digest? currentDraftDigest;
  final Digest? currentChangeSetDigest;
  final Digest? currentContentSetDigest;
  final Digest? currentSourceDigest;
  final Digest? currentReviewPacketDigest;

  bool get retryable => switch (code) {
    ExperienceAuthoringErrorCode.stale ||
    ExperienceAuthoringErrorCode.grantExpired ||
    ExperienceAuthoringErrorCode.grantRevoked ||
    ExperienceAuthoringErrorCode.grantConsumed ||
    ExperienceAuthoringErrorCode.unavailable => true,
    _ => false,
  };

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceAuthoringError',
    'code': code.name,
    'requestId': requestId.value,
    'subject': subject.toJson(),
    if (operation != null) 'operation': operation!.name,
    if (mutation != null) 'mutation': mutation!.name,
    if (draftId != null) 'draftId': draftId!.value,
    if (changeSetId != null) 'changeSetId': changeSetId!.value,
    if (reviewPacketId != null) 'reviewPacketId': reviewPacketId!.value,
    if (expectedDigest != null) 'expectedDigest': expectedDigest!.value,
    if (currentDraftDigest != null)
      'currentDraftDigest': currentDraftDigest!.value,
    if (currentChangeSetDigest != null)
      'currentChangeSetDigest': currentChangeSetDigest!.value,
    if (currentContentSetDigest != null)
      'currentContentSetDigest': currentContentSetDigest!.value,
    if (currentSourceDigest != null)
      'currentSourceDigest': currentSourceDigest!.value,
    if (currentReviewPacketDigest != null)
      'currentReviewPacketDigest': currentReviewPacketDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringError.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'ExperienceAuthoringError', const <String>{
          'code',
          'requestId',
          'subject',
          'operation',
          'mutation',
          'draftId',
          'changeSetId',
          'reviewPacketId',
          'expectedDigest',
          'currentDraftDigest',
          'currentChangeSetDigest',
          'currentContentSetDigest',
          'currentSourceDigest',
          'currentReviewPacketDigest',
        });
    final result = ExperienceAuthoringError(
      code: _authoringEnum(
        ExperienceAuthoringErrorCode.values,
        _authoringString(json, 'code', 'ExperienceAuthoringError'),
        'ExperienceAuthoringError.code',
      ),
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceAuthoringError'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      operation: json.containsKey('operation')
          ? _authoringEnum(
              AuthoringOperation.values,
              _authoringString(json, 'operation', 'ExperienceAuthoringError'),
              'ExperienceAuthoringError.operation',
            )
          : null,
      mutation: json.containsKey('mutation')
          ? _authoringEnum(
              LayoutDraftMutation.values,
              _authoringString(json, 'mutation', 'ExperienceAuthoringError'),
              'ExperienceAuthoringError.mutation',
            )
          : null,
      draftId: json.containsKey('draftId')
          ? LayoutDraftId(
              _authoringString(json, 'draftId', 'ExperienceAuthoringError'),
            )
          : null,
      changeSetId: json.containsKey('changeSetId')
          ? ExperienceChangeSetId(
              _authoringString(json, 'changeSetId', 'ExperienceAuthoringError'),
            )
          : null,
      reviewPacketId: json.containsKey('reviewPacketId')
          ? ExperienceReviewPacketId(
              _authoringString(
                json,
                'reviewPacketId',
                'ExperienceAuthoringError',
              ),
            )
          : null,
      expectedDigest: _authoringOptionalDigest(
        json,
        'expectedDigest',
        'ExperienceAuthoringError',
      ),
      currentDraftDigest: _authoringOptionalDigest(
        json,
        'currentDraftDigest',
        'ExperienceAuthoringError',
      ),
      currentChangeSetDigest: _authoringOptionalDigest(
        json,
        'currentChangeSetDigest',
        'ExperienceAuthoringError',
      ),
      currentContentSetDigest: _authoringOptionalDigest(
        json,
        'currentContentSetDigest',
        'ExperienceAuthoringError',
      ),
      currentSourceDigest: _authoringOptionalDigest(
        json,
        'currentSourceDigest',
        'ExperienceAuthoringError',
      ),
      currentReviewPacketDigest: _authoringOptionalDigest(
        json,
        'currentReviewPacketDigest',
        'ExperienceAuthoringError',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceAuthoringError');
    return result;
  }
}
