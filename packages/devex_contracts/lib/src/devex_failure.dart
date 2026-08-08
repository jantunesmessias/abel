enum FailureCategory {
  authoringValidation,
  incompatibility,
  capabilityMissing,
  precondition,
  timeout,
  consumerFailure,
  targetFailure,
  transportFailure,
  gatewayResolution,
  upstreamUnavailable,
  policyDenied,
  internal,
}

enum Recoverability { none, retry, reset, userAction }

final class DevExFailure {
  const DevExFailure({
    required this.code,
    required this.category,
    required this.message,
    required this.recoverability,
    this.context = const <String, String>{},
  });

  final String code;
  final FailureCategory category;
  final String message;
  final Recoverability recoverability;
  final Map<String, String> context;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'category': category.name,
    'message': message,
    'recoverability': recoverability.name,
    if (context.isNotEmpty) 'context': context,
  };
}
