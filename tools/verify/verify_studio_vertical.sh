#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/studio/build/jaspr"
chrome_debug_port="${CHROME_DEBUG_PORT:-9515}"
dev_pid=""
chrome_pid=""
chrome_profile=""
studio_origin=""
host_origin=""
stale_probe=""
dev_log=""
tool_exec=()
if command -v mise >/dev/null 2>&1; then
  tool_exec=(mise exec --)
fi
inventory_screenshot_args=()
if [[ -n "${STUDIO_INVENTORY_SCREENSHOT:-}" ]]; then
  inventory_screenshot_args=(
    "--screenshot=$STUDIO_INVENTORY_SCREENSHOT"
  )
fi

cleanup_dev() {
  if [[ -n "$dev_pid" ]] && kill -0 "$dev_pid" 2>/dev/null; then
    kill -INT "$dev_pid" 2>/dev/null || true
    for _ in $(seq 1 100); do
      if ! kill -0 "$dev_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$dev_pid" 2>/dev/null; then
      kill -TERM "$dev_pid" 2>/dev/null || true
    fi
    wait "$dev_pid" 2>/dev/null || true
  fi
  dev_pid=""
}

cleanup() {
  cleanup_dev
  if [[ -n "$chrome_pid" ]] && kill -0 "$chrome_pid" 2>/dev/null; then
    kill -TERM "$chrome_pid" 2>/dev/null || true
    wait "$chrome_pid" 2>/dev/null || true
  fi
  if [[ -n "$chrome_profile" && -d "$chrome_profile" ]]; then
    case "$chrome_profile" in
      /tmp/workspace-studio-chrome.*)
        find "$chrome_profile" -depth -delete 2>/dev/null || true
        ;;
      *)
        echo "Refusing to clean unexpected Chrome profile: $chrome_profile" >&2
        ;;
    esac
  fi
  if [[ -n "$stale_probe" && -f "$stale_probe" ]]; then
    rm -f -- "$stale_probe"
  fi
  if [[ -n "$dev_log" && -f "$dev_log" ]]; then
    rm -f -- "$dev_log"
  fi
}
trap cleanup EXIT INT TERM

if command -v google-chrome-stable >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome-stable)"
elif command -v google-chrome >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
  chromium_executable="$(command -v chromium)"
else
  echo "Chrome/Chromium is required for Studio conformance." >&2
  exit 1
