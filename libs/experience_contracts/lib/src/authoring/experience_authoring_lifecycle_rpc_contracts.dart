part of 'experience_authoring_contracts.dart';

final class LayoutDraftHeadRef {
  LayoutDraftHeadRef({
    required this.id,
    required this.digest,
    required this.revision,
  }) {
    if (revision < 0 || revision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Draft head revision must be a safe integer');
    }
  }

  final LayoutDraftId id;
  final Digest digest;
  final int revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'digest': digest.value,
    'revision': revision,
  };

  factory LayoutDraftHeadRef.fromJson(Object? value) {
    final json = _authoringObject(value, 'LayoutDraftHeadRef');
    _authoringOnly(json, const <String>{
      'id',
      'digest',
      'revision',
    }, 'LayoutDraftHeadRef');
    return LayoutDraftHeadRef(
      id: LayoutDraftId(_authoringString(json, 'id', 'LayoutDraftHeadRef')),
      digest: _authoringDigest(json, 'digest', 'LayoutDraftHeadRef'),
      revision: _authoringInt(json, 'revision', 'LayoutDraftHeadRef'),
    );
  }

  factory LayoutDraftHeadRef.fromDraft(LayoutDraft draft) => LayoutDraftHeadRef(
    id: draft.id,
    digest: draft.digest,
    revision: draft.revision,
  );
}

final class ExperienceChangeSetHeadRef {
  ExperienceChangeSetHeadRef({
    required this.id,
    required this.digest,
    required this.draftDigest,
  });

  final ExperienceChangeSetId id;
  final Digest digest;
  final Digest draftDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'digest': digest.value,
    'draftDigest': draftDigest.value,
  };

  factory ExperienceChangeSetHeadRef.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceChangeSetHeadRef');
    _authoringOnly(json, const <String>{
      'id',
      'digest',
      'draftDigest',
    }, 'ExperienceChangeSetHeadRef');
    return ExperienceChangeSetHeadRef(
      id: ExperienceChangeSetId(
        _authoringString(json, 'id', 'ExperienceChangeSetHeadRef'),
      ),
      digest: _authoringDigest(json, 'digest', 'ExperienceChangeSetHeadRef'),
      draftDigest: _authoringDigest(
        json,
        'draftDigest',
        'ExperienceChangeSetHeadRef',
      ),
    );
  }

  factory ExperienceChangeSetHeadRef.fromChangeSet(
    ExperienceChangeSet changeSet,
  ) => ExperienceChangeSetHeadRef(
    id: changeSet.id,
    digest: changeSet.digest,
    draftDigest: changeSet.draftDigest,
  );
}

final class ExperienceReviewHeadRef {
  ExperienceReviewHeadRef({
    required this.id,
    required this.digest,
    required this.revision,
    required this.changeSetId,
    required this.changeSetDigest,
  }) {
    if (revision < 0 || revision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Review head revision must be a safe integer');
    }
  }

  final ExperienceReviewPacketId id;
  final Digest digest;
  final int revision;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'digest': digest.value,
    'revision': revision,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
  };

  factory ExperienceReviewHeadRef.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceReviewHeadRef');
    _authoringOnly(json, const <String>{
      'id',
      'digest',
      'revision',
      'changeSetId',
      'changeSetDigest',
    }, 'ExperienceReviewHeadRef');
    return ExperienceReviewHeadRef(
      id: ExperienceReviewPacketId(
        _authoringString(json, 'id', 'ExperienceReviewHeadRef'),
      ),
      digest: _authoringDigest(json, 'digest', 'ExperienceReviewHeadRef'),
      revision: _authoringInt(json, 'revision', 'ExperienceReviewHeadRef'),
      changeSetId: ExperienceChangeSetId(
        _authoringString(json, 'changeSetId', 'ExperienceReviewHeadRef'),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperienceReviewHeadRef',
      ),
    );
  }

  factory ExperienceReviewHeadRef.fromPacket(ExperienceReviewPacket packet) =>
      ExperienceReviewHeadRef(
        id: packet.id,
        digest: packet.digest,
        revision: packet.revision,
        changeSetId: packet.changeSetId,
        changeSetDigest: packet.changeSetDigest,
      );
}

final class ExperiencePromotionHeadRef {
  const ExperiencePromotionHeadRef({required this.id, required this.digest});

