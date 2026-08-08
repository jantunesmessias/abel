import '../canonical_json.dart';
import '../digest.dart';

enum MembershipRole { owner, admin, editor, reviewer, viewer }

enum CollaborationEventKind {
  workspacePushed,
  commentAdded,
  approvalRecorded,
  presenceChanged,
  releasePublished,
}

final class Principal {
  Principal({
    required this.id,
    required this.issuer,
    required this.subject,
    required this.displayName,
  }) {
    _hostedId(id, 'Principal.id');
    _hostedText(issuer, 'Principal.issuer', maximum: 2048);
    _hostedText(subject, 'Principal.subject', maximum: 512);
    _hostedText(displayName, 'Principal.displayName', maximum: 256);
  }

  final String id;
  final String issuer;
  final String subject;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'issuer': issuer,
    'subject': subject,
    'displayName': displayName,
  };

  factory Principal.fromJson(Object? value) {
    final json = _hostedObject(value, 'Principal');
    _hostedOnly(json, const <String>{
      'id',
      'issuer',
      'subject',
      'displayName',
    }, 'Principal');
    return Principal(
      id: _hostedString(json, 'id', 'Principal'),
      issuer: _hostedString(json, 'issuer', 'Principal'),
      subject: _hostedString(json, 'subject', 'Principal'),
      displayName: _hostedString(json, 'displayName', 'Principal'),
    );
  }
}

final class Organization {
  Organization({
    required this.tenantId,
    required this.slug,
    required this.displayName,
    required this.createdAt,
  }) {
    _hostedId(tenantId, 'Organization.tenantId');
    if (!RegExp(r'^[a-z][a-z0-9-]{2,62}$').hasMatch(slug)) {
      throw const FormatException('Organization.slug is invalid');
    }
    _hostedText(displayName, 'Organization.displayName', maximum: 256);
    _hostedUtc(createdAt, 'Organization.createdAt');
  }

  final String tenantId;
  final String slug;
  final String displayName;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'slug': slug,
    'displayName': displayName,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Organization.fromJson(Object? value) {
    final json = _hostedObject(value, 'Organization');
    _hostedOnly(json, const <String>{
      'tenantId',
      'slug',
      'displayName',
      'createdAt',
    }, 'Organization');
    return Organization(
      tenantId: _hostedString(json, 'tenantId', 'Organization'),
      slug: _hostedString(json, 'slug', 'Organization'),
      displayName: _hostedString(json, 'displayName', 'Organization'),
      createdAt: _hostedDate(json, 'createdAt', 'Organization'),
    );
  }
}

final class Membership {
  Membership({
    required this.tenantId,
    required this.principalId,
    required this.role,
    required this.createdAt,
  }) {
    _hostedId(tenantId, 'Membership.tenantId');
    _hostedId(principalId, 'Membership.principalId');
    _hostedUtc(createdAt, 'Membership.createdAt');
  }

  final String tenantId;
  final String principalId;
  final MembershipRole role;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'principalId': principalId,
    'role': role.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Membership.fromJson(Object? value) {
    final json = _hostedObject(value, 'Membership');
    _hostedOnly(json, const <String>{
      'tenantId',
      'principalId',
      'role',
      'createdAt',
    }, 'Membership');
    return Membership(
      tenantId: _hostedString(json, 'tenantId', 'Membership'),
      principalId: _hostedString(json, 'principalId', 'Membership'),
      role: _hostedEnum(
        MembershipRole.values,
        _hostedString(json, 'role', 'Membership'),
        'Membership.role',
      ),
      createdAt: _hostedDate(json, 'createdAt', 'Membership'),
    );
  }
}

