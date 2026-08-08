part of 'experience_authoring_contracts.dart';

final class ExperienceReviewPrepareRequest {
  ExperienceReviewPrepareRequest({
    required this.requestId,
    required this.subject,
    required this.draftId,
    required this.expectedDraftDigest,
    required this.expectedDraftRevision,
    required this.expectedContentSetDigest,
    required this.expectedSourceDigest,
    required this.reviewGuideId,
    required this.reviewGuideStepId,
    required this.grantId,
    required this.grantDigest,
  }) {
    _authoringExternalId(reviewGuideId, 'ReviewGuide');
    _authoringId(reviewGuideStepId, 'ReviewGuideStep');
    if (expectedDraftRevision <= 0 ||
        expectedDraftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Review preparation requires a mutated safe head');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest expectedDraftDigest;
  final int expectedDraftRevision;
  final Digest expectedContentSetDigest;
  final Digest expectedSourceDigest;
  final ReviewGuideId reviewGuideId;
  final String reviewGuideStepId;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
  });
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewPrepareRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewPrepareRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewPrepareRequest',
      const <String>{
        'requestId',
        'subject',
        'draftId',
        'expectedDraftDigest',
        'expectedDraftRevision',
        'expectedContentSetDigest',
        'expectedSourceDigest',
        'reviewGuideId',
        'reviewGuideStepId',
        'grantId',
        'grantDigest',
        'payloadDigest',
      },
    );
    final result = ExperienceReviewPrepareRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewPrepareRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'ExperienceReviewPrepareRequest'),
      ),
      expectedDraftDigest: _authoringDigest(
        json,
        'expectedDraftDigest',
        'ExperienceReviewPrepareRequest',
      ),
      expectedDraftRevision: _authoringInt(
        json,
        'expectedDraftRevision',
        'ExperienceReviewPrepareRequest',
      ),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'ExperienceReviewPrepareRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'ExperienceReviewPrepareRequest',
      ),
      reviewGuideId: ReviewGuideId(
        _authoringString(
          json,
          'reviewGuideId',
          'ExperienceReviewPrepareRequest',
        ),
      ),
      reviewGuideStepId: _authoringString(
        json,
        'reviewGuideStepId',
        'ExperienceReviewPrepareRequest',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'ExperienceReviewPrepareRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceReviewPrepareRequest',
      ),
    );
    if (_authoringDigest(
          json,
          'payloadDigest',
          'ExperienceReviewPrepareRequest',
        ) !=
        result.payloadDigest) {
      throw const FormatException(
        'ExperienceReviewPrepareRequest payload mismatch',
      );
    }
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceReviewPrepareRequest',
    );
    return result;
  }

  void validateAgainstGrantIntent(AuthoringGrantIntent intent) {
    if (subject != intent.subject ||
        intent.effect != AuthoringActionEffect.authoring ||
        intent.operation != AuthoringOperation.prepareReview ||
        intent.expectedDigest != expectedDraftDigest ||
        intent.expectedSourceDigest != expectedSourceDigest ||
        intent.payloadDigest != payloadDigest) {
      throw StateError('Prepare review request differs from its grant intent');
    }
  }
}

final class ExperienceReviewPrepareResult {
  ExperienceReviewPrepareResult({
    required this.requestId,
    required this.changeSet,
    required this.reviewPacket,
    required this.head,
  }) {
    if (reviewPacket.findings.isNotEmpty ||
        reviewPacket.concepts.isNotEmpty ||
        reviewPacket.comments.isNotEmpty ||
        reviewPacket.automatedAcceptance != null ||
        reviewPacket.humanDecisions.isNotEmpty ||
        reviewPacket.revision != 0 ||
        reviewPacket.previousReviewPacketDigest != null) {
      throw ArgumentError('Prepared review packet must be an initial packet');
    }
    _validateReviewPair(changeSet, reviewPacket);
    if (head.subject != changeSet.subject ||
        head.draft?.digest != changeSet.draftDigest ||
        head.changeSet?.id != changeSet.id ||
        head.changeSet?.digest != changeSet.digest ||
        head.review?.id != reviewPacket.id ||
        head.review?.digest != reviewPacket.digest ||
        head.review?.revision != reviewPacket.revision) {
      throw ArgumentError(
        'Prepared review head does not expose its exact pair',
      );
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperienceChangeSet changeSet;
  final ExperienceReviewPacket reviewPacket;
  final ExperienceAuthoringSubjectHead head;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewPrepareResult',
    'requestId': requestId.value,
    'changeSet': changeSet.toJson(),
    'reviewPacket': reviewPacket.toJson(),
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewPrepareResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewPrepareResult',
      const <String>{'requestId', 'changeSet', 'reviewPacket', 'head'},
    );
    final result = ExperienceReviewPrepareResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewPrepareResult'),
      ),
      changeSet: ExperienceChangeSet.fromJson(json['changeSet']),
      reviewPacket: ExperienceReviewPacket.fromJson(json['reviewPacket']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceReviewPrepareResult',
    );
    return result;
  }

  void validateAgainst(
    ExperienceReviewPrepareRequest request, {
    required LayoutDraft draft,
  }) {
    if (requestId != request.requestId ||
        draft.id != request.draftId ||
        draft.subject != request.subject ||
        draft.digest != request.expectedDraftDigest ||
        draft.revision != request.expectedDraftRevision ||
        draft.contentSetDigest != request.expectedContentSetDigest ||
        draft.baseSourceDigest != request.expectedSourceDigest ||
        changeSet.draftDigest != draft.digest ||
        changeSet.draftRevision != draft.revision ||
        reviewPacket.reviewGuideBinding.reviewGuideId !=
            request.reviewGuideId ||
        reviewPacket.reviewGuideBinding.stepId != request.reviewGuideStepId) {
      throw StateError('Prepared review does not match its exact request');
    }
  }
}

