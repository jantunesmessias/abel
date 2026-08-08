import 'package:devex_contracts/devex_contracts.dart';

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

  /// Compatibility surface for callers that have not negotiated a v2 Host.
  factory StudioComposition.legacy() => StudioComposition(
    planDigest: Digest.semantic(const <String, Object?>{
      'profile': 'legacy-full-local-v1',
    }),
    contributions: const <String>{
      'studio.shell',
      'studio.journey-map',
      'studio.target',
      'studio.gateway',
      'studio.remote-session',
      'studio.hosted',
    },
  );

  final Digest planDigest;
  final Set<String> contributions;

  bool get shellEnabled => contributions.contains('studio.shell');
  bool get journeyMapEnabled => contributions.contains('studio.journey-map');
  bool get targetEnabled => contributions.contains('studio.target');
  bool get gatewayEnabled => contributions.contains('studio.gateway');
  bool get remoteSessionEnabled =>
      contributions.contains('studio.remote-session');
  bool get hostedEnabled => contributions.contains('studio.hosted');
}
