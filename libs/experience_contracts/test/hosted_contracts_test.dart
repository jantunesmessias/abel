import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 12);
  final subject = Digest.semantic('subject');
  final change = WorkspaceChangeSet(
    tenantId: 'tenant-a',
    workspaceId: 'workspace-a',
    baseDigest: Digest.semantic('base'),
    expectedDigest: Digest.semantic('base'),
    proposedDigest: Digest.semantic('proposal'),
    principalId: 'principal-a',
    idempotencyKey: 'idempotency-001',
    metadata: const <String, Object?>{'channel': 'test'},
  );
  final revision = WorkspaceRevision(
    tenantId: 'tenant-a',
    workspaceId: 'workspace-a',
    id: 'revision-001',
    contentDigest: change.proposedDigest,
    changeSetDigest: change.digest,
    parentDigest: change.expectedDigest,
    createdAt: now,
    createdBy: 'principal-a',
  );

  test('hosted documents round-trip through their closed public schema', () {
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _root(),
                'schemas/hosted/hosted-collaboration.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    final documents = <Map<String, Object?>>[
      Principal(
        id: 'principal-a',
        issuer: 'https://identity.example.test',
        subject: 'subject-a',
        displayName: 'Example Reviewer',
      ).toJson(),
      Organization(
        tenantId: 'tenant-a',
        slug: 'tenant-a',
        displayName: 'Example Organization',
        createdAt: now,
      ).toJson(),
      Membership(
        tenantId: 'tenant-a',
        principalId: 'principal-a',
        role: MembershipRole.editor,
        createdAt: now,
      ).toJson(),
      HostedWorkspaceLink(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        localWorkspaceId: 'local-workspace-a',
        linkedAt: now,
        linkedBy: 'principal-a',
      ).toJson(),
      revision.toJson(),
      change.toJson(),
      WorkspaceConflict(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        baseDigest: change.baseDigest,
        currentDigest: revision.digest,
        proposedDigest: change.proposedDigest,
      ).toJson(),
      CollaborationEvent(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        sequence: 1,
        kind: CollaborationEventKind.workspacePushed,
        subjectDigest: revision.digest,
        principalId: 'principal-a',
        occurredAt: now,
        payload: <String, Object?>{'revisionDigest': revision.digest.value},
      ).toJson(),
      PresenceLease(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        principalId: 'principal-a',
        sessionId: 'session-001',
        expiresAt: now.add(const Duration(minutes: 1)),
      ).toJson(),
      CommentThread(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        id: 'thread-001',
        subjectDigest: subject,
        comments: <CommentEntry>[
          CommentEntry(
            id: 'comment-001',
            principalId: 'principal-a',
            body: 'Reviewed.',
            createdAt: now,
          ),
        ],
        resolved: false,
      ).toJson(),
      AuditEvent(
        tenantId: 'tenant-a',
        id: 'audit-001',
        principalId: 'principal-a',
        action: 'workspace.push',
        subjectDigest: revision.digest,
        occurredAt: now,
        context: const <String, Object?>{'correlationId': 'correlation-001'},
      ).toJson(),
      IdempotencyRecord(
        tenantId: 'tenant-a',
        principalId: 'principal-a',
        key: 'idempotency-001',
        requestDigest: change.digest,
        responseDigest: revision.digest,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
      ).toJson(),
      HostedBlobDescriptor(
        tenantId: 'tenant-a',
        digest: subject,
        size: 7,
        mediaType: 'application/octet-stream',
        classification: 'internal',
        objectKey:
            'tenants/tenant-a/blobs/sha256/${subject.value.substring(7)}',
      ).toJson(),
    ];
    for (final document in documents) {
      expect(validator.validate(document).isValid, isTrue, reason: '$document');
    }
    expect(WorkspaceChangeSet.fromJson(change.toJson()).digest, change.digest);
    expect(
      WorkspaceRevision.fromJson(revision.toJson()).digest,
      revision.digest,
    );
  });

  test('tenant-scoped object keys and strict fields fail closed', () {
    expect(
      () => HostedBlobDescriptor(
        tenantId: 'tenant-a',
        digest: subject,
        size: 7,
        mediaType: 'application/octet-stream',
        classification: 'internal',
        objectKey:
            'tenants/tenant-b/blobs/sha256/${subject.value.substring(7)}',
      ),
      throwsFormatException,
    );
    expect(
      () => WorkspaceChangeSet.fromJson(change.toJson()..['unknown'] = true),
      throwsFormatException,
    );
  });
}

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
