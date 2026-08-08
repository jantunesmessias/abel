part of 'experience_authoring_contracts.dart';

/// Exact current-head fence shared by bounded review effects.
final class ExperienceReviewMutationFence {
  ExperienceReviewMutationFence({
    required this.subject,
    required this.changeSetId,
    required this.changeSetDigest,
    required this.reviewPacketId,
    required this.reviewPacketDigest,
    required this.reviewPacketRevision,
    required this.expectedSourceDigest,
    required this.expectedContentSetDigest,
  }) {
    if (reviewPacketRevision < 0 ||
        reviewPacketRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Review packet revision must be a safe integer');
    }
  }

  final AuthoringSubjectRef subject;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final ExperienceReviewPacketId reviewPacketId;
  final Digest reviewPacketDigest;
  final int reviewPacketRevision;
  final Digest expectedSourceDigest;
  final Digest expectedContentSetDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'subject': subject.toJson(),
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'reviewPacketRevision': reviewPacketRevision,
    'expectedSourceDigest': expectedSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
  };

  factory ExperienceReviewMutationFence.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceReviewMutationFence');
    _authoringOnly(json, const <String>{
      'subject',
      'changeSetId',
      'changeSetDigest',
      'reviewPacketId',
      'reviewPacketDigest',
      'reviewPacketRevision',
      'expectedSourceDigest',
      'expectedContentSetDigest',
    }, 'ExperienceReviewMutationFence');
    return ExperienceReviewMutationFence(
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      changeSetId: ExperienceChangeSetId(
        _authoringString(json, 'changeSetId', 'ExperienceReviewMutationFence'),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperienceReviewMutationFence',
      ),
      reviewPacketId: ExperienceReviewPacketId(
        _authoringString(
          json,
          'reviewPacketId',
          'ExperienceReviewMutationFence',
        ),
      ),
      reviewPacketDigest: _authoringDigest(
        json,
        'reviewPacketDigest',
        'ExperienceReviewMutationFence',
      ),
      reviewPacketRevision: _authoringInt(
        json,
        'reviewPacketRevision',
        'ExperienceReviewMutationFence',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'ExperienceReviewMutationFence',
      ),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'ExperienceReviewMutationFence',
      ),
    );
  }

  void validateAgainst({
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket packet,
  }) {
    if (changeSet.id != changeSetId ||
        changeSet.digest != changeSetDigest ||
        changeSet.subject != subject ||
        changeSet.baseSourceDigest != expectedSourceDigest ||
        changeSet.expectedContentSetDigest != expectedContentSetDigest ||
        packet.id != reviewPacketId ||
        packet.digest != reviewPacketDigest ||
        packet.revision != reviewPacketRevision ||
        packet.subject != subject ||
        packet.changeSetId != changeSetId ||
        packet.changeSetDigest != changeSetDigest ||
        packet.comparisonDigest != changeSet.comparison.digest ||
        packet.baseSourceDigest != expectedSourceDigest) {
      throw StateError('Review action fence does not match current heads');
    }
  }
}

