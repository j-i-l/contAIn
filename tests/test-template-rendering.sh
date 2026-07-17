#!/usr/bin/env bash
# test-template-rendering.sh — unit tests for systemd template rendering
# =========================================================================
# Verifies that the .in templates render correctly using the shared
# functions from lib/render-template.sh.
#
# Usage:  bash tests/test-template-rendering.sh
#         (no root required, no external dependencies beyond bash + coreutils)
# =========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/render-template.sh
source "${REPO_ROOT}/lib/render-template.sh"

SYSTEMD_DIR="${REPO_ROOT}/systemd"
PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

# assert_no_unreplaced_placeholders <rendered_output> <test_name>
# Fails if any @@WORD@@ tokens remain in the output.
assert_no_unreplaced_placeholders() {
  local output="$1" name="$2"
  if echo "$output" | grep -qE '@@[A-Z_]+@@'; then
    local remaining
    remaining=$(echo "$output" | grep -oE '@@[A-Z_]+@@' | sort -u | tr '\n' ' ')
    fail "${name}: unreplaced placeholders remain: ${remaining}"
  else
    pass "${name}: no unreplaced placeholders"
  fi
}

# assert_no_directives_before_first_section <rendered_output> <test_name>
# Fails if any KEY=VALUE directives appear before the first [Section] header.
# This is the exact bug class we're guarding against — bare directives
# outside of an INI section make Quadlet silently reject the file.
assert_no_directives_before_first_section() {
  local output="$1" name="$2"
  local before_section
  # Extract everything before the first [Section] line
  before_section=$(echo "$output" | sed -n '1,/^\[/{ /^\[/!p }')

  # Check if any non-comment, non-blank lines look like directives (Key=Value)
  if echo "$before_section" | grep -qE '^[A-Za-z]+='; then
    local offending
    offending=$(echo "$before_section" | grep -E '^[A-Za-z]+=')
    fail "${name}: directive(s) before first [Section]: ${offending}"
  else
    pass "${name}: no directives before first section"
  fi
}

# assert_contains <rendered_output> <expected_substring> <test_name>
assert_contains() {
  local output="$1" expected="$2" name="$3"
  if echo "$output" | grep -qF -- "$expected"; then
    pass "${name}"
  else
    fail "${name}: expected to find '${expected}'"
  fi
}

# assert_line_count <rendered_output> <pattern> <expected_count> <test_name>
assert_line_count() {
  local output="$1" pattern="$2" expected="$3" name="$4"
  local actual
  actual=$(echo "$output" | grep -cF -- "$pattern" || true)
  if [[ "$actual" -eq "$expected" ]]; then
    pass "${name}"
  else
    fail "${name}: expected ${expected} lines matching '${pattern}', got ${actual}"
  fi
}

# assert_not_contains <rendered_output> <substring> <test_name>
# Matches whole lines starting with the substring (so template comments that
# merely mention a directive don't trigger false positives).
assert_not_contains() {
  local output="$1" unexpected="$2" name="$3"
  if echo "$output" | grep -q "^$(printf '%s' "$unexpected" | sed 's/[][\.*^$/]/\\&/g')"; then
    fail "${name}: expected NOT to find line starting with '${unexpected}'"
  else
    pass "${name}"
  fi
}

# ── Test: Container template — single project path ──────────────────────

echo ""
echo "=== Container template: single project path ==="

VOLUME_LINES_1=$(build_volume_lines \
  "/home/alice/Projects" \
  "/home/alice/Projects")

RENDERED_1=$(render_container_unit \
  "${SYSTEMD_DIR}/contain.container.in" \
  "/home/alice" \
  "/home/alice/.config/contain" \
  "127.0.0.1" \
  "3000" \
  "$VOLUME_LINES_1")

assert_no_unreplaced_placeholders "$RENDERED_1" "single-path"
assert_no_directives_before_first_section "$RENDERED_1" "single-path"
assert_line_count "$RENDERED_1" "Volume=/home/alice/Projects:/home/alice/Projects:rw,Z" 1 \
  "single-path: project volume present"
assert_contains "$RENDERED_1" "Volume=/home/alice/.config/contain/opencode.json:/etc/contain/opencode.json:ro" \
  "single-path: policy volume resolved"
assert_contains "$RENDERED_1" "Volume=/home/alice/.config/opencode:/home/agent/.config/opencode:ro" \
  "single-path: opencode config volume resolved"
assert_contains "$RENDERED_1" "Exec=serve --hostname 127.0.0.1 --port 3001" \
  "single-path: on-demand default binds internal port (public+1)"
assert_contains "$RENDERED_1" "StopWhenUnneeded=yes" \
  "single-path: on-demand default sets StopWhenUnneeded"
assert_contains "$RENDERED_1" "Notify=healthy" \
  "single-path: on-demand default sets Notify=healthy"