final class HostedWorkspaceLink {
  HostedWorkspaceLink({
    required this.tenantId,
    required this.workspaceId,
    required this.localWorkspaceId,
    required this.linkedAt,
    required this.linkedBy,
  }) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('workspaceId', workspaceId),
      MapEntry<String, String>('localWorkspaceId', localWorkspaceId),
      MapEntry<String, String>('linkedBy', linkedBy),
    ]) {
      _hostedId(entry.value, 'HostedWorkspaceLink.${entry.key}');
    }
    _hostedUtc(linkedAt, 'HostedWorkspaceLink.linkedAt');
  }

  final String tenantId;
  final String workspaceId;
  final String localWorkspaceId;
  final DateTime linkedAt;
  final String linkedBy;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'localWorkspaceId': localWorkspaceId,
    'linkedAt': linkedAt.toIso8601String(),
    'linkedBy': linkedBy,
  };

  factory HostedWorkspaceLink.fromJson(Object? value) {
    final json = _hostedObject(value, 'HostedWorkspaceLink');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'localWorkspaceId',
      'linkedAt',
      'linkedBy',
    }, 'HostedWorkspaceLink');
    return HostedWorkspaceLink(
      tenantId: _hostedString(json, 'tenantId', 'HostedWorkspaceLink'),
      workspaceId: _hostedString(json, 'workspaceId', 'HostedWorkspaceLink'),
      localWorkspaceId: _hostedString(
        json,
        'localWorkspaceId',
        'HostedWorkspaceLink',
      ),
      linkedAt: _hostedDate(json, 'linkedAt', 'HostedWorkspaceLink'),
      linkedBy: _hostedString(json, 'linkedBy', 'HostedWorkspaceLink'),
    );
  }
}

final class WorkspaceRevision {
  WorkspaceRevision({
    required this.tenantId,
    required this.workspaceId,
    required this.id,
    required this.contentDigest,
    required this.changeSetDigest,
    required this.createdAt,
    required this.createdBy,
    this.parentDigest,
  }) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('workspaceId', workspaceId),
      MapEntry<String, String>('id', id),
      MapEntry<String, String>('createdBy', createdBy),
    ]) {
      _hostedId(entry.value, 'WorkspaceRevision.${entry.key}');
    }
    _hostedUtc(createdAt, 'WorkspaceRevision.createdAt');
  }

  final String tenantId;
  final String workspaceId;
  final String id;
  final Digest contentDigest;
  final Digest changeSetDigest;
  final Digest? parentDigest;
  final DateTime createdAt;
  final String createdBy;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'id': id,
    'contentDigest': contentDigest.value,
    'changeSetDigest': changeSetDigest.value,
    if (parentDigest != null) 'parentDigest': parentDigest!.value,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
  };

  factory WorkspaceRevision.fromJson(Object? value) {
    final json = _hostedObject(value, 'WorkspaceRevision');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'id',
      'contentDigest',
      'changeSetDigest',
      'parentDigest',
      'createdAt',
      'createdBy',
    }, 'WorkspaceRevision');
    return WorkspaceRevision(
      tenantId: _hostedString(json, 'tenantId', 'WorkspaceRevision'),
      workspaceId: _hostedString(json, 'workspaceId', 'WorkspaceRevision'),
      id: _hostedString(json, 'id', 'WorkspaceRevision'),
      contentDigest: Digest(
        _hostedString(json, 'contentDigest', 'WorkspaceRevision'),
      ),
      changeSetDigest: Digest(
        _hostedString(json, 'changeSetDigest', 'WorkspaceRevision'),
      ),
      parentDigest: json['parentDigest'] == null
          ? null
          : Digest(_hostedString(json, 'parentDigest', 'WorkspaceRevision')),
      createdAt: _hostedDate(json, 'createdAt', 'WorkspaceRevision'),
      createdBy: _hostedString(json, 'createdBy', 'WorkspaceRevision'),
    );
  }
}

final class WorkspaceChangeSet {
  WorkspaceChangeSet({
    required this.tenantId,
    required this.workspaceId,
    required this.baseDigest,
    required this.expectedDigest,
    required this.proposedDigest,
    required this.principalId,
    required this.idempotencyKey,
    required Map<String, Object?> metadata,
  }) : metadata = Map<String, Object?>.unmodifiable(metadata) {
    _hostedId(tenantId, 'WorkspaceChangeSet.tenantId');
    _hostedId(workspaceId, 'WorkspaceChangeSet.workspaceId');
    _hostedId(principalId, 'WorkspaceChangeSet.principalId');
    _hostedId(idempotencyKey, 'WorkspaceChangeSet.idempotencyKey');
    _hostedJson(this.metadata, 'WorkspaceChangeSet.metadata');
  }