/// Closed effect request. Host-only record fields never appear in this payload.
final class ExperienceReviewActionRequest {
  ExperienceReviewActionRequest({
    required this.requestId,
    required this.fence,
    required this.operation,
    required this.grantId,
    required this.grantDigest,
    this.finding,
    this.concept,
    this.comment,
    this.decision,
    this.expectedAutomatedAcceptanceDigest,
  }) {
    final valid = switch (operation) {
      AuthoringOperation.appendFinding =>
        finding != null &&
            concept == null &&
            comment == null &&
            decision == null &&
            expectedAutomatedAcceptanceDigest == null,
      AuthoringOperation.proposeConcept =>
        finding == null &&
            concept != null &&
            comment == null &&
            decision == null &&
            expectedAutomatedAcceptanceDigest == null,
      AuthoringOperation.appendComment =>
        finding == null &&
            concept == null &&
            comment != null &&
            decision == null &&
            expectedAutomatedAcceptanceDigest == null,
      AuthoringOperation.evaluateAutomatedAcceptance =>
        finding == null &&
            concept == null &&
            comment == null &&
            decision == null &&
            expectedAutomatedAcceptanceDigest == null,
      AuthoringOperation.decideReview =>
        finding == null &&
            concept == null &&
            comment == null &&
            decision != null &&
            expectedAutomatedAcceptanceDigest != null,
      _ => false,
    };
    if (!valid) {
      throw ArgumentError('Review action payload does not match its operation');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final ExperienceReviewMutationFence fence;
  final AuthoringOperation operation;
  final AuthoringActionGrantId grantId;
  final Digest grantDigest;
  final AppendExperienceFindingInput? finding;
  final ProposeExperienceConceptInput? concept;
  final AppendExperienceReviewCommentInput? comment;
  final AppendExperienceHumanDecisionInput? decision;
  final Digest? expectedAutomatedAcceptanceDigest;

  AuthoringActionEffect get effect => authoringEffectFor(operation);

  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'fence': fence.toJson(),
    'operation': operation.name,
    if (finding != null) 'finding': finding!.toJson(),
    if (concept != null) 'concept': concept!.toJson(),
    if (comment != null) 'comment': comment!.toJson(),
    if (decision != null) 'decision': decision!.toJson(),
    if (expectedAutomatedAcceptanceDigest != null)
      'expectedAutomatedAcceptanceDigest':
          expectedAutomatedAcceptanceDigest!.value,
  });
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewActionRequest',
    'requestId': requestId.value,
    'fence': fence.toJson(),
    'operation': operation.name,
    if (finding != null) 'finding': finding!.toJson(),
    if (concept != null) 'concept': concept!.toJson(),
    if (comment != null) 'comment': comment!.toJson(),
    if (decision != null) 'decision': decision!.toJson(),
    if (expectedAutomatedAcceptanceDigest != null)
      'expectedAutomatedAcceptanceDigest':
          expectedAutomatedAcceptanceDigest!.value,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewActionRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewActionRequest',
      const <String>{
        'requestId',
        'fence',
        'operation',
        'finding',
        'concept',
        'comment',
        'decision',
        'expectedAutomatedAcceptanceDigest',
        'grantId',
        'grantDigest',
        'payloadDigest',
      },
    );
    final result = ExperienceReviewActionRequest(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewActionRequest'),
      ),
      fence: ExperienceReviewMutationFence.fromJson(json['fence']),
      operation: _authoringEnum(
        AuthoringOperation.values,
        _authoringString(json, 'operation', 'ExperienceReviewActionRequest'),
        'ExperienceReviewActionRequest.operation',
      ),
      grantId: AuthoringActionGrantId(
        _authoringString(json, 'grantId', 'ExperienceReviewActionRequest'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceReviewActionRequest',
      ),
      finding: json.containsKey('finding')
          ? AppendExperienceFindingInput.fromJson(json['finding'])
          : null,
      concept: json.containsKey('concept')
          ? ProposeExperienceConceptInput.fromJson(json['concept'])
          : null,
      comment: json.containsKey('comment')
          ? AppendExperienceReviewCommentInput.fromJson(json['comment'])
          : null,
      decision: json.containsKey('decision')
          ? AppendExperienceHumanDecisionInput.fromJson(json['decision'])
          : null,
      expectedAutomatedAcceptanceDigest: _authoringOptionalDigest(
        json,
        'expectedAutomatedAcceptanceDigest',
        'ExperienceReviewActionRequest',
      ),
    );
    _authoringVerifyPayload(
      json,
      result.payloadDigest,
      'ExperienceReviewActionRequest',
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceReviewActionRequest',
    );
    return result;
  }

  void validateAgainstGrantIntent(AuthoringGrantIntent intent) {
    if (fence.subject != intent.subject ||
        effect != intent.effect ||
        operation != intent.operation ||
        fence.reviewPacketDigest != intent.expectedDigest ||
        fence.expectedSourceDigest != intent.expectedSourceDigest ||
        payloadDigest != intent.payloadDigest) {
      throw StateError('Review effect request differs from its grant intent');
    }
  }
}