  final ExperiencePromotionReceiptId id;
  final Digest digest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'digest': digest.value,
  };

  factory ExperiencePromotionHeadRef.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperiencePromotionHeadRef');
    _authoringOnly(json, const <String>{
      'id',
      'digest',
    }, 'ExperiencePromotionHeadRef');
    return ExperiencePromotionHeadRef(
      id: ExperiencePromotionReceiptId(
        _authoringString(json, 'id', 'ExperiencePromotionHeadRef'),
      ),
      digest: _authoringDigest(json, 'digest', 'ExperiencePromotionHeadRef'),
    );
  }

  factory ExperiencePromotionHeadRef.fromReceipt(
    ExperiencePromotionReceipt receipt,
  ) => ExperiencePromotionHeadRef(id: receipt.id, digest: receipt.digest);
}

/// Sanitized durable index that makes authoring state discoverable by subject.
final class ExperienceAuthoringSubjectHead {
  ExperienceAuthoringSubjectHead({
    required this.subject,
    this.draft,
    this.changeSet,
    this.review,
    this.latestPromotion,
  }) {
    if (draft == null && (changeSet != null || review != null)) {
      throw ArgumentError(
        'Closed subject heads cannot expose mutable review heads',
      );
    }
    if (review != null &&
        (changeSet == null ||
            review!.changeSetId != changeSet!.id ||
            review!.changeSetDigest != changeSet!.digest)) {
      throw ArgumentError('Review head must bind the current ChangeSet head');
    }
    if (draft != null &&
        changeSet != null &&
        changeSet!.draftDigest != draft!.digest) {
      throw ArgumentError('ChangeSet head must bind the current draft head');
    }
  }

  final AuthoringSubjectRef subject;
  final LayoutDraftHeadRef? draft;
  final ExperienceChangeSetHeadRef? changeSet;
  final ExperienceReviewHeadRef? review;
  final ExperiencePromotionHeadRef? latestPromotion;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'subject': subject.toJson(),
    if (draft != null) 'draft': draft!.toJson(),
    if (changeSet != null) 'changeSet': changeSet!.toJson(),
    if (review != null) 'review': review!.toJson(),
    if (latestPromotion != null) 'latestPromotion': latestPromotion!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringSubjectHead.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceAuthoringSubjectHead');
    _authoringOnly(json, const <String>{
      'subject',
      'draft',
      'changeSet',
      'review',
      'latestPromotion',
      'digest',
    }, 'ExperienceAuthoringSubjectHead');
    final result = ExperienceAuthoringSubjectHead(
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draft: json.containsKey('draft')
          ? LayoutDraftHeadRef.fromJson(json['draft'])
          : null,
      changeSet: json.containsKey('changeSet')
          ? ExperienceChangeSetHeadRef.fromJson(json['changeSet'])
          : null,
      review: json.containsKey('review')
          ? ExperienceReviewHeadRef.fromJson(json['review'])
          : null,
      latestPromotion: json.containsKey('latestPromotion')
          ? ExperiencePromotionHeadRef.fromJson(json['latestPromotion'])
          : null,
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceAuthoringSubjectHead',
    );
    return result;
  }
}

final class ExperienceAuthoringSubjectHeadRequest {
  ExperienceAuthoringSubjectHeadRequest({
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
    'kind': 'ExperienceAuthoringSubjectHeadRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringSubjectHeadRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceAuthoringSubjectHeadRequest',
      const <String>{'requestId', 'subject'},
    );
    final result = ExperienceAuthoringSubjectHeadRequest(
      requestId: AuthoringRequestId(
        _authoringString(
          json,
          'requestId',
          'ExperienceAuthoringSubjectHeadRequest',
        ),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceAuthoringSubjectHeadRequest',
    );
    return result;
  }
}

final class ExperienceAuthoringSubjectHeadResult {
  ExperienceAuthoringSubjectHeadResult({
    required this.requestId,
    required this.head,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperienceAuthoringSubjectHead head;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceAuthoringSubjectHeadResult',
    'requestId': requestId.value,
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceAuthoringSubjectHeadResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceAuthoringSubjectHeadResult',
      const <String>{'requestId', 'head'},
    );
    final result = ExperienceAuthoringSubjectHeadResult(
      requestId: AuthoringRequestId(
        _authoringString(
          json,
          'requestId',
          'ExperienceAuthoringSubjectHeadResult',
        ),
      ),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceAuthoringSubjectHeadResult',
    );
    return result;
  }

