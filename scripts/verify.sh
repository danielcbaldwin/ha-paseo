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

cleanup() { docker rm -f "$NAME" "${NAME}-mode" "${NAME}-opt" >/dev/null 2>&1 || true; kill "${STUB_PID:-}" 2>/dev/null || true; rm -f "${ENVDUMP:-}"; }
trap cleanup EXIT

check() {  # check <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

in_container() { docker exec "$NAME" "$@"; }

start_container() {
    cleanup
    # SYS_PTRACE is for the harness only, not the product: without it even root
    # cannot read /proc/<pid>/environ of the uid-1000 daemon, so the
    # provider_env propagation check cannot observe anything.
    docker run -d --name "$NAME" \
        --cap-add=SYS_PTRACE \
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
  "hostnames": ["homeassistant.local", ".lan"],
  "log_level": "info",
  "connection_mode": "local",
  "workspace_root": "/share/paseo/workspace",
  "expose_ha_config": true,
  "ha_mcp_url": "http://supervisor/core/mcp_server/sse",
  "provider_overrides": "{\"claude\":{\"label\":\"Claude (verify)\"}}",
  "provider_env": "{\"GEMINI_API_KEY\":\"verify-gemini-key\",\"bad name\":\"nope\"}",
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
check "relay disabled in local mode" sh -c "jq -e '.daemon.relay.enabled == false' <<<'$cfg'"
check "no stale relay endpoint"   sh -c "jq -e '.daemon.relay | has(\"endpoint\") | not' <<<'$cfg'"
check "app.baseUrl seeded"        sh -c "jq -e '.app.baseUrl == \"https://app.paseo.sh\"' <<<'$cfg'"
check "app.paseo.sh CORS origin"  sh -c "jq -e '.daemon.cors.allowedOrigins | index(\"https://app.paseo.sh\")' <<<'$cfg'"
check "provider_overrides merged" sh -c "jq -e '.agents.providers.claude.label == \"Claude (verify)\"' <<<'$cfg'"

# ---------------------------------------------------------------------------
step "4. Tooling on PATH"
for bin in claude codex opencode gemini copilot ha gh git jq rg python3 hass-api update-agents; do
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

# Debian's /etc/profile hardcodes PATH; a Paseo terminal pane is a login shell,
# so without the profile.d fix the wrapper and override dirs vanish there.
check "login shell keeps /share/paseo/bin on PATH" \
    sh -c "docker exec $NAME gosu paseo bash -lc 'echo \$PATH' | grep -q /share/paseo/bin"
check "login shell keeps npm-global on PATH" \
    sh -c "docker exec $NAME gosu paseo bash -lc 'echo \$PATH' | grep -q /data/home/.npm-global/bin"
# provider_env must reach the DAEMON, which is what spawns agents and terminal
# panes. Not PID 1 (that is tini, whose env was fixed at container start), and
# not `docker exec` (that gets the image env, not the entrypoint's exports).
# The daemon renames its processes ("Paseo Daemon"), so scan every pid and dump
# once to a file rather than re-running it inside each check's subshell.
ENVDUMP="$(mktemp)"
docker exec -u 0 "$NAME" sh -c \
    'for p in /proc/[0-9]*; do tr "\0" "\n" < $p/environ 2>/dev/null; done' \
    > "$ENVDUMP" 2>/dev/null || true

check "provider_env reaches the daemon" \
    grep -qx "GEMINI_API_KEY=verify-gemini-key" "$ENVDUMP"
check "invalid provider_env name rejected" \
    sh -c "docker logs $NAME 2>&1 | grep -q 'invalid name'"
check "invalid provider_env value never exported" \
    sh -c "! grep -q nope '$ENVDUMP'"
check "agent-login detects an API key" \
    sh -c "docker exec -e GEMINI_API_KEY=k $NAME gosu paseo agent-login | grep -q 'gemini.*logged in'"

check "update-agents status runs" \
    sh -c "docker exec $NAME gosu paseo update-agents status | grep -q gemini"

# ---------------------------------------------------------------------------
# Connection modes. Deliberately never exercises `relay`: that would register
# this throwaway container with Paseo's hosted relay service. The custom
# endpoint points at a dead local port so nothing leaves the container.
step "7. Connection modes"

boot_with_mode() {  # boot_with_mode <json-fragment>  -- password auto-added
    boot_with_options "$(printf '{"password":"m",%s}' "$1")"
}

boot_with_options() {  # boot_with_options <full-json> ; echoes the seeded config
    local opts="$1" dir="${TESTDIR}/mode"
    docker rm -f "${NAME}-mode" >/dev/null 2>&1 || true
    docker run --rm -v "${dir}:/wipe" alpine:3 sh -c 'rm -rf /wipe/* /wipe/.[!.]*' >/dev/null 2>&1 || true
    rm -rf "$dir"; mkdir -p "$dir"/{data,share}
    printf '%s\n' "$opts" > "${dir}/data/options.json"
    # An unparseable options file would make the add-on exit before seeding any
    # config, and every assertion below would then fail for the wrong reason.
    jq -e . "${dir}/data/options.json" >/dev/null \
        || { echo "BUG in boot_with_mode: invalid options.json" >&2; return 1; }
    docker run -d --name "${NAME}-mode" \
        -v "${dir}/data:/data" -v "${dir}/share:/share" "$IMAGE" >/dev/null
    local waited=0
    while [[ ! -f "${dir}/data/home/.paseo/config.json" ]] && (( waited < 40 )); do
        sleep 2; waited=$((waited + 2))
    done
    cat "${dir}/data/home/.paseo/config.json" 2>/dev/null || echo '{}'
}

mcfg="$(boot_with_mode '"connection_mode":"custom_relay","relay_endpoint":"127.0.0.1:59999","relay_use_tls":false')"
check "custom relay enabled"      sh -c "jq -e '.daemon.relay.enabled == true' <<<'$mcfg'"
check "custom relay endpoint set" sh -c "jq -e '.daemon.relay.endpoint == \"127.0.0.1:59999\"' <<<'$mcfg'"
check "custom relay useTls honoured" sh -c "jq -e '.daemon.relay.useTls == false' <<<'$mcfg'"

mcfg="$(boot_with_mode '"connection_mode":"custom_relay"')"
check "empty custom endpoint falls back to local" \
    sh -c "jq -e '.daemon.relay.enabled == false' <<<'$mcfg'"
check "fallback is warned about, not silent" \
    sh -c "docker logs ${NAME}-mode 2>&1 | grep -q \"falling back to 'local'\""
check "fallback does not reach the hosted relay" \
    sh -c "! jq -e '.daemon.relay | has(\"endpoint\")' <<<'$mcfg'"
docker rm -f "${NAME}-mode" >/dev/null 2>&1 || true

# jq's `//` treats false as absent, so every boolean defaulting to true used to
# ignore being switched off. expose_ha_config was the dangerous one: opting out
# of agent access to the HA config did nothing at all.
step "7b. Booleans can actually be set to false"

mcfg="$(boot_with_mode '"connection_mode":"local","expose_ha_config":false,"print_pairing_link":false')"
check "expose_ha_config:false is honoured" \
    sh -c "! docker logs ${NAME}-mode 2>&1 | grep -q 'Home Assistant config is mapped'"
check "print_pairing_link:false is honoured" \
    sh -c "! docker logs ${NAME}-mode 2>&1 | grep -q 'connection_mode is'"

# ---------------------------------------------------------------------------
step "8. Restart persistence"
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
step "9. Password is generated when none is configured"

# Previously this refused to boot. Refusing is bad UX for something that can be
# solved safely: generate a strong one and print it. Running UNauthenticated is
# still not an option -- 6767 is published and the daemon holds a Supervisor
# manager token.
pwdir="${TESTDIR}/mode"
cfg9="$(boot_with_options '{"connection_mode":"local"}')"

check "starts with no password configured" \
    sh -c "jq -e '.version == 1' <<<'$cfg9'"
check "generated password is logged" \
    sh -c "docker logs ${NAME}-mode 2>&1 | grep -q 'Generated Paseo password'"
check "generated password is persisted" \
    test -s "${pwdir}/data/.paseo-generated-password"
check "generated password is long enough" \
    sh -c "[ \"\$(wc -c < '${pwdir}/data/.paseo-generated-password')\" -ge 20 ]"
check "generated password file is not world readable" \
    sh -c "[ \"\$(stat -c %a '${pwdir}/data/.paseo-generated-password')\" = 600 ]"

# Restart against the same /data: it must reuse, not roll a new password on
# every boot (which would silently break every saved client).
pw_before="$(cat "${pwdir}/data/.paseo-generated-password")"
docker rm -f "${NAME}-mode" >/dev/null 2>&1 || true
docker run -d --name "${NAME}-mode" \
    -v "${pwdir}/data:/data" -v "${pwdir}/share:/share" "$IMAGE" >/dev/null
waited=0
while ! docker logs "${NAME}-mode" 2>&1 | grep -q "connection mode:" && (( waited < 40 )); do
    sleep 2; waited=$((waited + 2))
done
check "generated password is reused across restarts" \
    sh -c "[ \"\$(cat '${pwdir}/data/.paseo-generated-password')\" = '$pw_before' ]"
check "reuse is reported, not silently regenerated" \
    sh -c "docker logs ${NAME}-mode 2>&1 | grep -q 'reusing the one in'"
docker rm -f "${NAME}-mode" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# The generated password is written back into the add-on's own options so it is
# visible in the Configuration tab. Supervisor REPLACES options rather than
# merging, so the add-on must send the full set back -- a partial write would
# wipe every other setting. That is the assertion that matters here.
step "10. Generated password is written back to the add-on options"

STUB_PORT=17654
STUB_CAPTURE="$(mktemp)"
python3 "${ROOT}/scripts/supervisor-stub.py" "$STUB_PORT" "$STUB_CAPTURE" &
STUB_PID=$!
sleep 1

pwdir2="${TESTDIR}/optwrite"
rm -rf "$pwdir2"; mkdir -p "$pwdir2"/{data,share}
echo '{"connection_mode":"local"}' > "${pwdir2}/data/options.json"
docker rm -f "${NAME}-opt" >/dev/null 2>&1 || true
docker run -d --name "${NAME}-opt" \
    --add-host=supervisor-stub:host-gateway \
    -e SUPERVISOR_TOKEN=stub-token \
    -e "SUPERVISOR_API_BASE=http://supervisor-stub:${STUB_PORT}" \
    -v "${pwdir2}/data:/data" -v "${pwdir2}/share:/share" "$IMAGE" >/dev/null
waited=0
while [[ ! -s "$STUB_CAPTURE" ]] && (( waited < 60 )); do sleep 2; waited=$((waited + 2)); done

check "options write was attempted"        test -s "$STUB_CAPTURE"
check "password included in the write"     sh -c "jq -e '.options.password | length >= 20' '$STUB_CAPTURE'"
check "existing options preserved (log_level)" \
    sh -c "jq -e '.options.log_level == \"info\"' '$STUB_CAPTURE'"
check "existing options preserved (workspace_root)" \
    sh -c "jq -e '.options.workspace_root == \"/share/paseo/workspace\"' '$STUB_CAPTURE'"
check "log points at the Configuration tab" \
    sh -c "docker logs ${NAME}-opt 2>&1 | grep -q \"written into the\""
check "no stale on-disk copy left behind" \
    sh -c "! test -f '${pwdir2}/data/.paseo-generated-password'"

kill "$STUB_PID" 2>/dev/null || true
rm -f "$STUB_CAPTURE"
docker rm -f "${NAME}-opt" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
