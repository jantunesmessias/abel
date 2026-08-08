import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';

/// Builds the opaque target launch location without granting relay authority.
///
/// A normal Session omits [scenarioLabRunId]. Only the Scenario Lab relay
/// mount is allowed to provide it. The caller must navigate the iframe's
/// browsing context directly; this URI must never be assigned to an iframe
/// `src` attribute because the launch context can contain Host-owned data.
Uri buildTargetFrameLaunchUri({
  required Uri targetUri,
  required String sessionId,
  required String nonce,
  required String controllerOrigin,
  Uri? gatewayOrigin,
  Uri? gatewayDataOrigin,
  String? scenarioLabRunId,
}) {
  if (scenarioLabRunId != null && scenarioLabRunId != sessionId) {
    throw ArgumentError(
      'Scenario Lab TargetFrame run must equal its session ID',
    );
  }
  if (scenarioLabRunId == null && gatewayDataOrigin != null) {
    throw ArgumentError(
      'Gateway data origin is reserved for a Scenario Lab relay',
    );
  }
  if (scenarioLabRunId != null && gatewayOrigin != null) {
    throw ArgumentError(
      'Scenario Lab relay requires gatewayDataOrigin instead of gatewayOrigin',
    );
  }
  final controllerUri = Uri.parse(controllerOrigin);
  if (gatewayDataOrigin != null && targetUri.origin == controllerUri.origin) {
    throw ArgumentError(
      'Gateway-bound relay TargetFrame must be cross-origin from Studio',
    );
  }
  final relayGatewayOrigin = gatewayDataOrigin == null
      ? null
      : canonicalScenarioLabGatewayDataOrigin(gatewayDataOrigin);
  final effectiveGatewayOrigin = scenarioLabRunId == null
      ? gatewayOrigin
      : relayGatewayOrigin;
  final launchContext = base64Url
      .encode(
        utf8.encode(
          jsonEncode(<String, String>{
            'SESSION_ID': sessionId,
            'SESSION_NONCE': nonce,
            'TARGET_CONTROLLER_ORIGIN': controllerOrigin,
            if (effectiveGatewayOrigin != null)
              'GATEWAY_ORIGIN': effectiveGatewayOrigin.toString(),
            'SCENARIO_LAB_RUN_ID': ?scenarioLabRunId,
          }),
        ),
      )
      .replaceAll('=', '');
  return targetUri.replace(fragment: 'target-launch=$launchContext');
}

/// Enforces the security-relevant iframe activation order.
///
/// Navigation is deliberately last: an app loaded from cache can emit Hello
/// immediately, so the controller and window listener must already be active.
void activateTargetFrameInOrder({
  required void Function() attachController,
  required void Function() registerAuthorizedListener,
  required void Function() navigate,
}) {
  attachController();
  registerAuthorizedListener();
  navigate();
}

/// The declarative iframe source is permanently inert and non-sensitive.
///
/// Target activation mutates the child browsing context's Location instead of
/// this content attribute. Leaving the attribute stable also prevents Jaspr
/// rerenders from navigating an already-running target.
String targetFrameRenderedSource() => 'about:blank';