  void validateAgainst(ExperienceAuthoringSubjectHeadRequest request) {
    if (requestId != request.requestId || head.subject != request.subject) {
      throw StateError('Subject head result does not match its request');
    }
  }
}

final class LayoutDraftAbandonRequest {
  LayoutDraftAbandonRequest({
    required this.requestId,
    required this.subject,
    required this.draftId,
    required this.expectedDraftDigest,
    required this.expectedDraftRevision,
    required this.expectedSourceDigest,
    required this.grantId,
    required this.grantDigest,
  }) {
    if (expectedDraftRevision < 0 ||
        expectedDraftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Expected draft revision must be a safe integer');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest expectedDraftDigest;
  final int expectedDraftRevision;
  final Digest expectedSourceDigest;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'expectedSourceDigest': expectedSourceDigest.value,
  });
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftAbandonRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'expectedDraftDigest': expectedDraftDigest.value,
    'expectedDraftRevision': expectedDraftRevision,
    'expectedSourceDigest': expectedSourceDigest.value,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftAbandonRequest.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'LayoutDraftAbandonRequest', const <String>{
          'requestId',
          'subject',
          'draftId',
          'expectedDraftDigest',
          'expectedDraftRevision',
          'expectedSourceDigest',
          'grantId',
          'grantDigest',
          'payloadDigest',
        });
    final result = LayoutDraftAbandonRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftAbandonRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'LayoutDraftAbandonRequest'),
      ),
      expectedDraftDigest: _authoringDigest(
        json,
        'expectedDraftDigest',
        'LayoutDraftAbandonRequest',
      ),
      expectedDraftRevision: _authoringInt(
        json,
        'expectedDraftRevision',
        'LayoutDraftAbandonRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'LayoutDraftAbandonRequest',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'LayoutDraftAbandonRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'LayoutDraftAbandonRequest',
      ),
    );
    _authoringVerifyPayload(
      json,
      result.payloadDigest,
      'LayoutDraftAbandonRequest',
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftAbandonRequest');
    return result;
  }

  void validateAgainstGrantIntent(AuthoringGrantIntent intent) {
    if (subject != intent.subject ||
        intent.effect != AuthoringActionEffect.authoring ||
        intent.operation != AuthoringOperation.abandonDraft ||
        intent.expectedDigest != expectedDraftDigest ||
        intent.expectedSourceDigest != expectedSourceDigest ||
        intent.payloadDigest != payloadDigest) {
      throw StateError('Abandon request differs from its grant intent');
    }
  }
}

final class LayoutDraftAbandonResult {
  LayoutDraftAbandonResult({
    required this.requestId,
    required this.receipt,
    required this.head,
  }) {
    if (head.draft != null || head.subject != receipt.subject) {
      throw ArgumentError('Abandon result must release the subject draft head');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final LayoutDraftAbandonReceipt receipt;
  final ExperienceAuthoringSubjectHead head;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftAbandonResult',
    'requestId': requestId.value,
    'receipt': receipt.toJson(),
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftAbandonResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'LayoutDraftAbandonResult',
      const <String>{'requestId', 'receipt', 'head'},
    );
    final result = LayoutDraftAbandonResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftAbandonResult'),
      ),
      receipt: LayoutDraftAbandonReceipt.fromJson(json['receipt']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftAbandonResult');
    return result;
  }

  void validateAgainst(LayoutDraftAbandonRequest request) {
    if (requestId != request.requestId ||
        receipt.requestId != request.requestId ||
        receipt.subject != request.subject ||
        receipt.draftId != request.draftId ||
        receipt.finalDraftDigest != request.expectedDraftDigest ||
        receipt.finalDraftRevision != request.expectedDraftRevision ||
        receipt.sourceDigest != request.expectedSourceDigest) {
      throw StateError('Abandon result does not match its exact request');
    }
  }
}

final class ExperiencePromotionGrantRequest implements AuthoringGrantIntent {
  ExperiencePromotionGrantRequest({
    required this.requestId,
    required this.capabilityDigest,
    required this.subject,
    required this.draftId,
    required this.draftDigest,
    required this.draftRevision,
    required this.changeSetId,
    required this.changeSetDigest,
    required this.reviewPacketId,
    required this.reviewPacketDigest,
    required this.expectedSourceDigest,
    required this.expectedContentSetDigest,
    required this.candidateLayoutDigest,
  }) {
    if (draftRevision <= 0 ||
        draftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Promotion must bind a mutated safe draft revision');
    }
  }

