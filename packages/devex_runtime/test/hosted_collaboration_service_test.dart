import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryHostedCollaborationRepository repository;
  late _FakeClock clock;
  late HostedCollaborationService service;
  final base = Digest.semantic('base');

  test('hosted role matrix preserves least privilege and admin authority', () {
    const policy = HostedAuthorizationPolicy();
    expect(
      HostedPermission.values.every(
        (permission) => policy.allows(MembershipRole.owner, permission),
      ),
      isTrue,
    );
    expect(
      HostedPermission.values.every(
        (permission) => policy.allows(MembershipRole.admin, permission),
      ),
      isTrue,
    );
    expect(policy.allows(MembershipRole.editor, HostedPermission.push), isTrue);
    expect(
      policy.allows(MembershipRole.editor, HostedPermission.approve),
      isFalse,
    );
    expect(
      policy.allows(MembershipRole.reviewer, HostedPermission.approve),
      isTrue,
    );
    expect(
      policy.allows(MembershipRole.reviewer, HostedPermission.publish),
      isFalse,
    );
    expect(
      HostedPermission.values
          .where((permission) => permission != HostedPermission.read)
          .every(
            (permission) => !policy.allows(MembershipRole.viewer, permission),
          ),
      isTrue,
    );
  });

  setUp(() {
    repository = InMemoryHostedCollaborationRepository();
    clock = _FakeClock(DateTime.utc(2026, 8, 9, 12));
    service = HostedCollaborationService(
      repository: repository,
      clock: clock,
      ids: _SequentialIds(),
    );
    for (final membership in <Membership>[
      _membership('tenant-a', 'editor-a', MembershipRole.editor),
      _membership('tenant-a', 'reviewer-a', MembershipRole.reviewer),
      _membership('tenant-a', 'viewer-a', MembershipRole.viewer),
      _membership('tenant-b', 'editor-b', MembershipRole.editor),
    ]) {
      repository.seedMembership(membership);
    }
    repository
      ..seedWorkspaceHead(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        digest: base,
      )
      ..seedWorkspaceHead(
        tenantId: 'tenant-b',
        workspaceId: 'workspace-a',
        digest: base,
      );
  });

  test(
    'push is atomic, idempotent, and conflicts without overwriting',
    () async {
      final context = _context('tenant-a', 'editor-a');
      final change = _change(
        context,
        expected: base,
        proposed: Digest.semantic('proposal-a'),
        key: 'idem-001',
      );
      final first = await service.push(context, change);
      expect(first, isA<WorkspacePushAccepted>());
      final accepted = first as WorkspacePushAccepted;
      expect(accepted.replayed, isFalse);

      final replayed = await service.push(context, change);
      expect((replayed as WorkspacePushAccepted).replayed, isTrue);
      expect(replayed.revision.digest, accepted.revision.digest);

      final conflict = await service.push(
        context,
        _change(
          context,
          expected: base,
          proposed: Digest.semantic('proposal-b'),
          key: 'idem-002',
        ),
      );
      expect(conflict, isA<WorkspacePushRejected>());
      final rejected = conflict as WorkspacePushRejected;
      expect(rejected.conflict.baseDigest, base);
      expect(rejected.conflict.currentDigest, accepted.revision.digest);
      expect(rejected.conflict.proposedDigest, Digest.semantic('proposal-b'));
      expect(
        repository.workspaceHead('tenant-a', 'workspace-a'),
        accepted.revision.digest,
      );
      expect(repository.auditForTenant('tenant-a'), hasLength(1));
    },
  );

  test(
    'tenant scope is enforced on payload, storage, and replay cursor',
    () async {
      final contextA = _context('tenant-a', 'editor-a');
      final contextB = _context('tenant-b', 'editor-b');
      await service.push(
        contextA,
        _change(
          contextA,
          expected: base,
          proposed: Digest.semantic('tenant-a-data'),
          key: 'idem-a01',
        ),
      );
      await service.push(
        contextB,
        _change(
          contextB,
          expected: base,
          proposed: Digest.semantic('tenant-b-data'),
          key: 'idem-b01',
        ),
      );
      final eventsA = await service.replay(
        contextA,
        workspaceId: 'workspace-a',
        afterSequence: 0,
      );
      final eventsB = await service.replay(
        contextB,
        workspaceId: 'workspace-a',
        afterSequence: 0,
      );
      expect(eventsA, hasLength(1));
      expect(eventsB, hasLength(1));
      expect(eventsA.single.tenantId, 'tenant-a');
      expect(eventsB.single.tenantId, 'tenant-b');
      expect(eventsA.single.subjectDigest, isNot(eventsB.single.subjectDigest));
      expect(
        await service.replay(
          contextA,
          workspaceId: 'workspace-a',
          afterSequence: eventsA.single.sequence,
        ),
        isEmpty,
      );

      expect(
        () => service.push(
          contextA,
          _change(
            contextB,
            expected: base,
            proposed: Digest.semantic('cross-tenant'),
            key: 'idem-x01',
          ),
        ),
        throwsA(isA<HostedAuthorizationException>()),
      );
    },
  );

  test('roles, presence TTL, comments, and approvals are explicit', () async {
    final viewer = _context('tenant-a', 'viewer-a');
    expect(
      () => service.push(
        viewer,
        _change(
          viewer,
          expected: base,
          proposed: Digest.semantic('forbidden'),
          key: 'idem-v01',
        ),
      ),
      throwsA(isA<HostedAuthorizationException>()),
    );
    final lease = await service.heartbeat(
      viewer,
      workspaceId: 'workspace-a',
      sessionId: 'session-001',
    );
    expect(await service.presence(viewer, workspaceId: 'workspace-a'), [lease]);
    clock.advance(const Duration(seconds: 61));
    expect(await service.presence(viewer, workspaceId: 'workspace-a'), isEmpty);

    final reviewer = _context('tenant-a', 'reviewer-a');
    final subject = Digest.semantic('release');
    final thread = await service.comment(
      reviewer,
      workspaceId: 'workspace-a',
      subjectDigest: subject,
      body: 'Evidence reviewed.',
    );
    final approval = await service.approve(
      reviewer,
      workspaceId: 'workspace-a',
      subjectDigest: subject,
      approved: true,
    );
    expect(thread.subjectDigest, subject);
    expect(approval.subjectDigest, subject);
    final events = await service.replay(
      reviewer,
      workspaceId: 'workspace-a',
      afterSequence: 0,
    );
    expect(events.map((event) => event.kind), <CollaborationEventKind>[
      CollaborationEventKind.commentAdded,
      CollaborationEventKind.approvalRecorded,
    ]);
  });
}

HostedRequestContext _context(String tenant, String principal) =>
    HostedRequestContext(
      tenantId: tenant,
      principalId: principal,
      correlationId: 'correlation-001',
    );

Membership _membership(String tenant, String principal, MembershipRole role) =>
    Membership(
      tenantId: tenant,
      principalId: principal,
      role: role,
      createdAt: DateTime.utc(2026, 8, 9),
    );

WorkspaceChangeSet _change(
  HostedRequestContext context, {
  required Digest expected,
  required Digest proposed,
  required String key,
}) => WorkspaceChangeSet(
  tenantId: context.tenantId,
  workspaceId: 'workspace-a',
  baseDigest: expected,
  expectedDigest: expected,
  proposedDigest: proposed,
  principalId: context.principalId,
  idempotencyKey: key,
  metadata: const <String, Object?>{'source': 'test'},
);

final class _FakeClock implements Clock {
  _FakeClock(this.value);

  DateTime value;

  void advance(Duration duration) => value = value.add(duration);

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}

final class _SequentialIds implements IdGenerator {
  int value = 0;

  @override
  String nextId() => 'generated-${++value}';
}