  final String tenantId;
  final String workspaceId;
  final Digest baseDigest;
  final Digest expectedDigest;
  final Digest proposedDigest;
  final String principalId;
  final String idempotencyKey;
  final Map<String, Object?> metadata;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'baseDigest': baseDigest.value,
    'expectedDigest': expectedDigest.value,
    'proposedDigest': proposedDigest.value,
    'principalId': principalId,
    'idempotencyKey': idempotencyKey,
    'metadata': metadata,
  };

  factory WorkspaceChangeSet.fromJson(Object? value) {
    final json = _hostedObject(value, 'WorkspaceChangeSet');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'baseDigest',
      'expectedDigest',
      'proposedDigest',
      'principalId',
      'idempotencyKey',
      'metadata',
    }, 'WorkspaceChangeSet');
    return WorkspaceChangeSet(
      tenantId: _hostedString(json, 'tenantId', 'WorkspaceChangeSet'),
      workspaceId: _hostedString(json, 'workspaceId', 'WorkspaceChangeSet'),
      baseDigest: Digest(
        _hostedString(json, 'baseDigest', 'WorkspaceChangeSet'),
      ),
      expectedDigest: Digest(
        _hostedString(json, 'expectedDigest', 'WorkspaceChangeSet'),
      ),
      proposedDigest: Digest(
        _hostedString(json, 'proposedDigest', 'WorkspaceChangeSet'),
      ),
      principalId: _hostedString(json, 'principalId', 'WorkspaceChangeSet'),
      idempotencyKey: _hostedString(
        json,
        'idempotencyKey',
        'WorkspaceChangeSet',
      ),
      metadata: _hostedJsonMap(json['metadata'], 'WorkspaceChangeSet.metadata'),
    );
  }
}

final class WorkspaceConflict {
  WorkspaceConflict({
    required this.tenantId,
    required this.workspaceId,
    required this.baseDigest,
    required this.currentDigest,
    required this.proposedDigest,
  }) {
    _hostedId(tenantId, 'WorkspaceConflict.tenantId');
    _hostedId(workspaceId, 'WorkspaceConflict.workspaceId');
  }

  final String tenantId;
  final String workspaceId;
  final Digest baseDigest;
  final Digest currentDigest;
  final Digest proposedDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'baseDigest': baseDigest.value,
    'currentDigest': currentDigest.value,
    'proposedDigest': proposedDigest.value,
  };

  factory WorkspaceConflict.fromJson(Object? value) {
    final json = _hostedObject(value, 'WorkspaceConflict');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'baseDigest',
      'currentDigest',
      'proposedDigest',
    }, 'WorkspaceConflict');
    return WorkspaceConflict(
      tenantId: _hostedString(json, 'tenantId', 'WorkspaceConflict'),
      workspaceId: _hostedString(json, 'workspaceId', 'WorkspaceConflict'),
      baseDigest: Digest(
        _hostedString(json, 'baseDigest', 'WorkspaceConflict'),
      ),
      currentDigest: Digest(
        _hostedString(json, 'currentDigest', 'WorkspaceConflict'),
      ),
      proposedDigest: Digest(
        _hostedString(json, 'proposedDigest', 'WorkspaceConflict'),
      ),
    );
  }
}

final class CollaborationEvent {
  CollaborationEvent({
    required this.tenantId,
    required this.workspaceId,
    required this.sequence,
    required this.kind,
    required this.subjectDigest,
    required this.principalId,
    required this.occurredAt,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload) {
    _hostedId(tenantId, 'CollaborationEvent.tenantId');
    _hostedId(workspaceId, 'CollaborationEvent.workspaceId');
    _hostedId(principalId, 'CollaborationEvent.principalId');
    if (sequence < 1) {
      throw const FormatException('CollaborationEvent.sequence is invalid');
    }
    _hostedUtc(occurredAt, 'CollaborationEvent.occurredAt');
    _hostedJson(this.payload, 'CollaborationEvent.payload');
  }

  final String tenantId;
  final String workspaceId;
  final int sequence;
  final CollaborationEventKind kind;
  final Digest subjectDigest;
  final String principalId;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'sequence': sequence,
    'kind': kind.name,
    'subjectDigest': subjectDigest.value,
    'principalId': principalId,
    'occurredAt': occurredAt.toIso8601String(),
    'payload': payload,
  };

