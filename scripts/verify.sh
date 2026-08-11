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

cleanup() { docker rm -f "$NAME" "${NAME}-mode" "${NAME}-svc" "${NAME}-shim" >/dev/null 2>&1 || true; kill "${STUB_PID:-}" 2>/dev/null || true; rm -f "${ENVDUMP:-}"; }
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
# A wrapper in /share/paseo/bin must beat both the bundled CLIs and any
# update-agents override, or the documented proxy-shim recipe silently loses.
check "/share/paseo/bin wins over npm-global and /usr/local" \
    sh -c "docker exec $NAME gosu paseo bash -lc 'echo \$PATH' | grep -qE '^/run/ha-paseo/shims:/share/paseo/bin:/data/home/.npm-global/bin:'"
check "shim in /share/paseo/bin shadows the bundled claude" \
    sh -c "docker exec $NAME sh -c 'mkdir -p /share/paseo/bin && printf \"#!/bin/sh\\necho SHIMMED\\n\" > /share/paseo/bin/claude && chmod +x /share/paseo/bin/claude' \
           && [ \"\$(docker exec $NAME gosu paseo bash -lc 'claude')\" = SHIMMED ] \
           && docker exec $NAME rm -f /share/paseo/bin/claude"
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

# The registration check matched a `path` key that does not exist on workspace
# entries (they use `cwd`), so a duplicate /homeassistant workspace was created
# on every restart. This container has now started twice.
ws_count="$(docker exec -e PASEO_PASSWORD=verify-secret "$NAME" gosu paseo sh -lc \
    'paseo workspace ls --json 2>/dev/null | jq "[.[]? | select(.cwd==\"/homeassistant\")] | length"' \
    2>/dev/null || echo "?")"
check "exactly one /homeassistant workspace after a restart" \
    sh -c "[ '$ws_count' = '1' ]"

# ---------------------------------------------------------------------------
step "9. Password is optional; the bind address follows it"

# No auto-generation. The password only guards a network-exposed listener, so
# without one the relay modes must bind loopback rather than sitting open.
cfg9="$(boot_with_options '{"connection_mode":"relay"}')"
check "starts with no password configured" \
    sh -c "jq -e '.version == 1' <<<'$cfg9'"
check "nothing is auto-generated" \
    sh -c "! docker logs ${NAME}-mode 2>&1 | grep -qi 'generated'"
check "no password file is created" \
    sh -c "! test -e '${TESTDIR}/mode/data/.paseo-generated-password'"
check "relay + no password binds loopback" \
    sh -c "docker exec ${NAME}-mode sh -c 'tr \"\\0\" \"\\n\" < /proc/1/environ' | grep -q '^PASEO_LISTEN=127.0.0.1:6767$' \
           || docker logs ${NAME}-mode 2>&1 | grep -q 'binding 127.0.0.1'"

cfg9="$(boot_with_options '{"connection_mode":"local"}')"
check "local + no password still starts" \
    sh -c "jq -e '.version == 1' <<<'$cfg9'"
check "local + no password warns loudly" \
    sh -c "docker logs ${NAME}-mode 2>&1 | grep -q 'NO PASSWORD SET'"

cfg9="$(boot_with_options '{"connection_mode":"relay","password":"averylongtestpassword123"}')"
check "password set binds 0.0.0.0 even on relay" \
    sh -c "docker logs ${NAME}-mode 2>&1 | grep -q 'listening on 0.0.0.0:6767'"
docker rm -f "${NAME}-mode" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Shims must intercept for EVERY caller -- a shell alias cannot, which is the
# whole reason this exists. The recursion guard is the load-bearing part: a
# `claude` shim whose command resolves `claude` via PATH would re-enter itself.
step "9b. Shims"

shimdir="${TESTDIR}/shim"
rm -rf "$shimdir"; mkdir -p "$shimdir"/{data,share}
cat > "${shimdir}/data/options.json" <<'SHIMEOF'
{"connection_mode":"local","password":"verifyshimpassword1234",
 "shims":[{"name":"claude","command":"echo WRAPPED real=$REAL","passthrough":["--version"]},
          {"name":"../evil","command":"echo nope"}]}
SHIMEOF
docker rm -f "${NAME}-shim" >/dev/null 2>&1 || true
docker run -d --name "${NAME}-shim" \
    -v "${shimdir}/data:/data" -v "${shimdir}/share:/share" "$IMAGE" >/dev/null
waited=0
while ! docker logs "${NAME}-shim" 2>&1 | grep -q "starting daemon on" && (( waited < 60 )); do
    sleep 2; waited=$((waited + 2))
done

check "shim intercepts the command" \
    sh -c "docker exec ${NAME}-shim gosu paseo bash -lc 'claude hi' | grep -q WRAPPED"
check "shim resolves the real binary without recursing" \
    sh -c "docker exec ${NAME}-shim gosu paseo bash -lc 'claude hi' | grep -q 'real=/usr/local/bin/claude'"
check "passthrough args reach the real binary" \
    sh -c "docker exec ${NAME}-shim gosu paseo bash -lc 'claude --version' | grep -q 'Claude Code'"
check "unsafe shim name rejected" \
    sh -c "docker logs ${NAME}-shim 2>&1 | grep -q 'invalid shim name'"
check "shims live outside /share and /data" \
    sh -c "! test -e '${shimdir}/share/paseo/bin/claude' && ! test -e '${shimdir}/data/claude'"
docker rm -f "${NAME}-shim" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "10. init_commands and background services"

svcdir="${TESTDIR}/svc"
rm -rf "$svcdir"; mkdir -p "$svcdir"/{data,share/paseo/services}
cat > "${svcdir}/data/options.json" <<'SVCEOF'
{"connection_mode":"local","password":"verifysvcpassword12345",
 "init_commands":["echo hello-from-init","false"],
 "services":["sh -c 'while true; do echo tick; sleep 3; done'","sh -c 'echo dying; exit 3'"]}
SVCEOF
printf '#!/bin/sh\nwhile true; do echo from-dropin; sleep 3; done\n' \
    > "${svcdir}/share/paseo/services/dropin.sh"
chmod +x "${svcdir}/share/paseo/services/dropin.sh"

docker rm -f "${NAME}-svc" >/dev/null 2>&1 || true
docker run -d --name "${NAME}-svc" \
    -v "${svcdir}/data:/data" -v "${svcdir}/share:/share" "$IMAGE" >/dev/null
waited=0
while ! docker logs "${NAME}-svc" 2>&1 | grep -q "restarting in 4s" && (( waited < 60 )); do
    sleep 3; waited=$((waited + 3))
done

check "init_commands run"                sh -c "docker logs ${NAME}-svc 2>&1 | grep -q 'hello-from-init'"
check "a failing init_command does not stop startup" \
    sh -c "docker logs ${NAME}-svc 2>&1 | grep -q 'init command failed'"
check "daemon still starts after services" \
    sh -c "docker logs ${NAME}-svc 2>&1 | grep -q 'starting daemon on'"
check "option service runs"              sh -c "docker logs ${NAME}-svc 2>&1 | grep -q '\[svc:sh\] tick'"
check "drop-in directory service runs"   sh -c "docker logs ${NAME}-svc 2>&1 | grep -q '\[svc:dropin.sh\] from-dropin'"
check "dead service is restarted"        sh -c "docker logs ${NAME}-svc 2>&1 | grep -q 'exited; restarting'"
check "restart backs off exponentially"  sh -c "docker logs ${NAME}-svc 2>&1 | grep -q 'restarting in 4s'"
# Two `sh -c` services would otherwise both log as [svc:sh].
check "duplicate service names disambiguated" \
    sh -c "docker logs ${NAME}-svc 2>&1 | grep -q '\[svc:sh-2\]'"
docker rm -f "${NAME}-svc" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