fi
command -v jq >/dev/null 2>&1
if ((${#tool_exec[@]} == 0)); then
  command -v dart >/dev/null 2>&1
  command -v jaspr >/dev/null 2>&1
fi

(
  cd "$repo_dir"
  CHROME_EXECUTABLE="$chromium_executable" "${tool_exec[@]}" dart test \
    apps/studio/test/browser_studio_host_client_relay_test.dart \
    -p chrome
)

if [[ "${STUDIO_SKIP_BUILD:-0}" != "1" ]]; then
  (
    cd "$repo_dir/apps/studio"
    "${tool_exec[@]}" jaspr build
  )
fi

chrome_profile="$(mktemp -d /tmp/workspace-studio-chrome.XXXXXX)"
"$chromium_executable" \
  --headless=new \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$chrome_debug_port" \
  --remote-allow-origins="http://127.0.0.1:$chrome_debug_port" \
  --user-data-dir="$chrome_profile" \
  --no-first-run \
  --disable-gpu \
  --window-size=1440,1000 \
  --noerrdialogs \
  about:blank >/dev/null 2>&1 &
chrome_pid=$!
for _ in $(seq 1 100); do
  if curl --fail --silent "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null; then
    break
  fi
  sleep 0.1
done
curl --fail --silent "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null

start_dev() {
  local config_path="$1"
  local profile_override="${2:-}"
  local profile_args=()
  if [[ -n "$profile_override" ]]; then
    profile_args=(--profile "$profile_override")
  fi
  dev_log="$(mktemp "${TMPDIR:-/tmp}/workspace-studio-run.XXXXXX.jsonl")"
  (
    cd "$sample_dir"
    exec "${tool_exec[@]}" dart run ../../apps/workspace_cli/bin/workspace.dart --json dev \
      --config "$config_path" \
      "${profile_args[@]}" \
      --no-open \
      --studio-assets "$studio_assets"
  ) >"$dev_log" 2>&1 &
  dev_pid=$!

  local ready=""
  for _ in $(seq 1 240); do
    ready="$(jq -c 'select(.ok == true and .result.status == "ready")' "$dev_log" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$ready" ]]; then
      break
    fi
    if ! kill -0 "$dev_pid" 2>/dev/null; then
      cat "$dev_log" >&2
      return 1
    fi
    sleep 0.25
  done
  if [[ -z "$ready" ]]; then
    cat "$dev_log" >&2
    echo "Timed out waiting for workspace dev readiness." >&2
    return 1
  fi
  studio_origin="$(jq -r '.result.studioOrigin' <<<"$ready")"
  host_origin="$(jq -r '.result.hostOrigin' <<<"$ready")"
  [[ "$studio_origin" == http://127.0.0.1:* ]]
  [[ "$host_origin" == http://127.0.0.1:* ]]
}

assert_experience_topology() {
  local payload="$1"
  if ! jq -e '
    .experience.status == "ready" and
    (.experience.catalogDigest | startswith("sha256:")) and
    (.experience.topologyDigest | startswith("sha256:")) and
    (.experience.bundleDigest | startswith("sha256:")) and
    .experience.cardinalities == {
      boards: 1,
      projections: 2,
      nodeInstances: 10,
      edgeInstances: 5,
      layouts: 2,
      nodeFrames: 10,
      groups: 3,
      lanes: 5,
      annotations: 2
    } and
    (.experience.layoutDigests | map(.projectionId)) ==
      ["delivery-inventory", "delivery-journey"] and
    ([.experience.layoutDigests[].digest | startswith("sha256:")] | all) and
    ([.experience.projections[] | select(.projectionId == "delivery-journey")] | first) == {
      projectionId: "delivery-journey",
      kind: "journey",
      journeyId: "operate-delivery-workspace",
      nodeInstances: 5,
      edgeInstances: 5,
      layoutDigest: ([.experience.layoutDigests[] |
        select(.projectionId == "delivery-journey")][0].digest),
      nodeFrames: 5,
      groups: 1,
      lanes: 3,
      annotations: 1
    } and
    ([.experience.projections[] | select(.projectionId == "delivery-inventory")] | first) == {
      projectionId: "delivery-inventory",
      kind: "inventory",
      journeyId: null,
      nodeInstances: 5,
      edgeInstances: 0,
      layoutDigest: ([.experience.layoutDigests[] |
        select(.projectionId == "delivery-inventory")][0].digest),
      nodeFrames: 5,
      groups: 2,
      lanes: 2,
      annotations: 1
    } and
    .experience.resource.mediaType == "application/json" and
    .experience.resource.purpose == "experience-topology-bundle" and
    .experience.resource.size > 0 and
    (.experience.resource.digest | startswith("sha256:"))
  ' <<<"$payload" >/dev/null; then
    echo "Experience topology assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_atomic_content_set() {
  local payload="$1"
  if ! jq -e '
    (.contentSet.revision | type) == "number" and
    .contentSet.revision >= 1 and
    (.contentSet.catalogDigest | startswith("sha256:")) and
    (.contentSet.workspaceSnapshotDigest | startswith("sha256:")) and
    (.contentSet.workspaceContentDigest | startswith("sha256:")) and
    (.contentSet.experienceTopologyBundleDigest | startswith("sha256:")) and
    (.contentSet.scenarioFacetManifestDigest | startswith("sha256:")) and
    (.contentSet.contentSetDigest | startswith("sha256:")) and
    .contentSet.workspaceMatches == true and
    .contentSet.experienceMatches == true and
    .contentSet.resourcePurposes == (
      [
        "workspace-snapshot",
        "experience-topology-bundle",
        "scenario-facet-manifest"
      ] +
      (if .contentSet.scenarioLabManifestDigest == null
       then [] else ["scenario-lab-manifest"] end) +
      (if .contentSet.motionManifestDigest == null
       then [] else ["motion-manifest"] end)
    ) and
    .contentSet.facetCardinalities == {
      scenarioKinds: 3,
      surfaces: 2,
      states: 8,
      ownershipAreas: 2,
      tags: 6,
      components: 3,
      fixtures: 8,
      formFactors: 2,
      presentationFrames: 2,
      scenarioFacets: 8
    } and
    (.contentSet.scenarioFacets | length) == 8 and
    ([.contentSet.scenarioFacets[].scenarioId] | unique) == [
      "dashboard-empty",
      "dashboard-failed",
      "dashboard-loading",
      "dashboard-ready",
      "dashboard-stale",
      "dashboard-unavailable",
      "inspect-gateway-traffic",
      "toggle-delivery-task"
    ] and
    ([.contentSet.scenarioFacets[].lifecycle] | unique) == ["current"] and
    ([.contentSet.scenarioFacets[].renderSourceKind] | unique) ==
      ["previewDescriptor"] and
    ([.contentSet.scenarioFacets[] as $facet |
      ($facet.tagIds | length) >= 1 and
      ($facet.componentIds | length) >= 1 and
      ($facet.presentationFrameIds |
        index($facet.preferredPresentationFrameId)) != null
    ] | all) and
    (.rpcMethods | index("experience.content.describe")) != null and
    (.rpcMethods | index("experience.content.open")) != null
  ' <<<"$payload" >/dev/null; then
    echo "Atomic Experience content-set assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_spatial_map() {
  local payload="$1"
  if ! jq -e '
    .spatialMap.available == true and
    .spatialMap.projectionId == "delivery-journey" and
    .spatialMap.routePath ==
      "/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready" and
    .spatialMap.deepLinkNodeId == "journey-dashboard-ready" and
    .spatialMap.nodeInstanceCount == 5 and
    .spatialMap.edgeInstanceCount == 5 and
    .spatialMap.groupCount == 1 and
    .spatialMap.laneCount == 3 and
    .spatialMap.annotationCount == 1 and
    .spatialMap.windowCandidateCount == 5 and
    .spatialMap.windowRenderedCount == 5 and
    .spatialMap.typedAttrGeometrySupported == true and
    .spatialMap.stageRendered == true and
    .spatialMap.stageGeometryValid == true and
    .spatialMap.inlineStyleCount == 0 and
    .spatialMap.geometryMismatches == [] and
    .spatialMap.labelGeometryMismatches == [] and
    (.spatialMap.layoutDigest | startswith("sha256:")) and
    .spatialMap.nodeInstanceIds == [
      "journey-dashboard-failed",
      "journey-dashboard-loading",
      "journey-dashboard-ready",
      "journey-inspect-gateway-traffic",
      "journey-toggle-delivery-task"
    ] and
    .spatialMap.edgeInstanceIds == [
      "journey-loading-to-ready",
      "journey-ready-to-failed",
      "journey-ready-to-gateway",
      "journey-ready-to-toggle",
      "journey-toggle-to-gateway"
    ] and
    .spatialMap.groupIds == ["journey-branch-merge-group"] and
    .spatialMap.laneIds == [
      "journey-direct-lane",
      "journey-recovery-lane",
      "journey-task-lane"
    ] and
    .spatialMap.annotationIds == ["journey-branch-merge-note"] and
    .spatialMap.allNodeDeepLinksValid == true and
    .spatialMap.allNodeIdentitiesValid == true and
    .spatialMap.allEdgeEndpointsValid == true and
    .spatialMap.allEdgeGeometryValid == true and
    .spatialMap.allEdgesSemantic == true and
    .spatialMap.allEdgesRendered == true and
    .spatialMap.selectedNodeInstanceIds == ["journey-dashboard-ready"] and
    (.spatialMap.branchNodeIds | index("journey-dashboard-ready")) != null and
    (.spatialMap.mergeNodeIds |
      index("journey-inspect-gateway-traffic")) != null and
    .spatialMap.duplicateDomIds == [] and
    .spatialMap.duplicateNodeInstanceIds == [] and
    .spatialMap.duplicateEdgeInstanceIds == [] and
    .spatialMap.duplicateGroupIds == [] and
    .spatialMap.duplicateLaneIds == [] and
    .spatialMap.duplicateAnnotationIds == []
  ' <<<"$payload" >/dev/null; then
    echo "Spatial Journey Map assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_spatial_layout_matches_rpc() {
  local rpc_payload="$1"
  local browser_payload="$2"
  local rpc_layout_digest
  local browser_layout_digest
  rpc_layout_digest="$(jq -r '.experience.layoutDigests[] |
    select(.projectionId == "delivery-journey") | .digest' <<<"$rpc_payload")"
  browser_layout_digest="$(jq -r '.spatialMap.layoutDigest' \
    <<<"$browser_payload")"
  if [[ -z "$rpc_layout_digest" ||
        "$rpc_layout_digest" != "$browser_layout_digest" ]]; then
    echo "Browser/RPC delivery-journey layout digest mismatch." >&2
    return 1
  fi
}

assert_inventory_browser() {
  local payload="$1"
  if ! jq -e '
    .status == "passed" and
    .mode == "inventory-audit" and
    .hostConnected == true and
    .resourceRequests >= 1 and
    .accessibilityNodes >= 20 and
    (.screenshotDigest | startswith("sha256:")) and
    .screenshotWidth >= 1000 and
    .screenshotHeight >= 700 and
    .screenshotSubjectVisible == true and
    .severeBrowserLogs == 0 and
    .inventoryIndex.routePath == "/inventory" and
    .inventoryIndex.routeSearch == "" and
    .inventoryIndex.filterSource == "url" and
    .inventoryIndex.facetBoundaryCount == 1 and
    .inventoryIndex.facetStatus == "ready" and
    (.inventoryIndex.facetDigest | startswith("sha256:")) and
    .inventoryIndex.scenarioCount == 8 and
    .inventoryIndex.scenarioIds == [
      "dashboard-empty",
      "dashboard-failed",
      "dashboard-loading",
      "dashboard-ready",
      "dashboard-stale",
      "dashboard-unavailable",
      "inspect-gateway-traffic",
      "toggle-delivery-task"
    ] and
    .inventoryIndex.axisNames == [
      "data-inventory-lifecycle",
      "data-inventory-kind",
      "data-inventory-surface",
      "data-inventory-state",
      "data-inventory-owner",
      "data-inventory-tags",
      "data-inventory-components",
      "data-inventory-fixture",
      "data-inventory-render",
      "data-inventory-frames",
      "data-inventory-form-factors"
    ] and
    .inventoryIndex.axisCount == 11 and
    .inventoryIndex.allAxesNonEmpty == true and
    ([.inventoryIndex.scenarioCards[].missingAxes == []] | all) and
    .inventoryIndex.canonicalDomIds == true and
    .inventoryIndex.semanticArticleCount == 8 and
    .inventoryIndex.projectionIds == ["delivery-inventory"] and
    .inventoryIndex.duplicateDomIds == [] and
    .inventoryIndex.duplicateScenarioIds == [] and
    .inventoryFilter.routeSearch == "?state=dashboard.unavailable" and
    .inventoryFilter.querySize == 1 and
    .inventoryFilter.state == "dashboard.unavailable" and
    .inventoryFilter.selectedValue == "dashboard.unavailable" and
    .inventoryFilter.scenarioCount == 1 and
    .inventoryFilter.scenarioIds == ["dashboard-unavailable"] and
    .inventoryFilter.facetStatus == "ready" and
    .inventoryFilter.facetDigest == .inventoryIndex.facetDigest and
    .inventoryFilter.resetEnabled == true and
    .inventoryReset.routePath == "/inventory" and
    .inventoryReset.routeSearch == "" and
    .inventoryReset.scenarioCount == 8 and
    .inventoryReset.scenarioIds == .inventoryIndex.scenarioIds and
    .inventoryReset.facetDigest == .inventoryIndex.facetDigest and
    .spatialInventory.available == true and
    .spatialInventory.projectionId == "delivery-inventory" and
    .spatialInventory.projectionKind == "inventory" and
    .spatialInventory.inventoryProjectionId == "delivery-inventory" and
    .spatialInventory.routePath ==
      "/inventory/delivery-inventory/nodes/inventory-dashboard-ready" and
    .spatialInventory.routeSearch == "" and
    .spatialInventory.deepLinkNodeId == "inventory-dashboard-ready" and
    .spatialInventory.selectedNodeInstanceIds ==
      ["inventory-dashboard-ready"] and
    .spatialInventory.selectedOutlineNodeInstanceIds ==
      ["inventory-dashboard-ready"] and
    .spatialInventory.nodeInstanceCount == 5 and
    .spatialInventory.nodeInstanceIds == [
      "inventory-dashboard-failed",
      "inventory-dashboard-loading",
      "inventory-dashboard-ready",
      "inventory-inspect-gateway-traffic",
      "inventory-toggle-delivery-task"
    ] and
    .spatialInventory.declaredEdgeCount == 0 and
    .spatialInventory.edgeInstanceCount == 0 and
    .spatialInventory.edgeInstanceIds == [] and
    .spatialInventory.edgeLabelCount == 0 and
    .spatialInventory.edgeLineCount == 0 and
    .spatialInventory.edgeSvgSemantic == true and
    .spatialInventory.groupCount == 2 and
    .spatialInventory.groupIds == [
      "inventory-dashboard-group",
      "inventory-gateway-group"
    ] and
    .spatialInventory.laneCount == 2 and
    .spatialInventory.laneIds == [
      "inventory-operation-lane",
      "inventory-state-lane"
    ] and
    .spatialInventory.annotationCount == 1 and
    .spatialInventory.annotationIds == ["inventory-reuse-note"] and
    .spatialInventory.windowCandidateCount == 5 and
    .spatialInventory.windowRenderedCount == 5 and
    .spatialInventory.camera == {x: 0, y: 0, zoom: 0.9} and
    .spatialInventory.canvas == {width: 1216, height: 532} and
    (.spatialInventory.layoutDigest | startswith("sha256:")) and
    .spatialInventory.typedAttrGeometrySupported == true and
    .spatialInventory.stageRendered == true and
    .spatialInventory.stageGeometryValid == true and
    .spatialInventory.inlineStyleCount == 0 and
    .spatialInventory.geometryMismatches == [] and
    .spatialInventory.allNodeDeepLinksValid == true and
    .spatialInventory.allNodeIdentitiesValid == true and
    .spatialInventory.crossLensPath ==
      "/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready" and
    .spatialInventory.crossLensSearch == "" and
    .spatialInventory.crossLensExact == true and
    .spatialInventory.duplicateDomIds == [] and
    .spatialInventory.duplicateNodeInstanceIds == [] and
    .spatialInventory.duplicateEdgeInstanceIds == [] and
    .spatialInventory.duplicateGroupIds == [] and
    .spatialInventory.duplicateLaneIds == [] and
    .spatialInventory.duplicateAnnotationIds == [] and
    .semanticHtml.hasMain == true and
    .semanticHtml.hasPrimaryNavigation == true and
    .semanticHtml.hasPageHeading == true and
    .semanticHtml.hasLiveRegion == true and
    .semanticHtml.flutterElementCount == 0 and
    .semanticHtml.unnamedFocusableCount == 0 and
    .semanticHtml.minimumInteractiveSize >= 47.5 and
    .keyboard.uniqueTabStops >= 5 and
    .reflow200Percent.horizontalDocumentOverflow == false and
    .reflow200Percent.mainVisible == true and
    .reflow200Percent.headingVisible == true and
    .reducedMotion.queryMatches == true and
    .reducedMotion.transitionSeconds <= 0.001 and
    .performance.loadEventMs < 5000
  ' <<<"$payload" >/dev/null; then
    echo "Browser Inventory assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_inventory_matches_rpc() {
  local rpc_payload="$1"
  local browser_payload="$2"
  local rpc_layout_digest
  local browser_layout_digest
  local rpc_facet_digest
  local browser_facet_digest
  rpc_layout_digest="$(jq -r '.experience.layoutDigests[] |
    select(.projectionId == "delivery-inventory") | .digest' \
    <<<"$rpc_payload")"
  browser_layout_digest="$(jq -r '.spatialInventory.layoutDigest' \
    <<<"$browser_payload")"
  rpc_facet_digest="$(jq -r '.contentSet.scenarioFacetManifestDigest' \
    <<<"$rpc_payload")"
  browser_facet_digest="$(jq -r '.inventoryIndex.facetDigest' \
    <<<"$browser_payload")"
  if [[ -z "$rpc_layout_digest" ||
        "$rpc_layout_digest" != "$browser_layout_digest" ]]; then
    echo "Browser/RPC delivery-inventory layout digest mismatch." >&2
    return 1
  fi
  if [[ -z "$rpc_facet_digest" ||
        "$rpc_facet_digest" != "$browser_facet_digest" ]]; then
    echo "Browser/RPC ScenarioFacetManifest digest mismatch." >&2
    return 1
  fi
}

assert_current_capture_keys() {
  local payload="$1"
  local expected_freshness="$2"
  if ! jq -e --arg freshness "$expected_freshness" '
    def expected:
      [
        {scenarioId: "dashboard-empty", variantId: "phone.light.en-us"},
        {scenarioId: "dashboard-failed", variantId: "phone.light.en-us"},
        {scenarioId: "dashboard-loading", variantId: "phone.light.en-us"},
        {scenarioId: "dashboard-ready", variantId: "desktop.light.en-us"},
        {scenarioId: "dashboard-ready", variantId: "phone.dark.en-us"},
        {scenarioId: "dashboard-ready", variantId: "phone.light.en-us"},
        {scenarioId: "dashboard-stale", variantId: "desktop.light.en-us"},
        {scenarioId: "dashboard-unavailable", variantId: "phone.light.en-us"},
        {scenarioId: "inspect-gateway-traffic", variantId: "desktop.light.en-us"},
        {scenarioId: "toggle-delivery-task", variantId: "phone.light.en-us"}
      ];
    ([.projectionStates[] |
      select(
        .scenarioId != null and
        .status == "collected" and
        .freshness == $freshness and
        .fidelity == "structural" and
        .capturePolicyId == "static-v1" and
        .hasArtifactHandle == true and
        ((.executionFingerprintDigest | type) == "string") and
        (.executionFingerprintDigest | startswith("sha256:"))
      ) |
      {scenarioId, variantId}] | unique) as $validCurrent |
    (expected - $validCurrent | length) == 0
  ' <<<"$payload" >/dev/null; then
    echo "Current AutoPreview key assertion failed ($expected_freshness):" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_preview_snapshot() {
  local payload="$1"
  if ! jq -e '
    .applications == 1 and
    .journeys == 1 and
    .scenarios == 8 and
    .variants == 3 and
    .providers == ["evidence.auto-preview"] and
    .collected >= 10 and
    .fresh >= 10 and
    .validatedPngs >= 10 and
    .collection.state == "completed" and
    .collection.completedItems == 10 and
    .collection.totalItems == 10 and
    .collection.failedItems == 0 and
    (.rpcMethods | index("preview.collect")) != null
  ' <<<"$payload" >/dev/null; then
    echo "Preview snapshot assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
  assert_current_capture_keys "$payload" "fresh"
  assert_experience_topology "$payload"
  assert_atomic_content_set "$payload"
}

assert_stale_snapshot() {
  local payload="$1"
  if ! jq -e '
    .variants == 3 and
    .collected >= 10 and
    .validatedPngs >= 10 and
    .stale >= 10
  ' <<<"$payload" >/dev/null; then
    echo "Stale snapshot assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
  assert_current_capture_keys "$payload" "stale"
  assert_experience_topology "$payload"
  assert_atomic_content_set "$payload"
}

echo "[studio-vertical] starting journey-preview" >&2
start_dev "journey-preview.yaml"
echo "[studio-vertical] collecting ten AutoPreview captures" >&2
preview_payload="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" "$studio_origin" --collect)"
assert_preview_snapshot "$preview_payload"
echo "[studio-vertical] validating release Studio in Chromium" >&2
browser_payload="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready")"
jq -e '
  .resourceRequests >= 1 and
  .severeBrowserLogs == 0 and
  .semanticHtml.flutterElementCount == 0 and
  .semanticHtml.unnamedFocusableCount == 0 and
  .keyboard.uniqueTabStops >= 5 and
  .reflow200Percent.horizontalDocumentOverflow == false and
  .reducedMotion.queryMatches == true and
  .performance.loadEventMs < 5000 and
  .mapInteraction.p95Ms < 100
' \
  <<<"$browser_payload" >/dev/null
assert_spatial_map "$browser_payload"
assert_spatial_layout_matches_rpc "$preview_payload" "$browser_payload"
echo "[studio-vertical] auditing canonical Inventory in Chromium" >&2
inventory_browser_payload="$("${tool_exec[@]}" dart run \
  "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/inventory" \
  "${inventory_screenshot_args[@]}" \
  --inventory-audit)"
assert_inventory_browser "$inventory_browser_payload"
assert_inventory_matches_rpc "$preview_payload" "$inventory_browser_payload"

stale_probe="$(mktemp "$sample_dir/lib/studio_stale_probe_XXXXXX.dart")"
printf '%s\n' '// Synthetic source-impact probe. Removed by the gate trap.' \
  >"$stale_probe"
echo "[studio-vertical] proving source edit marks evidence stale" >&2
stale_payload="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
  "$studio_origin" --refresh)"
assert_stale_snapshot "$stale_payload"
echo "[studio-vertical] recollecting changed source to fresh" >&2
fresh_with_probe="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
  "$studio_origin" --collect)"
assert_preview_snapshot "$fresh_with_probe"

rm -f -- "$stale_probe"
stale_probe=""
echo "[studio-vertical] proving source restoration marks evidence stale" >&2
restored_stale="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
  "$studio_origin" --refresh)"
assert_stale_snapshot "$restored_stale"
echo "[studio-vertical] recollecting restored source to fresh" >&2
restored_fresh="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
  "$studio_origin" --collect)"
