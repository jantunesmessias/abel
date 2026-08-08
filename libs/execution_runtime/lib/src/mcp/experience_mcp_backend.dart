abstract interface class ExperienceMcpBackend {
  List<Map<String, Object?>> get tools;

  List<Map<String, Object?>> get resources;

  Future<Object?> call({
    required String name,
    required Map<String, Object?> arguments,
    required String principalId,
    required String connectionEpoch,
  });

  Future<Object?> readResource({
    required String uri,
    required String principalId,
  });

  Future<void> close({required String connectionEpoch});
}

final class ExperienceMcpToolException implements Exception {
  const ExperienceMcpToolException(this.code, {this.details});

  final String code;
  final Object? details;
}
