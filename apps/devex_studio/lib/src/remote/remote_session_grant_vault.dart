import 'package:devex_contracts/devex_contracts.dart';

final class RemoteSessionGrantVault {
  RemoteSessionGrantVault({DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final DateTime Function() _nowUtc;
  final Map<String, RemoteSessionGrant> _grants =
      <String, RemoteSessionGrant>{};

  void stage(RemoteSessionGrant grant) {
    if (!grant.expiresAt.isAfter(_nowUtc()) ||
        _grants.containsKey(grant.runId)) {
      throw StateError('remote session grant is expired or already staged');
    }
    _grants[grant.runId] = grant;
  }

  RemoteSessionGrant? take(String runId) {
    final grant = _grants.remove(runId);
    if (grant == null || !grant.expiresAt.isAfter(_nowUtc())) return null;
    return grant;
  }

  void clear() => _grants.clear();
}