  static const int schemaVersion = 1;
  @override
  final AuthoringRequestId requestId;
  @override
  final Digest capabilityDigest;
  @override
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest draftDigest;
  final int draftRevision;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final ExperienceReviewPacketId reviewPacketId;
  final Digest reviewPacketDigest;
  @override
  final Digest expectedSourceDigest;
  final Digest expectedContentSetDigest;
  final Digest candidateLayoutDigest;

  @override
  AuthoringActionEffect get effect => AuthoringActionEffect.authoring;
  @override
  AuthoringOperation get operation => AuthoringOperation.promote;
  @override
  Digest get expectedDigest => reviewPacketDigest;
  @override
  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'candidateLayoutDigest': candidateLayoutDigest.value,
  });
  @override
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionGrantRequest',
    'requestId': requestId.value,
    'capabilityDigest': capabilityDigest.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'candidateLayoutDigest': candidateLayoutDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionGrantRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionGrantRequest',
      const <String>{
        'requestId',
        'capabilityDigest',
        'subject',
        'draftId',
        'draftDigest',
        'draftRevision',
        'changeSetId',
        'changeSetDigest',
        'reviewPacketId',
        'reviewPacketDigest',
        'expectedSourceDigest',
        'expectedContentSetDigest',
        'candidateLayoutDigest',
        'payloadDigest',
      },
    );
    final result = ExperiencePromotionGrantRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionGrantRequest'),
      ),
      capabilityDigest: _authoringDigest(
        json,
        'capabilityDigest',
        'ExperiencePromotionGrantRequest',
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'ExperiencePromotionGrantRequest'),
      ),
      draftDigest: _authoringDigest(
        json,
        'draftDigest',
        'ExperiencePromotionGrantRequest',
      ),
      draftRevision: _authoringInt(
        json,
        'draftRevision',
        'ExperiencePromotionGrantRequest',
      ),
      changeSetId: ExperienceChangeSetId(
        _authoringString(
          json,
          'changeSetId',
          'ExperiencePromotionGrantRequest',
        ),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperiencePromotionGrantRequest',
      ),
      reviewPacketId: ExperienceReviewPacketId(
        _authoringString(
          json,
          'reviewPacketId',
          'ExperiencePromotionGrantRequest',
        ),
      ),
      reviewPacketDigest: _authoringDigest(
        json,
        'reviewPacketDigest',
        'ExperiencePromotionGrantRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'ExperiencePromotionGrantRequest',
      ),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'ExperiencePromotionGrantRequest',
      ),
      candidateLayoutDigest: _authoringDigest(
        json,
        'candidateLayoutDigest',
        'ExperiencePromotionGrantRequest',
      ),
    );
    _authoringVerifyPayload(
      json,
      result.payloadDigest,
      'ExperiencePromotionGrantRequest',
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionGrantRequest',
    );
    return result;
  }

  void validateAgainst({
    required LayoutDraft draft,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
  }) {
    if (draft.id != draftId ||
        draft.subject != subject ||
        draft.digest != draftDigest ||
        draft.revision != draftRevision ||
        draft.baseSourceDigest != expectedSourceDigest ||
        draft.contentSetDigest != expectedContentSetDigest ||
        draft.candidateLayoutDigest != candidateLayoutDigest ||
        changeSet.id != changeSetId ||
        changeSet.digest != changeSetDigest ||
        changeSet.subject != subject ||
        changeSet.draftDigest != draft.digest ||
        changeSet.draftRevision != draft.revision ||
        changeSet.baseSourceDigest != expectedSourceDigest ||
        changeSet.expectedContentSetDigest != expectedContentSetDigest ||
        changeSet.comparison.beforeLayoutDigest != draft.baseLayoutDigest ||
        changeSet.comparison.afterLayoutDigest != candidateLayoutDigest ||
        changeSet.comparison.topologyDigest != draft.topologyDigest ||
        reviewPacket.id != reviewPacketId ||
        reviewPacket.digest != reviewPacketDigest ||
        reviewPacket.subject != subject ||
        reviewPacket.changeSetId != changeSet.id ||
        reviewPacket.changeSetDigest != changeSet.digest ||
        reviewPacket.comparisonDigest != changeSet.comparison.digest ||
        reviewPacket.baseSourceDigest != expectedSourceDigest ||
        !reviewPacket.isPromotable) {
      throw StateError('Promotion grant request does not bind current heads');
    }
  }
}

