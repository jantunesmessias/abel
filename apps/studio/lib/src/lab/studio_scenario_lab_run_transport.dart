import 'package:experience_contracts/experience_contracts.dart';

const Set<String> studioScenarioLabRunRpcMethods = <String>{
  'lab.start',
  'lab.get',
  'lab.cancel',
  'lab.reattach',
};

enum StudioScenarioLabRunTransportAvailability { unavailable, available }

final class StudioScenarioLabRunUnavailable implements Exception {
  const StudioScenarioLabRunUnavailable();

  @override
  String toString() => 'StudioScenarioLabRunUnavailable';
}

final class StudioScenarioLabRunFencingMismatch implements Exception {
  const StudioScenarioLabRunFencingMismatch();

  @override
  String toString() => 'StudioScenarioLabRunFencingMismatch';
}

StudioScenarioLabRunTransportAvailability selectStudioScenarioLabRunTransport(
  Set<String> capabilities,
) {
  final present = capabilities.intersection(studioScenarioLabRunRpcMethods);
  if (present.isEmpty) {
    return StudioScenarioLabRunTransportAvailability.unavailable;
  }
  if (present.length != studioScenarioLabRunRpcMethods.length) {
    throw const FormatException(
      'Workspace Host exposes an incomplete Scenario Lab run capability',
    );
  }
  return StudioScenarioLabRunTransportAvailability.available;
}

Map<String, Object?> encodeStudioScenarioLabRunStart(
  ScenarioLabRunStartRequest request,
) => request.toJson();

Map<String, Object?> encodeStudioScenarioLabRunReference(
  ScenarioLabRunReference reference,
) => reference.toJson();

Map<String, Object?> encodeStudioScenarioLabRunObserve(
  ScenarioLabRunObserveRequest request,
) => request.toJson();

ScenarioLabRunSnapshot decodeStudioScenarioLabRunStart(
  Object? value,
  ScenarioLabRunStartRequest request,
) {
  final snapshot = ScenarioLabRunSnapshot.fromJson(value);
  try {
    snapshot.validateAgainstStart(request);
  } on ArgumentError {
    throw const StudioScenarioLabRunFencingMismatch();
  }
  return snapshot;
}

ScenarioLabRunSnapshot decodeStudioScenarioLabRunReferenceResponse(
  Object? value,
  ScenarioLabRunReference reference,
) {
  final snapshot = ScenarioLabRunSnapshot.fromJson(value);
  if (snapshot.runId != reference.runId) {
    throw const FormatException(
      'Scenario Lab reference response belongs to another run',
    );
  }
  return snapshot;
}

ScenarioLabRunObservation decodeStudioScenarioLabRunObservation(
  Object? value,
  ScenarioLabRunObserveRequest request,
) {
  final observation = ScenarioLabRunObservation.fromJson(value);
  if (observation.runId != request.runId ||
      observation.afterSequence != request.afterSequence ||
      observation.observations.length > request.limit) {
    throw const FormatException(
      'Scenario Lab reattach response does not bind its request',
    );
  }
  return observation;
}