assert_preview_snapshot "$restored_fresh"

first_studio_origin="$studio_origin"
first_host_origin="$host_origin"
cleanup_dev
if curl --silent --max-time 1 "$first_studio_origin/health" >/dev/null 2>&1 || \
   curl --silent --max-time 1 "$first_host_origin/health" >/dev/null 2>&1; then
  echo "Preview run left a listener behind." >&2
  exit 1
fi

echo "[studio-vertical] restarting with Journey Map and no provider" >&2
start_dev "journey-no-evidence.yaml"
no_preview_payload="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" "$studio_origin")"
jq -e '
  .variants == 0 and
  .providers == [] and
  .visualProjections == 0 and
  .validatedPngs == 0 and
  (.rpcMethods | map(startswith("preview.")) | any) == false
' <<<"$no_preview_payload" >/dev/null
assert_experience_topology "$no_preview_payload"
assert_atomic_content_set "$no_preview_payload"
no_preview_browser="$("${tool_exec[@]}" dart run "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready" \
  --no-preview)"
jq -e '
  .resourceRequests >= 1 and
  .severeBrowserLogs == 0 and
  .mode == "no-preview" and
  .semanticHtml.flutterElementCount == 0 and
  .reflow200Percent.horizontalDocumentOverflow == false
' \
  <<<"$no_preview_browser" >/dev/null