/// Dedicated decision grant intent. Acceptance is Host-derived and pre-existing.
final class ExperienceReviewDecisionGrantRequest
    implements AuthoringGrantIntent {
  ExperienceReviewDecisionGrantRequest({
    required this.requestId,
    required this.capabilityDigest,
    required this.fence,
    required this.decision,
    required this.automatedAcceptanceDigest,
  });

  static const int schemaVersion = 1;
  @override
  final AuthoringRequestId requestId;
  @override
  final Digest capabilityDigest;
  final ExperienceReviewMutationFence fence;
  final AppendExperienceHumanDecisionInput decision;
  final Digest automatedAcceptanceDigest;

  @override
  AuthoringSubjectRef get subject => fence.subject;
  @override
  AuthoringActionEffect get effect => AuthoringActionEffect.decision;
  @override
  AuthoringOperation get operation => AuthoringOperation.decideReview;
  @override
  Digest get expectedDigest => fence.reviewPacketDigest;
  @override
  Digest get expectedSourceDigest => fence.expectedSourceDigest;
  @override
  late final Digest payloadDigest = Digest.semantic(<String, Object?>{
    'fence': fence.toJson(),
    'operation': operation.name,
    'decision': decision.toJson(),
    'expectedAutomatedAcceptanceDigest': automatedAcceptanceDigest.value,
  });
  @override
  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewDecisionGrantRequest',
    'requestId': requestId.value,
    'capabilityDigest': capabilityDigest.value,
    'fence': fence.toJson(),
    'decision': decision.toJson(),
    'automatedAcceptanceDigest': automatedAcceptanceDigest.value,
    'payloadDigest': payloadDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewDecisionGrantRequest.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewDecisionGrantRequest',
      const <String>{
        'requestId',
        'capabilityDigest',
        'fence',
        'decision',
        'automatedAcceptanceDigest',
        'payloadDigest',
      },
    );
    final result = ExperienceReviewDecisionGrantRequest(
      requestId: AuthoringRequestId(
        _authoringString(
          json,
          'requestId',
          'ExperienceReviewDecisionGrantRequest',
        ),
      ),
      capabilityDigest: _authoringDigest(
        json,
        'capabilityDigest',
        'ExperienceReviewDecisionGrantRequest',
      ),
      fence: ExperienceReviewMutationFence.fromJson(json['fence']),
      decision: AppendExperienceHumanDecisionInput.fromJson(json['decision']),
      automatedAcceptanceDigest: _authoringDigest(
        json,
        'automatedAcceptanceDigest',
        'ExperienceReviewDecisionGrantRequest',
      ),
    );
    _authoringVerifyPayload(
      json,
      result.payloadDigest,
      'ExperienceReviewDecisionGrantRequest',
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceReviewDecisionGrantRequest',
    );
    return result;
  }

  void validateAgainst({
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket packet,
  }) {
    fence.validateAgainst(changeSet: changeSet, packet: packet);
    if (packet.automatedAcceptance?.digest != automatedAcceptanceDigest) {
      throw StateError('Human decision requires current automated acceptance');
    }
  }
}

final class ExperienceReviewActionResult {
  ExperienceReviewActionResult({
    required this.requestId,
    required this.operation,
    required this.reviewPacket,
    required this.head,
    this.finding,
    this.concept,
    this.comment,
    this.automatedAcceptance,
    this.decision,
  }) {
    final present = <Object?>[
      finding,
      concept,
      comment,
      automatedAcceptance,
      decision,
    ].where((item) => item != null).length;
    final matches = switch (operation) {
      AuthoringOperation.appendFinding => finding != null,
      AuthoringOperation.proposeConcept => concept != null,
      AuthoringOperation.appendComment => comment != null,
      AuthoringOperation.evaluateAutomatedAcceptance =>
        automatedAcceptance != null,
      AuthoringOperation.decideReview => decision != null,
      _ => false,
    };
    if (present != 1 || !matches) {
      throw ArgumentError('Review result payload does not match its operation');
    }
    if (head.subject != reviewPacket.subject ||
        head.review?.id != reviewPacket.id ||
        head.review?.digest != reviewPacket.digest ||
        head.review?.revision != reviewPacket.revision ||
        head.changeSet?.id != reviewPacket.changeSetId ||
        head.changeSet?.digest != reviewPacket.changeSetDigest) {
      throw ArgumentError(
        'Review action head does not expose the result packet',
      );
    }
  }

