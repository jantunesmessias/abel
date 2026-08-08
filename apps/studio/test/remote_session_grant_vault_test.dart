import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/remote/remote_session_grant_vault.dart';
import 'package:test/test.dart';

void main() {
  test('staged grants are unexpired, unique, and consumed exactly once', () {
    var now = DateTime.utc(2026, 8, 9, 12);
    final vault = RemoteSessionGrantVault(nowUtc: () => now);
    final grant = _grant(expiresAt: now.add(const Duration(minutes: 5)));

    vault.stage(grant);
    expect(() => vault.stage(grant), throwsStateError);
    expect(vault.take(grant.runId), same(grant));
    expect(vault.take(grant.runId), isNull);

    final expiring = _grant(
      runId: 'run-expiring',
      expiresAt: now.add(const Duration(seconds: 1)),
    );
    vault.stage(expiring);
    now = now.add(const Duration(seconds: 1));
    expect(vault.take(expiring.runId), isNull);
    expect(
      () => vault.stage(_grant(runId: 'run-expired', expiresAt: now)),
      throwsStateError,
    );
  });
}

RemoteSessionGrant _grant({
  String runId = 'run-001',
  required DateTime expiresAt,
}) => RemoteSessionGrant(
  runId: runId,
  endpoint: Uri.parse('wss://gateway.example.test/v1/sessions/$runId/viewer'),
  compactTicket: 'signed-viewer-ticket',
  allowedTransports: const <RemoteInteractiveTransport>{
    RemoteInteractiveTransport.webDirect,
  },
  expiresAt: expiresAt,
);