final class ExperiencePromotionApplyRequest {
  ExperiencePromotionApplyRequest({
    required this.requestId,
    required this.subject,
    required this.draftId,
    required this.draftDigest,
    required this.draftRevision,
    required this.changeSetId,
    required this.changeSetDigest,
    required this.reviewPacketId,
    required this.reviewPacketDigest,
    required this.expectedSourceDigest,
    required this.expectedContentSetDigest,
    required this.candidateLayoutDigest,
    required this.grantId,
    required this.grantDigest,
  }) {
    if (draftRevision <= 0 ||
        draftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Promotion must bind a mutated safe draft revision');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest draftDigest;
  final int draftRevision;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final ExperienceReviewPacketId reviewPacketId;
  final Digest reviewPacketDigest;
  final Digest expectedSourceDigest;
  final Digest expectedContentSetDigest;
  final Digest candidateLayoutDigest;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'candidateLayoutDigest': candidateLayoutDigest.value,
  });
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionApplyRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'candidateLayoutDigest': candidateLayoutDigest.value,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionApplyRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionApplyRequest',
      const <String>{
        'requestId',
        'subject',
        'draftId',
        'draftDigest',
        'draftRevision',
        'changeSetId',
        'changeSetDigest',
        'reviewPacketId',
        'reviewPacketDigest',
        'expectedSourceDigest',
        'expectedContentSetDigest',
        'candidateLayoutDigest',
        'grantId',
        'grantDigest',
        'payloadDigest',
      },
    );
    final result = ExperiencePromotionApplyRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionApplyRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'ExperiencePromotionApplyRequest'),
      ),
      draftDigest: _authoringDigest(
        json,
        'draftDigest',
        'ExperiencePromotionApplyRequest',
      ),
      draftRevision: _authoringInt(
        json,
        'draftRevision',
        'ExperiencePromotionApplyRequest',
      ),
      changeSetId: ExperienceChangeSetId(
        _authoringString(
          json,
          'changeSetId',
          'ExperiencePromotionApplyRequest',
        ),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperiencePromotionApplyRequest',
      ),
      reviewPacketId: ExperienceReviewPacketId(
        _authoringString(
          json,
          'reviewPacketId',
          'ExperiencePromotionApplyRequest',
        ),
      ),
      reviewPacketDigest: _authoringDigest(
        json,
        'reviewPacketDigest',
        'ExperiencePromotionApplyRequest',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'ExperiencePromotionApplyRequest',
      ),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'ExperiencePromotionApplyRequest',
      ),
      candidateLayoutDigest: _authoringDigest(
        json,
        'candidateLayoutDigest',
        'ExperiencePromotionApplyRequest',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'ExperiencePromotionApplyRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperiencePromotionApplyRequest',
      ),
    );
    _authoringVerifyPayload(
      json,
      result.payloadDigest,
      'ExperiencePromotionApplyRequest',
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionApplyRequest',
    );
    return result;
  }

  void validateAgainst(ExperiencePromotionGrantRequest intent) {
    if (subject != intent.subject ||
        draftId != intent.draftId ||
        draftDigest != intent.draftDigest ||
        draftRevision != intent.draftRevision ||
        changeSetId != intent.changeSetId ||
        changeSetDigest != intent.changeSetDigest ||
        reviewPacketId != intent.reviewPacketId ||
        reviewPacketDigest != intent.reviewPacketDigest ||
        expectedSourceDigest != intent.expectedSourceDigest ||
        expectedContentSetDigest != intent.expectedContentSetDigest ||
        candidateLayoutDigest != intent.candidateLayoutDigest ||
        payloadDigest != intent.payloadDigest) {
      throw StateError('Promotion apply request differs from its grant intent');
    }
  }
}