  factory CollaborationEvent.fromJson(Object? value) {
    final json = _hostedObject(value, 'CollaborationEvent');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'sequence',
      'kind',
      'subjectDigest',
      'principalId',
      'occurredAt',
      'payload',
    }, 'CollaborationEvent');
    return CollaborationEvent(
      tenantId: _hostedString(json, 'tenantId', 'CollaborationEvent'),
      workspaceId: _hostedString(json, 'workspaceId', 'CollaborationEvent'),
      sequence: _hostedInt(json, 'sequence', 'CollaborationEvent'),
      kind: _hostedEnum(
        CollaborationEventKind.values,
        _hostedString(json, 'kind', 'CollaborationEvent'),
        'CollaborationEvent.kind',
      ),
      subjectDigest: Digest(
        _hostedString(json, 'subjectDigest', 'CollaborationEvent'),
      ),
      principalId: _hostedString(json, 'principalId', 'CollaborationEvent'),
      occurredAt: _hostedDate(json, 'occurredAt', 'CollaborationEvent'),
      payload: _hostedJsonMap(json['payload'], 'CollaborationEvent.payload'),
    );
  }
}

final class PresenceLease {
  PresenceLease({
    required this.tenantId,
    required this.workspaceId,
    required this.principalId,
    required this.sessionId,
    required this.expiresAt,
  }) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('workspaceId', workspaceId),
      MapEntry<String, String>('principalId', principalId),
      MapEntry<String, String>('sessionId', sessionId),
    ]) {
      _hostedId(entry.value, 'PresenceLease.${entry.key}');
    }
    _hostedUtc(expiresAt, 'PresenceLease.expiresAt');
  }

  final String tenantId;
  final String workspaceId;
  final String principalId;
  final String sessionId;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'principalId': principalId,
    'sessionId': sessionId,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory PresenceLease.fromJson(Object? value) {
    final json = _hostedObject(value, 'PresenceLease');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'principalId',
      'sessionId',
      'expiresAt',
    }, 'PresenceLease');
    return PresenceLease(
      tenantId: _hostedString(json, 'tenantId', 'PresenceLease'),
      workspaceId: _hostedString(json, 'workspaceId', 'PresenceLease'),
      principalId: _hostedString(json, 'principalId', 'PresenceLease'),
      sessionId: _hostedString(json, 'sessionId', 'PresenceLease'),
      expiresAt: _hostedDate(json, 'expiresAt', 'PresenceLease'),
    );
  }
}

final class CommentEntry {
  CommentEntry({
    required this.id,
    required this.principalId,
    required this.body,
    required this.createdAt,
  }) {
    _hostedId(id, 'CommentEntry.id');
    _hostedId(principalId, 'CommentEntry.principalId');
    _hostedText(body, 'CommentEntry.body', maximum: 16000);
    _hostedUtc(createdAt, 'CommentEntry.createdAt');
  }

  final String id;
  final String principalId;
  final String body;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'principalId': principalId,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CommentEntry.fromJson(Object? value) {
    final json = _hostedObject(value, 'CommentEntry');
    _hostedOnly(json, const <String>{
      'id',
      'principalId',
      'body',
      'createdAt',
    }, 'CommentEntry');
    return CommentEntry(
      id: _hostedString(json, 'id', 'CommentEntry'),
      principalId: _hostedString(json, 'principalId', 'CommentEntry'),
      body: _hostedString(json, 'body', 'CommentEntry'),
      createdAt: _hostedDate(json, 'createdAt', 'CommentEntry'),
    );
  }
}

final class CommentThread {
  CommentThread({
    required this.tenantId,
    required this.workspaceId,
    required this.id,
    required this.subjectDigest,
    required List<CommentEntry> comments,
    required this.resolved,
  }) : comments = List<CommentEntry>.unmodifiable(comments) {
    _hostedId(tenantId, 'CommentThread.tenantId');
    _hostedId(workspaceId, 'CommentThread.workspaceId');
    _hostedId(id, 'CommentThread.id');
    if (this.comments.isEmpty ||
        this.comments.map((item) => item.id).toSet().length !=
            this.comments.length) {
      throw const FormatException('CommentThread.comments is invalid');
    }
  }