assert_contains "$RENDERED_1" "HealthCmd=curl -sf http://127.0.0.1:3001/global/health" \
  "single-path: runtime healthcheck uses internal port"
assert_contains "$RENDERED_1" "HealthInterval=30s" \
  "single-path: healthcheck interval rendered"
assert_contains "$RENDERED_1" "HealthTimeout=5s" \
  "single-path: healthcheck timeout rendered"
assert_contains "$RENDERED_1" "HealthRetries=3" \
  "single-path: healthcheck retries rendered"
assert_contains "$RENDERED_1" "HealthStartPeriod=10s" \
  "single-path: healthcheck start period rendered"
assert_contains "$RENDERED_1" "HealthStartupCmd=curl -sf http://127.0.0.1:3001/global/health" \
  "single-path: startup healthcheck uses internal port"
assert_contains "$RENDERED_1" "HealthStartupInterval=1s" \
  "single-path: startup healthcheck interval rendered"
assert_contains "$RENDERED_1" "HealthStartupTimeout=2s" \
  "single-path: startup healthcheck timeout rendered"
assert_contains "$RENDERED_1" "HealthStartupRetries=0" \
  "single-path: startup healthcheck does not force restarts"
assert_contains "$RENDERED_1" "HealthStartupSuccess=1" \
  "single-path: startup healthcheck requires one success"
assert_not_contains "$RENDERED_1" "WantedBy=multi-user.target" \
  "single-path: on-demand default has no boot autostart"

# ── Test: Container template — multiple project paths ────────────────────

echo ""
echo "=== Container template: multiple project paths ==="

