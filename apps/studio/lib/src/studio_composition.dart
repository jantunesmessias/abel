import 'package:experience_contracts/experience_contracts.dart';

final class StudioComposition {
  StudioComposition({
    required this.planDigest,
    required Iterable<String> contributions,
  }) : contributions = Set<String>.unmodifiable(contributions);

  factory StudioComposition.fromManifest(EffectiveKitManifest manifest) =>
      StudioComposition(
        planDigest: manifest.resolvedPlanDigest,
        contributions: manifest.studioContributions,
      );

  final Digest planDigest;
  final Set<String> contributions;

  bool get shellEnabled => contributions.contains('studio.shell');
  bool get authoringEnabled => contributions.contains('studio.authoring');
  bool get motionEnabled => contributions.contains('studio.motion');
  bool get contextEnabled => contributions.contains('studio.context');
  bool get journeyMapEnabled => contributions.contains('studio.journey-map');
  bool get inventoryEnabled => contributions.contains('studio.inventory');
  bool get labEnabled => contributions.contains('studio.lab');
  bool get qualityEnabled => contributions.contains('studio.quality');
  bool get targetEnabled => contributions.contains('studio.target');
  bool get gatewayEnabled => contributions.contains('studio.gateway');
  bool get remoteSessionEnabled =>
      contributions.contains('studio.remote-session');
  bool get hostedEnabled => contributions.contains('studio.hosted');
}
