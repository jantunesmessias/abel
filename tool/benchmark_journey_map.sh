#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

# The Jaspr benchmark uses the same authoritative Host, static distribution,
# real PNG handles and Google Chrome CDP path as the vertical gate. It measures
# the actual sample Journey instead of preserving the removed Flutter
# CustomPainter synthetic corpus. The pure-Dart window policy separately proves
# that a 10,000-item sequence keeps the canvas DOM bounded to 24 scenarios.
dart test packages/devex_ux_system/test/ux_system_test.dart \
  --plain-name 'visual canvas window remains bounded around deep selections' \
  --reporter compact >/dev/null
result="$(./tool/verify_studio_vertical.sh)"

jq -e '
  .status == "passed" and
  .browserPerformance.loadEventMs > 0 and
  .browserPerformance.loadEventMs < 5000 and
  .mapInteraction.samples == 20 and
  .mapInteraction.p95Ms > 0 and
  .mapInteraction.p95Ms < 100 and
  .browserAccessibility.semanticHtml.flutterElementCount == 0 and
  .browserAccessibility.reflow200Percent.horizontalDocumentOverflow == false
' <<<"$result" >/dev/null

jq '{
  status: "passed",
  renderer: "jaspr-html-css",
  corpus: "sample-authoritative-journey-plus-10000-item-window-policy",
  browserPerformance,
  mapInteraction,
  reflow200Percent: .browserAccessibility.reflow200Percent,
  limitations: [
    "Browser timing covers the authoritative sample Journey; the 10,000-item bound is verified independently by the pure-Dart policy test.",
    "The Outline remains complete while the canvas DOM is capped at 24 scenarios."
  ]
}' <<<"$result"