assert_spatial_map "$no_preview_browser"
assert_spatial_layout_matches_rpc "$no_preview_payload" "$no_preview_browser"
echo "[studio-vertical] auditing Inventory without Evidence provider" >&2
no_preview_inventory_browser="$("${tool_exec[@]}" dart run \
  "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/inventory" \
  --inventory-audit)"
assert_inventory_browser "$no_preview_inventory_browser"
assert_inventory_matches_rpc \
  "$no_preview_payload" "$no_preview_inventory_browser"

preview_topology_identity="$(jq -c '.experience | {
  catalogDigest,
  topologyDigest,
  bundleDigest,
  layoutDigests,
  cardinalities,
  projections
}' <<<"$restored_fresh")"
no_provider_topology_identity="$(jq -c '.experience | {
  catalogDigest,
  topologyDigest,
  bundleDigest,
  layoutDigests,
  cardinalities,
  projections
}' <<<"$no_preview_payload")"
if [[ "$preview_topology_identity" != "$no_provider_topology_identity" ]]; then
  echo "Provider profile changed the Experience topology/layout payload." >&2
  exit 1
fi

preview_facet_identity="$(jq -c '.contentSet | {
  catalogDigest,
  scenarioFacetManifestDigest,
  facetCardinalities,
  scenarioFacets
}' <<<"$restored_fresh")"
no_provider_facet_identity="$(jq -c '.contentSet | {
  catalogDigest,
  scenarioFacetManifestDigest,
  facetCardinalities,
  scenarioFacets
}' <<<"$no_preview_payload")"
if [[ "$preview_facet_identity" != "$no_provider_facet_identity" ]]; then
  echo "Provider profile changed the Scenario facets payload." >&2
  exit 1