  final String tenantId;
  final String workspaceId;
  final String id;
  final Digest subjectDigest;
  final List<CommentEntry> comments;
  final bool resolved;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'workspaceId': workspaceId,
    'id': id,
    'subjectDigest': subjectDigest.value,
    'comments': <Object?>[for (final comment in comments) comment.toJson()],
    'resolved': resolved,
  };

  factory CommentThread.fromJson(Object? value) {
    final json = _hostedObject(value, 'CommentThread');
    _hostedOnly(json, const <String>{
      'tenantId',
      'workspaceId',
      'id',
      'subjectDigest',
      'comments',
      'resolved',
    }, 'CommentThread');
    return CommentThread(
      tenantId: _hostedString(json, 'tenantId', 'CommentThread'),
      workspaceId: _hostedString(json, 'workspaceId', 'CommentThread'),
      id: _hostedString(json, 'id', 'CommentThread'),
      subjectDigest: Digest(
        _hostedString(json, 'subjectDigest', 'CommentThread'),
      ),
      comments: _hostedList(
        json['comments'],
        'CommentThread.comments',
      ).map(CommentEntry.fromJson).toList(growable: false),
      resolved: _hostedBool(json, 'resolved', 'CommentThread'),
    );
  }
}

final class AuditEvent {
  AuditEvent({
    required this.tenantId,
    required this.id,
    required this.principalId,
    required this.action,
    required this.subjectDigest,
    required this.occurredAt,
    required Map<String, Object?> context,
  }) : context = Map<String, Object?>.unmodifiable(context) {
    _hostedId(tenantId, 'AuditEvent.tenantId');
    _hostedId(id, 'AuditEvent.id');
    _hostedId(principalId, 'AuditEvent.principalId');
    if (!RegExp(r'^[a-z][a-z0-9.-]{2,127}$').hasMatch(action)) {
      throw const FormatException('AuditEvent.action is invalid');
    }
    _hostedUtc(occurredAt, 'AuditEvent.occurredAt');
    _hostedJson(this.context, 'AuditEvent.context');
  }

  final String tenantId;
  final String id;
  final String principalId;
  final String action;
  final Digest subjectDigest;
  final DateTime occurredAt;
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'id': id,
    'principalId': principalId,
    'action': action,
    'subjectDigest': subjectDigest.value,
    'occurredAt': occurredAt.toIso8601String(),
    'context': context,
  };

  factory AuditEvent.fromJson(Object? value) {
    final json = _hostedObject(value, 'AuditEvent');
    _hostedOnly(json, const <String>{
      'tenantId',
      'id',
      'principalId',
      'action',
      'subjectDigest',
      'occurredAt',
      'context',
    }, 'AuditEvent');
    return AuditEvent(
      tenantId: _hostedString(json, 'tenantId', 'AuditEvent'),
      id: _hostedString(json, 'id', 'AuditEvent'),
      principalId: _hostedString(json, 'principalId', 'AuditEvent'),
      action: _hostedString(json, 'action', 'AuditEvent'),
      subjectDigest: Digest(_hostedString(json, 'subjectDigest', 'AuditEvent')),
      occurredAt: _hostedDate(json, 'occurredAt', 'AuditEvent'),
      context: _hostedJsonMap(json['context'], 'AuditEvent.context'),
    );
  }
}

final class IdempotencyRecord {
  IdempotencyRecord({
    required this.tenantId,
    required this.principalId,
    required this.key,
    required this.requestDigest,
    required this.responseDigest,
    required this.createdAt,
    required this.expiresAt,
  }) {
    _hostedId(tenantId, 'IdempotencyRecord.tenantId');
    _hostedId(principalId, 'IdempotencyRecord.principalId');
    _hostedId(key, 'IdempotencyRecord.key');
    _hostedUtc(createdAt, 'IdempotencyRecord.createdAt');
    _hostedUtc(expiresAt, 'IdempotencyRecord.expiresAt');
    if (!expiresAt.isAfter(createdAt)) {
      throw const FormatException('IdempotencyRecord expiry is invalid');
    }
  }

