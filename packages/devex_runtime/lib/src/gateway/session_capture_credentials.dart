import 'safe_http_upstream.dart';
import 'session_capture_vault.dart';

/// Resolves the sole session credential handle against a vault entry already
/// bound to the active principal and target generation.
final class SessionCaptureCredentialResolver implements CredentialResolver {
  const SessionCaptureCredentialResolver({
    required this.vault,
    required this.captureId,
    required this.principalId,
    required this.targetId,
    required this.targetGeneration,
  });

  final SessionCaptureVault vault;
  final String captureId;
  final String principalId;
  final String targetId;
  final String targetGeneration;

  @override
  Future<CredentialValue?> resolve(String handle) async {
    if (handle != 'session:authorization') {
      throw const FormatException('Unsupported captured session handle');
    }
    final value = vault
        .resolve(
          captureId: captureId,
          principalId: principalId,
          targetId: targetId,
          targetGeneration: targetGeneration,
        )
        .value('authorization');
    return value == null ? null : CredentialValue(value);
  }
}

/// Routes credential handles without allowing one credential backend to
/// inspect or reinterpret the namespace owned by another backend.
final class NamespacedCredentialResolver implements CredentialResolver {
  const NamespacedCredentialResolver({
    required this.environment,
    required this.session,
  });

  final CredentialResolver environment;
  final CredentialResolver? session;

  @override
  Future<CredentialValue?> resolve(String handle) {
    if (handle.startsWith('env:')) return environment.resolve(handle);
    if (handle.startsWith('session:') && session != null) {
      return session!.resolve(handle);
    }
    throw const FormatException('Credential handle namespace is unavailable');
  }
}
