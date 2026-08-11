#!/usr/bin/env bash
#
# Local verification of the add-on image, simulating what Supervisor does:
# a persistent /data bind, a /share bind, an options.json, and a SUPERVISOR_TOKEN.
#
#   ./scripts/verify.sh [image]
#
# Exercises the checks that matter before this ever reaches a real Home
# Assistant instance -- above all that state lands in /data and NOT on the
# anonymous /home/paseo volume declared by the upstream image.

set -euo pipefail

IMAGE="${1:-ha-paseo:dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDIR="${ROOT}/.test"
NAME=ha-paseo-verify
PORT=16767

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

check() {  # check <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

in_container() { docker exec "$NAME" "$@"; }

start_container() {
    cleanup
    docker run -d --name "$NAME" \
        -p "${PORT}:6767" \
        -v "${TESTDIR}/data:/data" \
        -v "${TESTDIR}/share:/share" \
        -v "${TESTDIR}/homeassistant:/homeassistant" \
        -e SUPERVISOR_TOKEN=dummy-token \
        "$IMAGE" >/dev/null
}

wait_healthy() {
    local waited=0
    until curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; do
        sleep 2; waited=$((waited + 2))
        if (( waited >= 90 )); then
            printf '\n\033[31mDaemon never became healthy. Logs:\033[0m\n'
            docker logs "$NAME" 2>&1 | tail -40
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
step "Preparing ${TESTDIR}"
# Previous runs leave directories owned by uid 1000 / root from inside the
# container, so clear them out as root in a throwaway container.
if [[ -d "$TESTDIR" ]]; then
    docker run --rm -v "${TESTDIR}:/wipe" alpine:3 sh -c 'rm -rf /wipe/..?* /wipe/.[!.]* /wipe/*' \
        >/dev/null 2>&1 || true
fi
rm -rf "$TESTDIR"
mkdir -p "${TESTDIR}"/{data,share,homeassistant}
cat > "${TESTDIR}/data/options.json" <<'EOF'
{
  "password": "verify-secret",
  "hostnames": ["homeassistant.local", ".lan", ".ts.net"],
  "log_level": "info",
  "relay_enabled": false,
  "workspace_root": "/share/paseo/workspace",
  "expose_ha_config": true,
  "ha_mcp_url": "http://supervisor/core/mcp_server/sse",
  "provider_overrides": "{\"claude\":{\"label\":\"Claude (verify)\"}}",
  "extra_npm_packages": [],
  "extra_apt_packages": []
}
EOF

# ---------------------------------------------------------------------------
step "1. Boot"
start_container
wait_healthy || exit 1
ok "/api/health responds"

# ---------------------------------------------------------------------------
step "2. State landed on /data, not the anonymous volume"
check "/data/home/.paseo/config.json exists" \
    in_container test -f /data/home/.paseo/config.json

# The load-bearing assertion: upstream declares VOLUME /home/paseo, which
# Supervisor discards on update. Nothing may accumulate there.
if [[ -z "$(in_container sh -c 'ls -A /home/paseo 2>/dev/null')" ]]; then
    ok "/home/paseo is empty (anonymous volume unused)"
else
    bad "/home/paseo is NOT empty -- state would be lost on add-on update:"
    in_container ls -la /home/paseo | sed 's/^/        /'
fi

check "/data/home owned by uid 1000" \
    sh -c "[ \"\$(docker exec $NAME stat -c %u /data/home)\" = 1000 ]"

# ---------------------------------------------------------------------------
step "3. Seeded config"
cfg="$(in_container cat /data/home/.paseo/config.json)"
check "worktrees.root set"        sh -c "jq -e '.worktrees.root == \"/share/paseo/workspace\"' <<<'$cfg'"
check "relay disabled"            sh -c "jq -e '.daemon.relay.enabled == false' <<<'$cfg'"
check "app.paseo.sh CORS origin"  sh -c "jq -e '.daemon.cors.allowedOrigins | index(\"https://app.paseo.sh\")' <<<'$cfg'"
check "provider_overrides merged" sh -c "jq -e '.agents.providers.claude.label == \"Claude (verify)\"' <<<'$cfg'"

# ---------------------------------------------------------------------------
step "4. Tooling on PATH"
for bin in claude codex opencode ha gh git jq rg python3 hass-api; do
    check "$bin" in_container sh -lc "command -v $bin"
done

# ---------------------------------------------------------------------------
step "5. Home Assistant wiring"
check "/homeassistant/CLAUDE.md written"  test -f "${TESTDIR}/homeassistant/CLAUDE.md"
check "/homeassistant/.mcp.json written"  test -f "${TESTDIR}/homeassistant/.mcp.json"
check "MCP token not written literally" \
    sh -c "grep -q 'SUPERVISOR_TOKEN' '${TESTDIR}/homeassistant/.mcp.json' \
           && ! grep -q 'dummy-token' '${TESTDIR}/homeassistant/.mcp.json'"
check "mcp snippets written"              test -f "${TESTDIR}/data/home/.ha-paseo/mcp-snippets.md"

# ---------------------------------------------------------------------------
step "6. Agents taught about Home Assistant"
check "ha-inventory on PATH"        in_container sh -lc 'command -v ha-inventory'
check "claude: skill installed"     in_container test -f /data/home/.claude/skills/home-assistant/SKILL.md
check "claude: commands installed"  in_container test -f /data/home/.claude/commands/ha-inventory.md
check "claude: project CLAUDE.md"   test -f "${TESTDIR}/homeassistant/CLAUDE.md"
check "codex: global AGENTS.md"     in_container test -f /data/home/.codex/AGENTS.md
check "codex+opencode: project AGENTS.md" test -f "${TESTDIR}/homeassistant/AGENTS.md"
check "opencode: commands installed" in_container test -f /data/home/.config/opencode/command/ha-automation.md
check "opencode: global instructions" \
    sh -c "docker exec $NAME jq -e '.instructions | index(\"/usr/share/ha-paseo/home-assistant.md\")' \
           /data/home/.config/opencode/opencode.json"
check "opencode: HA mcp server" \
    sh -c "docker exec $NAME jq -e '.mcp.homeassistant.enabled == true' \
           /data/home/.config/opencode/opencode.json"

# The guide is what every provider ultimately reads; make sure it is real
# content and not an empty file from a botched copy.
check "guide is substantial" \
    sh -c "[ \"\$(docker exec $NAME sh -c 'wc -l < /usr/share/ha-paseo/home-assistant.md')\" -gt 50 ]"

# ---------------------------------------------------------------------------
step "7. Restart persistence"
marker="persist-$$"
in_container sh -c "mkdir -p /data/home/.claude && echo $marker > /data/home/.claude/verify-marker"
docker rm -f "$NAME" >/dev/null
start_container
wait_healthy || exit 1
check "credential dir survived restart" \
    sh -c "[ \"\$(docker exec $NAME cat /data/home/.claude/verify-marker)\" = $marker ]"
check "config.json survived restart" \
    in_container test -f /data/home/.paseo/config.json

# ---------------------------------------------------------------------------
step "8. Empty-password guard"
docker rm -f "$NAME" >/dev/null
jq '.password = ""' "${TESTDIR}/data/options.json" > "${TESTDIR}/data/options.json.tmp"
mv "${TESTDIR}/data/options.json.tmp" "${TESTDIR}/data/options.json"
out="$(docker run --rm \
    -v "${TESTDIR}/data:/data" -v "${TESTDIR}/share:/share" \
    "$IMAGE" 2>&1 || true)"
if grep -q "the 'password' option is empty" <<<"$out"; then
    ok "refuses to start without a password"
else
    bad "started (or failed differently) with an empty password:"
    printf '%s\n' "$out" | tail -10 | sed 's/^/        /'
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