  static const int schemaVersion = 1;
  final AuthoringRequestId requestId;
  final AuthoringOperation operation;
  final ExperienceReviewPacket reviewPacket;
  final ExperienceAuthoringSubjectHead head;
  final ExperienceFindingRecord? finding;
  final ExperienceConceptProposalRecord? concept;
  final ExperienceReviewCommentRecord? comment;
  final AutomatedAcceptanceRecord? automatedAcceptance;
  final ExperienceHumanDecisionRecord? decision;

  late final Digest digest = _authoringFrameDigest(
    toJson(includeDigest: false),
  );

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewActionResult',
    'requestId': requestId.value,
    'operation': operation.name,
    'reviewPacket': reviewPacket.toJson(),
    'head': head.toJson(),
    if (finding != null) 'finding': finding!.toJson(),
    if (concept != null) 'concept': concept!.toJson(),
    if (comment != null) 'comment': comment!.toJson(),
    if (automatedAcceptance != null)
      'automatedAcceptance': automatedAcceptance!.toJson(),
    if (decision != null) 'decision': decision!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewActionResult.fromJson(Object? value) {
    final json = _authoringDocument(
      value,
      'ExperienceReviewActionResult',
      const <String>{
        'requestId',
        'operation',
        'reviewPacket',
        'head',
        'finding',
        'concept',
        'comment',
        'automatedAcceptance',
        'decision',
      },
    );
    final result = ExperienceReviewActionResult(
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'ExperienceReviewActionResult'),
      ),
      operation: _authoringEnum(
        AuthoringOperation.values,
        _authoringString(json, 'operation', 'ExperienceReviewActionResult'),
        'ExperienceReviewActionResult.operation',
      ),
      reviewPacket: ExperienceReviewPacket.fromJson(json['reviewPacket']),
      head: ExperienceAuthoringSubjectHead.fromJson(json['head']),
      finding: json.containsKey('finding')
          ? ExperienceFindingRecord.fromJson(json['finding'])
          : null,
      concept: json.containsKey('concept')
          ? ExperienceConceptProposalRecord.fromJson(json['concept'])
          : null,
      comment: json.containsKey('comment')
          ? ExperienceReviewCommentRecord.fromJson(json['comment'])
          : null,
      automatedAcceptance: json.containsKey('automatedAcceptance')
          ? AutomatedAcceptanceRecord.fromJson(json['automatedAcceptance'])
          : null,
      decision: json.containsKey('decision')
          ? ExperienceHumanDecisionRecord.fromJson(json['decision'])
          : null,
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceReviewActionResult');
    return result;
  }

  void validateAgainst(
    ExperienceReviewActionRequest request, {
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket previousPacket,
  }) {
    if (requestId != request.requestId || operation != request.operation) {
      throw StateError('Review result does not match its effect request');
    }
    request.fence.validateAgainst(changeSet: changeSet, packet: previousPacket);
    _validateReviewSuccessor(previousPacket, reviewPacket);

    switch (operation) {
      case AuthoringOperation.appendFinding:
        final record = finding!;
        if (!_sameReviewSubject(record.subject, request.finding!.subject) ||
            record.severity != request.finding!.severity ||
            record.summary != request.finding!.summary ||
            record.detail != request.finding!.detail ||
            record.grantDigest != request.grantDigest ||
            !_sameRecordSet(reviewPacket.findings, <ExperienceFindingRecord>[
              ...previousPacket.findings,
              record,
            ], (item) => item.digest) ||
            !_sameReviewStateExcept(
              previousPacket,
              reviewPacket,
              findingsChanged: true,
            )) {
          throw StateError('Finding result rewrites unrelated review state');
        }
      case AuthoringOperation.proposeConcept:
        final record = concept!;
        if (record.scenarioId != request.concept!.scenarioId ||
            record.title != request.concept!.title ||
            record.rationale != request.concept!.rationale ||
            record.grantDigest != request.grantDigest ||
            !_sameRecordSet(
              reviewPacket.concepts,
              <ExperienceConceptProposalRecord>[
                ...previousPacket.concepts,
                record,
              ],
              (item) => item.digest,
            ) ||
            !_sameReviewStateExcept(
              previousPacket,
              reviewPacket,
              conceptsChanged: true,
            )) {
          throw StateError('Concept result rewrites unrelated review state');
        }
      case AuthoringOperation.appendComment:
        final record = comment!;
        if (!_sameReviewSubject(record.subject, request.comment!.subject) ||
            record.body != request.comment!.body ||
            record.grantDigest != request.grantDigest ||
            !_sameRecordList(
              reviewPacket.comments,
              <ExperienceReviewCommentRecord>[
                ...previousPacket.comments,
                record,
              ],
              (item) => item.digest,
            ) ||
            !_sameReviewStateExcept(
              previousPacket,
              reviewPacket,
              commentsChanged: true,
            )) {
          throw StateError('Comment result rewrites unrelated review state');
        }
      case AuthoringOperation.evaluateAutomatedAcceptance:
        if (previousPacket.automatedAcceptance != null ||
            previousPacket.humanDecisions.isNotEmpty ||
            automatedAcceptance!.digest !=
                reviewPacket.automatedAcceptance?.digest ||
            automatedAcceptance!.changeSetDigest != changeSet.digest ||
            !_sameReviewStateExcept(
              previousPacket,
              reviewPacket,
              acceptanceChanged: true,
            )) {
          throw StateError('Acceptance result rewrites unrelated review state');
        }
      case AuthoringOperation.decideReview:
        final record = decision!;
        if (previousPacket.automatedAcceptance == null ||
            request.expectedAutomatedAcceptanceDigest !=
                previousPacket.automatedAcceptance!.digest ||
            record.changeSetDigest != changeSet.digest ||
            record.reviewPacketDigest != previousPacket.digest ||
            record.decision != request.decision!.decision ||
            record.rationale != request.decision!.rationale ||
            record.grantDigest != request.grantDigest ||
            !_sameRecordList(
              reviewPacket.humanDecisions,
              <ExperienceHumanDecisionRecord>[
                ...previousPacket.humanDecisions,
                record,
              ],
              (item) => item.digest,
            ) ||
            !_sameReviewStateExcept(
              previousPacket,
              reviewPacket,
              decisionsChanged: true,
            )) {
          throw StateError('Decision result rewrites unrelated review state');
        }
      default:
        throw StateError('Unsupported review action result');
    }
  }
}

