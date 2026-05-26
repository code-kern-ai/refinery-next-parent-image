#!/usr/bin/env bash
# Debug helper: validates cache/base images and logs NDJSON for hypothesis testing.
# Usage: ./scripts/debug-docker-cache.sh [branch-name]
# Optional env: REGISTRY_USER, REGISTRY_PASS, DHI_USER, DHI_PASS

set -euo pipefail

LOG_PATH="${DEBUG_LOG_PATH:-/Users/linalumburovska/Documents/workspace/.cursor/debug-dd9b2b.log}"
SESSION_ID="${DEBUG_SESSION_ID:-dd9b2b}"
RUN_ID="${DEBUG_RUN_ID:-local-$(date +%s)}"
BRANCH="${1:-hardened-images}"
ARCH="$(uname -m)"
REPO="registry.dev.kern.ai/code-kern-ai/refinery-parent-images"

# #region agent log
log() {
  local hyp="$1" loc="$2" msg="$3" data="$4"
  printf '%s\n' "{\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"${hyp}\",\"location\":\"${loc}\",\"message\":\"${msg}\",\"data\":${data},\"timestamp\":$(date +%s000)}" >> "$LOG_PATH"
}
# #endregion

mkdir -p "$(dirname "$LOG_PATH")"

log "H0" "debug-docker-cache.sh:start" "debug script started" "{\"branch\":\"${BRANCH}\",\"arch\":\"${ARCH}\"}"

if command -v docker >/dev/null 2>&1; then
  log "H0" "debug-docker-cache.sh:docker" "docker available" "{\"version\":\"$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)\"}"
else
  log "H0" "debug-docker-cache.sh:docker" "docker missing" "{}"
  exit 1
fi

login_reg() {
  if [[ -n "${REGISTRY_USER:-}" && -n "${REGISTRY_PASS:-}" ]]; then
    echo "$REGISTRY_PASS" | docker login registry.dev.kern.ai -u "$REGISTRY_USER" --password-stdin >/dev/null 2>&1 || true
  fi
}

login_dhi() {
  if [[ -n "${DHI_USER:-}" && -n "${DHI_PASS:-}" ]]; then
    echo "$DHI_PASS" | docker login dhi.io -u "$DHI_USER" --password-stdin >/dev/null 2>&1 || true
  fi
}

inspect_tag() {
  local hyp="$1" tag="$2"
  local pull_out pull_ec=0
  pull_out="$(docker pull "$tag" 2>&1)" || pull_ec=$?
  log "$hyp" "debug-docker-cache.sh:pull" "cache pull result" "$(jq -nc --arg tag "$tag" --arg out "$pull_out" --argjson ec "$pull_ec" '{tag:$tag,exitCode:$ec,output:($out|.[0:500])}')"

  if [[ "$pull_ec" -eq 0 ]]; then
    local inspect_json
    inspect_json="$(docker image inspect "$tag" --format '{{json .}}' 2>/dev/null | head -c 2000 || echo '{}')"
    local arch os id
    arch="$(docker image inspect "$tag" --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
    os="$(docker image inspect "$tag" --format '{{.Os}}' 2>/dev/null || echo unknown)"
    id="$(docker image inspect "$tag" --format '{{.Id}}' 2>/dev/null || echo unknown)"
    log "$hyp" "debug-docker-cache.sh:inspect" "image inspect" "$(jq -nc --arg tag "$tag" --arg arch "$arch" --arg os "$os" --arg id "$id" '{tag:$tag,architecture:$arch,os:$os,id:$id}')"

    local manifest_out manifest_ec=0
    manifest_out="$(docker manifest inspect "$tag" 2>&1)" || manifest_ec=$?
    local is_manifest_list="false"
    echo "$manifest_out" | grep -q '"manifests"' && is_manifest_list="true"
    log "H2" "debug-docker-cache.sh:manifest" "manifest inspect" "$(jq -nc --arg tag "$tag" --argjson ec "$manifest_ec" --argjson list "$is_manifest_list" '{tag:$tag,exitCode:$ec,isManifestList:$list}')"
  fi
}

login_reg
login_dhi

# H1: corrupt or wrong-arch cache layer (dev-next)
inspect_tag "H1" "${REPO}:dev-next"
# H1b: branch-specific cache
inspect_tag "H1" "${REPO}:${BRANCH}-next"

# H3: DHI base images pull and layer validity
for base in "dhi.io/node:20-debian12-dev" "dhi.io/node:20-debian12"; do
  pull_ec=0
  pull_out="$(docker pull "$base" 2>&1)" || pull_ec=$?
  log "H3" "debug-docker-cache.sh:dhi-pull" "dhi base pull" "$(jq -nc --arg img "$base" --argjson ec "$pull_ec" --arg out "$pull_out" '{image:$img,exitCode:$ec,output:($out|.[0:300])}')"
done

# H4: build with cache-from vs without (only if logged in to both registries)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${REGISTRY_USER:-}" && -n "${DHI_USER:-}" ]]; then
  cd "$ROOT"
  build_ec=0
  build_out="$(docker build --pull -f Dockerfile -t refinery-next-debug:cache-test \
    --cache-from "${REPO}:dev-next" \
    --cache-from "${REPO}:${BRANCH}-next" . 2>&1)" || build_ec=$?
  log "H4" "debug-docker-cache.sh:build-with-cache" "build with cache-from" "$(jq -nc --argjson ec "$build_ec" --arg out "$build_out" '{exitCode:$ec,hasInvalidTar:($out|test("invalid tar header")),tail:($out|.[0:800])}')"

  build_ec2=0
  build_out2="$(docker build --pull -f Dockerfile -t refinery-next-debug:no-cache . 2>&1)" || build_ec2=$?
  log "H4" "debug-docker-cache.sh:build-no-cache" "build without cache-from" "$(jq -nc --argjson ec "$build_ec2" --arg out "$build_out2" '{exitCode:$ec,hasInvalidTar:($out|test("invalid tar header")),tail:($out|.[0:800])}')"
else
  log "H4" "debug-docker-cache.sh:build-skip" "skipped build tests (set REGISTRY_USER/PASS and DHI_USER/PASS)" "{}"
fi

log "H0" "debug-docker-cache.sh:done" "debug script finished" "{}"
echo "Wrote debug logs to ${LOG_PATH}"
