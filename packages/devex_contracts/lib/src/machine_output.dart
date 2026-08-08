import 'devex_failure.dart';

final class MachineDiagnostic {
  const MachineDiagnostic({
    required this.code,
    required this.message,
    this.context = const <String, Object?>{},
  });

  final String code;
  final String message;
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (context.isNotEmpty) 'context': context,
  };
}

final class MachineOutput {
  MachineOutput({
    required this.command,
    required this.ok,
    required this.correlationId,
    required Map<String, Object?> effectiveContext,
    required this.result,
    required List<DevExFailure> failures,
    required List<MachineDiagnostic> diagnostics,
  }) : effectiveContext = Map<String, Object?>.unmodifiable(effectiveContext),
       failures = List<DevExFailure>.unmodifiable(failures),
       diagnostics = List<MachineDiagnostic>.unmodifiable(diagnostics);

  static const int schemaVersion = 1;

  final String command;
  final bool ok;
  final String? correlationId;
  final Map<String, Object?> effectiveContext;
  final Object? result;
  final List<DevExFailure> failures;
  final List<MachineDiagnostic> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'command': command,
    'ok': ok,
    'correlationId': correlationId,
    'effectiveContext': effectiveContext,
    'result': result,
    'failures': <Object?>[for (final failure in failures) failure.toJson()],
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };
}