final class ExperienceChangeSetGetRequest {
  ExperienceChangeSetGetRequest({
    required this.requestId,
    required this.subject,
    required this.changeSetId,
    this.expectedChangeSetDigest,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final ExperienceChangeSetId changeSetId;
  final Digest? expectedChangeSetDigest;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceChangeSetGetRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'changeSetId': changeSetId.value,
    if (expectedChangeSetDigest != null)
      'expectedChangeSetDigest': expectedChangeSetDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceChangeSetGetRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceChangeSetGetRequest',
      const <String>{
        'requestId',
        'subject',
        'changeSetId',
        'expectedChangeSetDigest',
      },
    );
    final result = ExperienceChangeSetGetRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceChangeSetGetRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      changeSetId: ExperienceChangeSetId(
        _authoringString(json, 'changeSetId', 'ExperienceChangeSetGetRequest'),
      ),
      expectedChangeSetDigest: _authoringOptionalDigest(
        json,
        'expectedChangeSetDigest',
        'ExperienceChangeSetGetRequest',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceChangeSetGetRequest',
    );
    return result;
  }
}

final class ExperienceChangeSetGetResult {
  ExperienceChangeSetGetResult({
    required this.requestId,
    required this.changeSet,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperienceChangeSet changeSet;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceChangeSetGetResult',
    'requestId': requestId.value,
    'changeSet': changeSet.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceChangeSetGetResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceChangeSetGetResult',
      const <String>{'requestId', 'changeSet'},
    );
    final result = ExperienceChangeSetGetResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceChangeSetGetResult'),
      ),
      changeSet: ExperienceChangeSet.fromJson(json['changeSet']),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceChangeSetGetResult');
    return result;
  }

  void validateAgainst(ExperienceChangeSetGetRequest request) {
    if (requestId != request.requestId ||
        changeSet.id != request.changeSetId ||
        changeSet.subject != request.subject ||
        (request.expectedChangeSetDigest != null &&
            changeSet.digest != request.expectedChangeSetDigest)) {
      throw StateError('ChangeSet result does not match its request');
    }
  }
}

final class ExperienceReviewGetRequest {
  ExperienceReviewGetRequest({
    required this.requestId,
    required this.subject,
    required this.reviewPacketId,
    this.expectedReviewPacketDigest,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final ExperienceReviewPacketId reviewPacketId;
  final Digest? expectedReviewPacketDigest;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewGetRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'reviewPacketId': reviewPacketId.value,
    if (expectedReviewPacketDigest != null)
      'expectedReviewPacketDigest': expectedReviewPacketDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewGetRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewGetRequest',
      const <String>{
        'requestId',
        'subject',
        'reviewPacketId',
        'expectedReviewPacketDigest',
      },
    );
    final result = ExperienceReviewGetRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewGetRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      reviewPacketId: ExperienceReviewPacketId(
        _authoringString(json, 'reviewPacketId', 'ExperienceReviewGetRequest'),
      ),
      expectedReviewPacketDigest: _authoringOptionalDigest(
        json,
        'expectedReviewPacketDigest',
        'ExperienceReviewGetRequest',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceReviewGetRequest');
    return result;
  }
}

final class ExperienceReviewGetResult {
  ExperienceReviewGetResult({
    required this.requestId,
    required this.reviewPacket,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperienceReviewPacket reviewPacket;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewGetResult',
    'requestId': requestId.value,
    'reviewPacket': reviewPacket.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewGetResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewGetResult',
      const <String>{'requestId', 'reviewPacket'},
    );
    final result = ExperienceReviewGetResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewGetResult'),
      ),
      reviewPacket: ExperienceReviewPacket.fromJson(json['reviewPacket']),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceReviewGetResult');
    return result;
  }

  void validateAgainst(ExperienceReviewGetRequest request) {
    if (requestId != request.requestId ||
        reviewPacket.id != request.reviewPacketId ||
        reviewPacket.subject != request.subject ||
        (request.expectedReviewPacketDigest != null &&
            reviewPacket.digest != request.expectedReviewPacketDigest)) {
      throw StateError('Review result does not match its request');
    }
  }

  void validateWithChangeSet(ExperienceChangeSetGetResult changeSetResult) {
    _validateReviewPair(changeSetResult.changeSet, reviewPacket);
  }
}

void _validateReviewPair(
  ExperienceChangeSet changeSet,
  ExperienceReviewPacket reviewPacket,
) {
  if (reviewPacket.subject != changeSet.subject ||
      reviewPacket.changeSetId != changeSet.id ||
      reviewPacket.changeSetDigest != changeSet.digest ||
      reviewPacket.comparisonDigest != changeSet.comparison.digest ||
      reviewPacket.baseSourceDigest != changeSet.baseSourceDigest) {
    throw StateError('Review packet and ChangeSet fences do not match');
  }
}