fi

second_studio_origin="$studio_origin"
second_host_origin="$host_origin"
cleanup_dev
if curl --silent --max-time 1 "$second_studio_origin/health" >/dev/null 2>&1 || \
   curl --silent --max-time 1 "$second_host_origin/health" >/dev/null 2>&1; then
  echo "No-provider run left a listener behind." >&2
  exit 1
fi

jq -n \
  --arg previewSnapshot "$(jq -r '.snapshotDigest' <<<"$restored_fresh")" \
  --arg browserScreenshot "$(jq -r '.screenshotDigest' <<<"$browser_payload")" \
  --arg inventoryScreenshot "$(jq -r '.screenshotDigest' <<<"$inventory_browser_payload")" \
  --arg noPreviewSnapshot "$(jq -r '.snapshotDigest' <<<"$no_preview_payload")" \
  --argjson validatedPngs "$(jq -r '.validatedPngs' <<<"$restored_fresh")" \
  --argjson browserPerformance "$(jq -c '.performance' <<<"$browser_payload")" \
  --argjson mapInteraction "$(jq -c '.mapInteraction' <<<"$browser_payload")" \
  --argjson browserAccessibility "$(jq -c '{semanticHtml, keyboard, reflow200Percent, reducedMotion}' <<<"$browser_payload")" \
  --argjson experienceTopology "$(jq -c '.experience' <<<"$restored_fresh")" \
  --argjson spatialJourney "$(jq -c '.spatialMap' <<<"$browser_payload")" \
  --argjson inventoryBrowser "$(jq -c '{
    inventoryIndex,
    inventoryFilter,
    inventoryReset,
    spatialInventory,
    semanticHtml,
    keyboard,
    reflow200Percent,
    reducedMotion,
    performance,
    accessibilityNodes,
    screenshotDigest,
    screenshotSubjectVisible,
    severeBrowserLogs
  }' <<<"$inventory_browser_payload")" \
  --argjson noProviderExperienceTopology "$(jq -c '.experience' <<<"$no_preview_payload")" \
  --argjson noProviderSpatialJourney "$(jq -c '.spatialMap' <<<"$no_preview_browser")" \
  --argjson noProviderInventoryBrowser "$(jq -c '{
    inventoryIndex,
    inventoryFilter,
    inventoryReset,
    spatialInventory,
    semanticHtml,
    keyboard,
    reflow200Percent,
    reducedMotion,
    performance,
    accessibilityNodes,
    screenshotDigest,
    screenshotSubjectVisible,
    severeBrowserLogs
  }' <<<"$no_preview_inventory_browser")" \
  '{
    status: "passed",
    previewSnapshotDigest: $previewSnapshot,
    browserScreenshotDigest: $browserScreenshot,
    inventoryScreenshotDigest: $inventoryScreenshot,
    noPreviewSnapshotDigest: $noPreviewSnapshot,
    variants: 3,
    validatedPngs: $validatedPngs,
    fidelity: "structural",
    sourceImpact: "stale-to-fresh",
    cleanup: "verified",
    experienceTopology: $experienceTopology,
    spatialJourney: $spatialJourney,
    inventory: $inventoryBrowser,
    noProvider: {
      experienceTopology: $noProviderExperienceTopology,
      spatialJourney: $noProviderSpatialJourney,
      inventory: $noProviderInventoryBrowser
    },
    browserPerformance: $browserPerformance,
    mapInteraction: $mapInteraction,
    browserAccessibility: $browserAccessibility
  }'