VOLUME_LINES_3=$(build_volume_lines \
  "/home/bob/code/frontend
/home/bob/code/backend
/home/bob/code/shared" \
  "/home/bob/code/frontend
/home/bob/code/backend
/home/bob/code/shared")

RENDERED_3=$(render_container_unit \
  "${SYSTEMD_DIR}/contain.container.in" \
  "/home/bob" \
  "/home/bob/.config/contain" \
  "0.0.0.0" \
  "8080" \
  "$VOLUME_LINES_3")

assert_no_unreplaced_placeholders "$RENDERED_3" "multi-path"
assert_no_directives_before_first_section "$RENDERED_3" "multi-path"
assert_line_count "$RENDERED_3" "Volume=/home/bob/code/" 3 \
  "multi-path: all 3 project volumes present"
assert_contains "$RENDERED_3" "Volume=/home/bob/code/frontend:/home/bob/code/frontend:rw,Z" \
  "multi-path: frontend volume correct"
assert_contains "$RENDERED_3" "Volume=/home/bob/code/backend:/home/bob/code/backend:rw,Z" \
  "multi-path: backend volume correct"
assert_contains "$RENDERED_3" "Volume=/home/bob/code/shared:/home/bob/code/shared:rw,Z" \
  "multi-path: shared volume correct"
assert_contains "$RENDERED_3" "Exec=serve --hostname 0.0.0.0 --port 8081" \
  "multi-path: on-demand default derives internal port from custom port"

# ── Test: Container template — always-on mode ─────────────────────────────

echo ""
echo "=== Container template: always-on mode ==="

RENDERED_AO=$(render_container_unit \
  "${SYSTEMD_DIR}/contain.container.in" \
  "/home/alice" \
  "/home/alice/.config/contain" \
  "127.0.0.1" \
  "3000" \
  "$VOLUME_LINES_1" \
  "always-on")

assert_no_unreplaced_placeholders "$RENDERED_AO" "always-on"
assert_no_directives_before_first_section "$RENDERED_AO" "always-on"
assert_contains "$RENDERED_AO" "Exec=serve --hostname 127.0.0.1 --port 3000" \
  "always-on: binds public port directly"
assert_contains "$RENDERED_AO" "WantedBy=multi-user.target" \
  "always-on: boot autostart present"
assert_not_contains "$RENDERED_AO" "StopWhenUnneeded=yes" \
  "always-on: no StopWhenUnneeded"
assert_not_contains "$RENDERED_AO" "Notify=healthy" \
  "always-on: no Notify=healthy"
assert_contains "$RENDERED_AO" "HealthCmd=curl -sf http://127.0.0.1:3000/global/health" \
  "always-on: runtime healthcheck uses public port"
assert_contains "$RENDERED_AO" "HealthStartupCmd=curl -sf http://127.0.0.1:3000/global/health" \
  "always-on: startup healthcheck uses public port"

# ── Test: Container template — explicit internal port ─────────────────────

echo ""
echo "=== Container template: explicit internal port ==="

RENDERED_IP=$(render_container_unit \
  "${SYSTEMD_DIR}/contain.container.in" \
  "/home/alice" \
  "/home/alice/.config/contain" \
  "127.0.0.1" \
  "3000" \
  "$VOLUME_LINES_1" \
  "on-demand" \
  "4242")

assert_contains "$RENDERED_IP" "Exec=serve --hostname 127.0.0.1 --port 4242" \
  "explicit-internal: Exec uses given internal port"
assert_contains "$RENDERED_IP" "HealthCmd=curl -sf http://127.0.0.1:4242/global/health" \
  "explicit-internal: runtime healthcheck uses given internal port"
assert_contains "$RENDERED_IP" "HealthStartupCmd=curl -sf http://127.0.0.1:4242/global/health" \
  "explicit-internal: startup healthcheck uses given internal port"

# ── Test: Proxy socket + service templates ────────────────────────────────

echo ""
echo "=== Proxy socket + service templates ==="

RENDERED_SOCK=$(render_proxy_socket \
  "${SYSTEMD_DIR}/contain-proxy.socket.in" \
  "127.0.0.1" \
  "3000")

assert_no_unreplaced_placeholders "$RENDERED_SOCK" "proxy-socket"
assert_no_directives_before_first_section "$RENDERED_SOCK" "proxy-socket"
assert_contains "$RENDERED_SOCK" "ListenStream=127.0.0.1:3000" \
  "proxy-socket: listen stream resolved"

RENDERED_PROXY=$(render_proxy_service \
  "${SYSTEMD_DIR}/contain-proxy.service.in" \
  "127.0.0.1" \
  "3001" \
  "20min")

assert_no_unreplaced_placeholders "$RENDERED_PROXY" "proxy-service"
assert_no_directives_before_first_section "$RENDERED_PROXY" "proxy-service"
assert_contains "$RENDERED_PROXY" "--exit-idle-time=20min 127.0.0.1:3001" \
  "proxy-service: idle timeout and backend resolved"
assert_contains "$RENDERED_PROXY" "Requires=contain.service" \
  "proxy-service: requires the container"

# ── Test: Container template — paths with spaces ────────────────────────

echo ""
echo "=== Container template: path with spaces ==="

VOLUME_LINES_SPACE=$(build_volume_lines \
  "/home/user/My Projects/app" \
  "/home/user/My Projects/app")

RENDERED_SPACE=$(render_container_unit \
  "${SYSTEMD_DIR}/contain.container.in" \
  "/home/user" \
  "/home/user/.config/contain" \
  "127.0.0.1" \
  "3000" \
  "$VOLUME_LINES_SPACE")

assert_no_unreplaced_placeholders "$RENDERED_SPACE" "spaces-in-path"
assert_no_directives_before_first_section "$RENDERED_SPACE" "spaces-in-path"
assert_contains "$RENDERED_SPACE" "Volume=/home/user/My Projects/app:/home/user/My Projects/app:rw,Z" \
  "spaces-in-path: volume line preserved spaces"

# ── Test: Watcher service template ──────────────────────────────────────

echo ""
echo "=== Watcher service template ==="

RENDERED_WATCHER=$(render_watcher_unit \
  "${SYSTEMD_DIR}/contain-watcher.service.in" \
  "/opt/contain" \
  "alice" \
  "agent" \
  "/home/alice/Projects /home/alice/Work")

assert_no_unreplaced_placeholders "$RENDERED_WATCHER" "watcher"
assert_no_directives_before_first_section "$RENDERED_WATCHER" "watcher"
assert_contains "$RENDERED_WATCHER" \
  "ExecStart=/opt/contain/contain-watcher.sh alice agent /home/alice/Projects /home/alice/Work" \
  "watcher: ExecStart fully resolved"

# ── Test: Commit service template ───────────────────────────────────────

echo ""
echo "=== Commit service template ==="

RENDERED_COMMIT=$(render_commit_service \
  "${SYSTEMD_DIR}/contain-commit.service" \
  "/opt/contain")

assert_no_unreplaced_placeholders "$RENDERED_COMMIT" "commit"
assert_no_directives_before_first_section "$RENDERED_COMMIT" "commit"
assert_contains "$RENDERED_COMMIT" \
  "ExecStart=/opt/contain/contain-commit.sh" \
  "commit: ExecStart resolved"

# ── Test: build_volume_lines helper ─────────────────────────────────────

echo ""
echo "=== build_volume_lines helper ==="

VL_RESULT=$(build_volume_lines \
  "/a/b
/c/d" \
  "/a/b
/c/d")

EXPECTED_VL="Volume=/a/b:/a/b:rw,Z
Volume=/c/d:/c/d:rw,Z"

if [[ "$VL_RESULT" == "$EXPECTED_VL" ]]; then
  pass "build_volume_lines: correct output for 2 paths"
else
  fail "build_volume_lines: unexpected output"
  echo "  Expected: $(echo "$EXPECTED_VL" | cat -A)"
  echo "  Got:      $(echo "$VL_RESULT" | cat -A)"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

[[ $FAIL -eq 0 ]] || exit 1