final class ExperiencePromotionApplyResult {
  ExperiencePromotionApplyResult({
    required this.requestId,
    required this.receipt,
    required this.head,
  }) {
    if (head.subject != receipt.subject ||
        head.draft != null ||
        head.latestPromotion?.id != receipt.id ||
        head.latestPromotion?.digest != receipt.digest) {
      throw ArgumentError('Promotion result does not expose its closed head');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperiencePromotionReceipt receipt;
  final ExperienceAuthoringSubjectHead head;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionApplyResult',
    'requestId': requestId.value,
    'receipt': receipt.toJson(),
    'head': head.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionApplyResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionApplyResult',
      const <String>{'requestId', 'receipt', 'head'},
    );
    final result = ExperiencePromotionApplyResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionApplyResult'),
      ),
      receipt: ExperiencePromotionReceipt.fromJson(json['receipt']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionApplyResult',
    );
    return result;
  }

  void validateAgainst(ExperiencePromotionApplyRequest request) {
    if (requestId != request.requestId ||
        receipt.subject != request.subject ||
        receipt.draftId != request.draftId ||
        receipt.draftDigest != request.draftDigest ||
        receipt.draftRevision != request.draftRevision ||
        receipt.sourceDigest != request.expectedSourceDigest ||
        receipt.previousContentSetDigest != request.expectedContentSetDigest ||
        receipt.resultContentSetDigest == request.expectedContentSetDigest ||
        receipt.layoutDigest != request.candidateLayoutDigest ||
        receipt.changeSetId != request.changeSetId ||
        receipt.changeSetDigest != request.changeSetDigest ||
        receipt.reviewPacketId != request.reviewPacketId ||
        receipt.reviewPacketDigest != request.reviewPacketDigest) {
      throw StateError('Promotion result does not match its exact request');
    }
  }
}

/// Reads one durable promotion receipt without exposing Host authority state.
final class ExperiencePromotionGetRequest {
  ExperiencePromotionGetRequest({
    required this.requestId,
    required this.subject,
    required this.receiptId,
    this.expectedReceiptDigest,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final ExperiencePromotionReceiptId receiptId;
  final Digest? expectedReceiptDigest;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionGetRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'receiptId': receiptId.value,
    if (expectedReceiptDigest != null)
      'expectedReceiptDigest': expectedReceiptDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionGetRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionGetRequest',
      const <String>{
        'requestId',
        'subject',
        'receiptId',
        'expectedReceiptDigest',
      },
    );
    final result = ExperiencePromotionGetRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionGetRequest'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      receiptId: ExperiencePromotionReceiptId(
        _authoringString(json, 'receiptId', 'ExperiencePromotionGetRequest'),
      ),
      expectedReceiptDigest: _authoringOptionalDigest(
        json,
        'expectedReceiptDigest',
        'ExperiencePromotionGetRequest',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionGetRequest',
    );
    return result;
  }
}

final class ExperiencePromotionGetResult {
  ExperiencePromotionGetResult({
    required this.requestId,
    required this.receipt,
  });

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperiencePromotionReceipt receipt;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionGetResult',
    'requestId': requestId.value,
    'receipt': receipt.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionGetResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionGetResult',
      const <String>{'requestId', 'receipt'},
    );
    final result = ExperiencePromotionGetResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionGetResult'),
      ),
      receipt: ExperiencePromotionReceipt.fromJson(json['receipt']),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperiencePromotionGetResult');
    return result;
  }

  void validateAgainst(ExperiencePromotionGetRequest request) {
    if (requestId != request.requestId ||
        receipt.subject != request.subject ||
        receipt.id != request.receiptId ||
        (request.expectedReceiptDigest != null &&
            receipt.digest != request.expectedReceiptDigest)) {
      throw StateError('Promotion receipt does not match its request');
    }
  }
}