void _validateReviewSuccessor(
  ExperienceReviewPacket previous,
  ExperienceReviewPacket next,
) {
  if (next.id != previous.id ||
      next.subject != previous.subject ||
      next.changeSetId != previous.changeSetId ||
      next.changeSetDigest != previous.changeSetDigest ||
      next.comparisonDigest != previous.comparisonDigest ||
      next.baseSourceDigest != previous.baseSourceDigest ||
      next.reviewGuideBinding.digest != previous.reviewGuideBinding.digest ||
      next.revision != previous.revision + 1 ||
      next.previousReviewPacketDigest != previous.digest) {
    throw StateError('Review action result breaks the packet head chain');
  }
}

bool _sameReviewStateExcept(
  ExperienceReviewPacket previous,
  ExperienceReviewPacket next, {
  bool findingsChanged = false,
  bool conceptsChanged = false,
  bool commentsChanged = false,
  bool acceptanceChanged = false,
  bool decisionsChanged = false,
}) =>
    (findingsChanged ||
        _sameRecordList(
          previous.findings,
          next.findings,
          (item) => item.digest,
        )) &&
    (conceptsChanged ||
        _sameRecordList(
          previous.concepts,
          next.concepts,
          (item) => item.digest,
        )) &&
    (commentsChanged ||
        _sameRecordList(
          previous.comments,
          next.comments,
          (item) => item.digest,
        )) &&
    (acceptanceChanged ||
        previous.automatedAcceptance?.digest ==
            next.automatedAcceptance?.digest) &&
    (decisionsChanged ||
        _sameRecordList(
          previous.humanDecisions,
          next.humanDecisions,
          (item) => item.digest,
        ));

bool _sameReviewSubject(
  ExperienceReviewSubject left,
  ExperienceReviewSubject right,
) => Digest.semantic(left.toJson()) == Digest.semantic(right.toJson());

bool _sameRecordList<T>(
  List<T> left,
  List<T> right,
  Digest Function(T) digestOf,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (digestOf(left[index]) != digestOf(right[index])) return false;
  }
  return true;
}

bool _sameRecordSet<T>(
  List<T> left,
  List<T> right,
  Digest Function(T) digestOf,
) =>
    left.length == right.length &&
    left.map(digestOf).toSet().containsAll(right.map(digestOf));