  final String tenantId;
  final String principalId;
  final String key;
  final Digest requestDigest;
  final Digest responseDigest;
  final DateTime createdAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'principalId': principalId,
    'key': key,
    'requestDigest': requestDigest.value,
    'responseDigest': responseDigest.value,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory IdempotencyRecord.fromJson(Object? value) {
    final json = _hostedObject(value, 'IdempotencyRecord');
    _hostedOnly(json, const <String>{
      'tenantId',
      'principalId',
      'key',
      'requestDigest',
      'responseDigest',
      'createdAt',
      'expiresAt',
    }, 'IdempotencyRecord');
    return IdempotencyRecord(
      tenantId: _hostedString(json, 'tenantId', 'IdempotencyRecord'),
      principalId: _hostedString(json, 'principalId', 'IdempotencyRecord'),
      key: _hostedString(json, 'key', 'IdempotencyRecord'),
      requestDigest: Digest(
        _hostedString(json, 'requestDigest', 'IdempotencyRecord'),
      ),
      responseDigest: Digest(
        _hostedString(json, 'responseDigest', 'IdempotencyRecord'),
      ),
      createdAt: _hostedDate(json, 'createdAt', 'IdempotencyRecord'),
      expiresAt: _hostedDate(json, 'expiresAt', 'IdempotencyRecord'),
    );
  }
}

final class HostedBlobDescriptor {
  HostedBlobDescriptor({
    required this.tenantId,
    required this.digest,
    required this.size,
    required this.mediaType,
    required this.classification,
    required this.objectKey,
  }) {
    _hostedId(tenantId, 'HostedBlobDescriptor.tenantId');
    if (size < 0 || size > 1024 * 1024 * 1024) {
      throw const FormatException('HostedBlobDescriptor.size is invalid');
    }
    _hostedText(mediaType, 'HostedBlobDescriptor.mediaType', maximum: 255);
    if (!const <String>{
      'public',
      'internal',
      'sensitive',
    }.contains(classification)) {
      throw const FormatException(
        'HostedBlobDescriptor.classification is invalid',
      );
    }
    if (objectKey !=
        'tenants/$tenantId/blobs/sha256/${digest.value.substring(7)}') {
      throw const FormatException(
        'HostedBlobDescriptor.objectKey is not tenant scoped',
      );
    }
  }

  final String tenantId;
  final Digest digest;
  final int size;
  final String mediaType;
  final String classification;
  final String objectKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'digest': digest.value,
    'size': size,
    'mediaType': mediaType,
    'classification': classification,
    'objectKey': objectKey,
  };

  factory HostedBlobDescriptor.fromJson(Object? value) {
    final json = _hostedObject(value, 'HostedBlobDescriptor');
    _hostedOnly(json, const <String>{
      'tenantId',
      'digest',
      'size',
      'mediaType',
      'classification',
      'objectKey',
    }, 'HostedBlobDescriptor');
    return HostedBlobDescriptor(
      tenantId: _hostedString(json, 'tenantId', 'HostedBlobDescriptor'),
      digest: Digest(_hostedString(json, 'digest', 'HostedBlobDescriptor')),
      size: _hostedInt(json, 'size', 'HostedBlobDescriptor'),
      mediaType: _hostedString(json, 'mediaType', 'HostedBlobDescriptor'),
      classification: _hostedString(
        json,
        'classification',
        'HostedBlobDescriptor',
      ),
      objectKey: _hostedString(json, 'objectKey', 'HostedBlobDescriptor'),
    );
  }
}

Map<String, Object?> _hostedObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _hostedOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _hostedString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a string');
  }
  return value;
}

int _hostedInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

bool _hostedBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

DateTime _hostedDate(Map<String, Object?> json, String key, String path) {
  final parsed = DateTime.tryParse(_hostedString(json, key, path));
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$path.$key must be UTC');
  }
  return parsed;
}

List<Object?> _hostedList(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be an array');
  return value;
}

Map<String, Object?> _hostedJsonMap(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  _hostedJson(value, path);
  return value;
}

T _hostedEnum<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path is invalid');
}

void _hostedId(String value, String path) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$').hasMatch(value)) {
    throw FormatException('$path is invalid');
  }
}

void _hostedText(String value, String path, {required int maximum}) {
  if (value.isEmpty || value.length > maximum || value.contains('\u0000')) {
    throw FormatException('$path is invalid');
  }
}

void _hostedUtc(DateTime value, String path) {
  if (!value.isUtc) throw ArgumentError('$path must be UTC');
}

void _hostedJson(Object? value, String path) {
  final canonical = const JcsCanonicalizer().canonicalize(value);
  if (canonical.length > 64 * 1024) {
    throw FormatException('$path exceeds the canonical size limit');
  }
}