final class ExperiencePromotionHistoryRequest {
  ExperiencePromotionHistoryRequest({
    required this.requestId,
    required this.subject,
    required this.offset,
    required this.limit,
  }) {
    if (offset < 0 ||
        offset > experienceAuthoringMaxSafeInteger ||
        limit <= 0 ||
        limit > experienceAuthoringMaxPromotionReceipts) {
      throw ArgumentError('Promotion history page is outside its profile');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final int offset;
  final int limit;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionHistoryRequest',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'offset': offset,
    'limit': limit,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionHistoryRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionHistoryRequest',
      const <String>{'requestId', 'subject', 'offset', 'limit'},
    );
    final result = ExperiencePromotionHistoryRequest(
      requestId: AuthoringRequestId(
        _authoringString(
          json,
          'requestId',
          'ExperiencePromotionHistoryRequest',
        ),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      offset: _authoringInt(
        json,
        'offset',
        'ExperiencePromotionHistoryRequest',
      ),
      limit: _authoringInt(json, 'limit', 'ExperiencePromotionHistoryRequest'),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionHistoryRequest',
    );
    return result;
  }
}

final class ExperiencePromotionHistoryResult {
  ExperiencePromotionHistoryResult({
    required this.requestId,
    required this.subject,
    required this.offset,
    required this.limit,
    required this.totalCount,
    required this.previousPageReceiptDigest,
    required List<ExperiencePromotionReceipt> receipts,
  }) : receipts = List<ExperiencePromotionReceipt>.unmodifiable(receipts) {
    if (offset < 0 ||
        offset > experienceAuthoringMaxSafeInteger ||
        limit <= 0 ||
        limit > experienceAuthoringMaxPromotionReceipts ||
        totalCount < 0 ||
        totalCount > experienceAuthoringMaxSafeInteger ||
        (offset == 0) != (previousPageReceiptDigest == null) ||
        this.receipts.length > limit ||
        this.receipts.any((receipt) => receipt.subject != subject) ||
        this.receipts.map((receipt) => receipt.id).toSet().length !=
            this.receipts.length) {
      throw ArgumentError('Promotion history exceeds its bounded subject view');
    }
    final expectedLength = totalCount == 0
        ? 0
        : (totalCount - offset < limit ? totalCount - offset : limit);
    if (offset > totalCount ||
        this.receipts.length != expectedLength ||
        (totalCount == 0 && offset != 0)) {
      throw ArgumentError('Promotion history page does not cover its range');
    }
    for (var index = 0; index < this.receipts.length; index += 1) {
      final expectedPrevious = index == 0
          ? previousPageReceiptDigest
          : this.receipts[index - 1].digest;
      if (this.receipts[index].sequence != offset + index + 1 ||
          this.receipts[index].previousReceiptDigest != expectedPrevious) {
        throw ArgumentError('Promotion history receipt chain is disconnected');
      }
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final int offset;
  final int limit;
  final int totalCount;
  final Digest? previousPageReceiptDigest;
  final List<ExperiencePromotionReceipt> receipts;
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionHistoryResult',
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'offset': offset,
    'limit': limit,
    'totalCount': totalCount,
    if (previousPageReceiptDigest != null)
      'previousPageReceiptDigest': previousPageReceiptDigest!.value,
    'receipts': receipts.map((receipt) => receipt.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionHistoryResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperiencePromotionHistoryResult',
      const <String>{
        'requestId',
        'subject',
        'offset',
        'limit',
        'totalCount',
        'previousPageReceiptDigest',
        'receipts',
      },
    );
    final result = ExperiencePromotionHistoryResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperiencePromotionHistoryResult'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      offset: _authoringInt(json, 'offset', 'ExperiencePromotionHistoryResult'),
      limit: _authoringInt(json, 'limit', 'ExperiencePromotionHistoryResult'),
      totalCount: _authoringInt(
        json,
        'totalCount',
        'ExperiencePromotionHistoryResult',
      ),
      previousPageReceiptDigest: _authoringOptionalDigest(
        json,
        'previousPageReceiptDigest',
        'ExperiencePromotionHistoryResult',
      ),
      receipts: _authoringList(
        json,
        'receipts',
        'ExperiencePromotionHistoryResult',
        maxItems: experienceAuthoringMaxPromotionReceipts,
      ).map(ExperiencePromotionReceipt.fromJson).toList(growable: false),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperiencePromotionHistoryResult',
    );
    return result;
  }

  void validateAgainst(ExperiencePromotionHistoryRequest request) {
    if (requestId != request.requestId ||
        subject != request.subject ||
        offset != request.offset ||
        limit != request.limit) {
      throw StateError('Promotion history does not match its request');
    }
  }

  void validateLatestHead(ExperienceAuthoringSubjectHead head) {
    if (head.subject != subject || offset + receipts.length != totalCount) {
      throw StateError('History page is not the final subject page');
    }
    final latest = receipts.isEmpty ? null : receipts.last;
    if ((latest == null) != (head.latestPromotion == null) ||
        (latest != null &&
            (head.latestPromotion!.id != latest.id ||
                head.latestPromotion!.digest != latest.digest))) {
      throw StateError('Promotion history does not match the subject head');
    }
  }
}

void _authoringVerifyPayload(
  Map<String, Object?> json,
  Digest expected,
  String path,
) {
  if (_authoringDigest(json, 'payloadDigest', path) != expected) {
    throw FormatException('$path payload digest mismatch');
  }
}
