import 'package:experience_contracts/experience_contracts.dart';

final class WorkspaceConnectionState {
  const WorkspaceConnectionState({
    required this.connected,
    this.isStale = false,
    this.message,
  });

  const WorkspaceConnectionState.unavailable()
    : connected = false,
      isStale = false,
      message = null;

  final bool connected;
  final bool isStale;
  final String? message;
}

final class StudioWorkspaceState {
  const StudioWorkspaceState({
    required this.connection,
    this.snapshot,
    this.experienceBundle,
    this.scenarioFacets,
    this.scenarioLab,
    this.motion,
    this.contentIdentity,
    this.failureMessage,
    this.isConnecting = false,
  }) : assert(experienceBundle == null || snapshot != null),
       assert(scenarioFacets == null || snapshot != null),
       assert(scenarioLab == null || snapshot != null),
       assert(motion == null || snapshot != null),
       assert(contentIdentity == null || snapshot != null),
       assert(scenarioLab == null || contentIdentity != null),
       assert(motion == null || contentIdentity != null);

  const StudioWorkspaceState.initial()
    : connection = const WorkspaceConnectionState.unavailable(),
      snapshot = null,
      experienceBundle = null,
      scenarioFacets = null,
      scenarioLab = null,
      motion = null,
      contentIdentity = null,
      failureMessage = null,
      isConnecting = false;

  final WorkspaceConnectionState connection;
  final WorkspaceSnapshot? snapshot;
  final ExperienceTopologyBundle? experienceBundle;
  final ScenarioFacetManifest? scenarioFacets;
  final ScenarioLabManifest? scenarioLab;
  final MotionManifest? motion;
  final ExperienceContentSetIdentity? contentIdentity;
  final String? failureMessage;
  final bool isConnecting;

  bool get hasSnapshot => snapshot != null;
  ExperienceTopologyBundle? get experience => experienceBundle;
  bool get hasContentGeneration => contentIdentity != null;
}
