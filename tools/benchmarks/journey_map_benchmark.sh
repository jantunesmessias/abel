#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"
result="$(./tools/verify/verify_scale_accessibility_security_vertical.sh)"

jq -e '
  .status == "passed" and
  .corpus.scenarioCount >= 2000 and
  .corpus.transitionCount >= 20000 and
  .measurements.totalMs > 0 and
  .measurements.totalMs <= .budgets.maxElapsedMs and
  .measurements.rssObservedBytes <= .budgets.maxRssBytes and
  .measurements.windowP95Micros <= .budgets.maxWindowP95Micros and
  .browser.domElementCount <= 5000 and
  .browser.textScale200Overflow == false and
  .browser.reducedMotion == true
' <<<"$result" >/dev/null

jq '{
  status: "passed",
  renderer: "jaspr-html-css",
  corpus,
  budgets,
  measurements,
  virtualization,
  incrementalCapture,
  descriptorBatches,
  browser,
  limitations: [
    "Timings and RSS are local observations from one Linux x64 run, not service-level objectives.",
    "The accessibility checks are automated browser evidence, not WCAG or assistive-technology certification."
  ]
}' <<<"$result"
