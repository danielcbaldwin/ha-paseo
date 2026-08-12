# Paseo — Home Assistant add-on

Runs the [Paseo](https://paseo.sh) daemon on your Home Assistant box, so you can
drive Claude Code, Codex, OpenCode and Copilot from the Paseo phone, desktop or
web client — including agents that work directly on your Home Assistant
configuration.

---

## Before you start

- **amd64 or aarch64 only.** Upstream Paseo has no 32-bit ARM build, so a Pi 3
  or any armv7 host cannot run this.
- **This is not a lightweight add-on.** Paseo plus four agent CLIs wants real
  CPU and a couple of GB of RAM once agents are running.
- **Read the security section below before enabling it on your primary
  instance.** With the default options an agent can rewrite your automations
  and restart Core.

---

## Setup

1. Install the add-on and open **Configuration**.
2. Leave **password** blank unless you want direct/LAN access — with the
   default `relay` mode it is not needed. See "Authentication" below.
3. Add any hostname you will reach it by to **hostnames** (Paseo returns
   `403 Host not allowed` for names that are not on the list). IP addresses and
   `localhost` always work without an entry. The defaults cover `*.lan` and
   `homeassistant.local`.
4. Start the add-on and watch the log for `starting Paseo`.

### Connecting a client

There is **no sidebar panel**, by design — see "Why no Ingress" below.

How clients reach the daemon is controlled by **`connection_mode`**:

| `connection_mode` | What it does | When to use it |
| --- | --- | --- |
| **`relay`** *(default)* | Paseo's hosted relay. No router or network changes; a join link is printed to the add-on log. Traffic is end-to-end encrypted between your client and the daemon. | You want it to just work, including from outside your network. |
| **`local`** | No relay at all. Direct connections only. | The daemon is reachable already — same LAN, or you have a VPN to it — and you would rather nothing transited a third party. |
| **`custom_relay`** | A relay you run yourself. The image already contains `@getpaseo/relay`. | You want off-network access without depending on Paseo's hosted service. |

Whatever the mode, a **direct connection always works** when you can reach the
box: in the Paseo app, Settings → Add host → Direct connection, host = the HA
box's IP, port `6767`, SSL **off**, plus your password. No join link involved.
The **Open Web UI** button on the add-on page works too.

#### Running your own relay

Point the add-on at it:

```yaml
connection_mode: custom_relay
relay_endpoint: relay.example.com:443    # where the daemon connects
relay_use_tls: true
relay_public_endpoint: ""                # optional: what clients are told to use,
relay_public_use_tls: true               #   if it differs from the above
```

`relay_endpoint` is required in this mode. If you leave it empty the add-on falls
back to **`local`** and says so in the log — it will not quietly send your
traffic to the hosted relay you just opted out of.

Switching back to `relay` or `local` later removes the endpoint keys from the
config, so a stale self-hosted address cannot linger.

If you also self-host the Paseo web app, set `app_base_url` to its origin
(default `https://app.paseo.sh`); it is what pairing links point at.

### Authentication

**The password is optional, and only does anything for direct connections.**

Paseo's own guidance is that password auth "is primarily useful for direct LAN
or VPN connections". The relay does not use it: the daemon holds a persistent
ECDH keypair and refuses commands until the pairing handshake completes, so
*the pairing link is the credential* there. That is why a desktop Paseo install
usually has no password — it binds `127.0.0.1` and is reached over the relay.

So the bind address follows from whether you set one:

| `password` | `connection_mode` | Binds | Result |
| --- | --- | --- | --- |
| set | any | `0.0.0.0:6767` | Protected. Direct connections, LAN browser and **Open Web UI** all work. |
| empty | `relay` / `custom_relay` | `127.0.0.1:6767` | Relay only. Nothing is exposed, so nothing needs guarding. **Open Web UI and LAN browser access do not work.** |
| empty | `local` | `0.0.0.0:6767` | **Exposed with no authentication.** Allowed, but warned about loudly in the log. |

Nothing is auto-generated, and no password is stored on disk by the add-on.

> **Home Assistant cannot hide an option based on another option's value** — its
> add-on schema has no conditional fields. So `password` is always visible in
> the Configuration tab even though it only matters for `local`. Leave it blank
> unless you are using `local` (or want the web UI).

That last row is the one to think about: `local` with no password means anyone
who can reach port 6767 controls a daemon holding a Supervisor token with
`manager` rights — enough to rewrite automations or remove add-ons. The add-on
will still start, because you asked for the password to be optional, but it says
so in the log every time.

The password is hashed in memory at startup and is **not** written into
`config.json`.

### Getting the join / pairing URL

A pairing link is only needed for the **relay**. For a direct connection you
just enter host, port `6767` and the password — there is nothing to pair.

Getting a shell inside a Home Assistant add-on is awkward, so the link is put
where you can actually read it:

1. Make sure `connection_mode` is `relay` (the default) or `custom_relay`.
2. Restart the add-on.
3. **Settings → Add-ons → Paseo → Log.** The join URL is printed in a banner:

   ```
   ================ Paseo pairing link ================
     https://...
     Open it on your phone, or scan the QR from a terminal
   ====================================================
   ```

Set `print_pairing_link: false` to suppress that if you would rather it not sit
in the log — **the link grants access to the daemon, so treat it as a secret**.

To get it on demand instead, open a terminal pane in the Paseo web UI and run:

```bash
paseo daemon pair          # prints a scannable QR code and the link
paseo daemon pair --json   # just the data
```

The add-on will not enable the relay for you. `paseo daemon pair` offers to turn
it on interactively, and a background job silently enabling a hosted relay is
not something that should happen behind your back — so in `local` mode the log
tells you how to connect directly instead.

### Logging the agents in

Open a **terminal pane inside a Paseo workspace** — that is the shell you get in
this add-on, and it is all you need. Then run:

```bash
agent-login     # who is logged in, and exactly what to type for who isn't
```

Credentials land under `/data/home/` and survive restarts *and* add-on updates,
so each of these is a one-time job.

| Provider | Command | Works headless? |
| --- | --- | --- |
| **Claude Code** | `claude`, then `/login` and paste the code back. Or `claude setup-token` for a long-lived token (needs a subscription) | Yes |
| **OpenCode** | `opencode auth login` — interactive provider picker | Yes |
| **Copilot** | `copilot login` — device-code flow | Yes |
| **Codex** | `codex login` | **No** — see below |
| **Gemini** | no login subcommand exists | **No** — see below |

#### The two that need help

**Codex** uses a browser flow with a callback to `localhost:1455`. Your browser
resolves `localhost` to *your laptop*, not the Home Assistant box, so it cannot
complete from a remote container. Either tunnel it:

```bash
ssh -L 1455:localhost:1455 you@ha-host     # then run `codex login` in the pane
```

or skip the browser entirely:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
codex login status
```

**Gemini CLI has no login subcommand at all.** Auth is either the interactive
"Login with Google" picker in its TUI — same localhost-callback problem — or an
API key. In practice, use the API key.

#### API keys, no interactive flow

Set the `provider_env` option to a JSON object and restart:

```yaml
provider_env: >-
  {"GEMINI_API_KEY": "...", "OPENAI_API_KEY": "...", "ANTHROPIC_API_KEY": "..."}
```

These are exported to the daemon and inherited by every agent and terminal pane
it spawns. Key names are validated; anything that is not a valid shell
identifier is logged and skipped rather than executed.

One wrinkle if you go poking around from the host: a shell obtained with
`docker exec` will **not** see them. `docker exec` starts from the image
environment, not from the running entrypoint's exports. Use a terminal pane in
the Paseo UI, which is a child of the daemon and inherits them properly.

The field is masked in the UI, but add-on options are stored **in plaintext** in
`/data/options.json` and are captured in backups. Where an interactive login
works, prefer it — it keeps a key off disk entirely.

---

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `password` | *(empty)* | Optional. Only used for direct connections — see Authentication. Leaving it blank makes relay modes bind loopback. |
| `hostnames` | `homeassistant.local`, `.lan` | DNS names allowed to reach the daemon. Add any other name you use; IPs always work. |
| `log_level` | `info` | `trace`, `debug`, `info`, `warn`, `error`. |
| `connection_mode` | `relay` | `relay`, `local`, or `custom_relay`. See above. |
| `relay_endpoint` | `""` | Required for `custom_relay` — where the daemon connects. |
| `relay_public_endpoint` | `""` | Optional — what clients are told to connect to, if different. |
| `relay_use_tls` / `relay_public_use_tls` | `true` | TLS for the two endpoints above. |
| `app_base_url` | `https://app.paseo.sh` | Web app origin used in pairing links. Change if you self-host it. |
| `workspace_root` | `/share/paseo/workspace` | Where worktrees are created. Kept on `/share` so clones stay out of add-on backups. |
| `expose_ha_config` | `true` | Register `/homeassistant` as a workspace and write agent config into it. |
| `ha_mcp_url` | `http://supervisor/core/mcp_server/sse` | Requires the **MCP Server** integration in Home Assistant. |
| `provider_overrides` | `"{}"` | JSON string merged into `agents.providers`. See below. |
| `provider_env` | `"{}"` | JSON string of env vars exported to the daemon and its agents — API keys for providers whose login flow will not work headless. Masked in the UI, plaintext on disk. |
| `auto_update_agents` | `false` | Update every agent CLI to latest on each boot. Slow, network-dependent, not reproducible. |
| `print_pairing_link` | `true` | Print the relay join URL to the add-on log at startup. No effect in `local` mode. |
| `extra_npm_packages` | `[]` | Installed into the persistent `/data/home/.npm-global` at each boot. |
| `extra_apt_packages` | `[]` | Installed at each boot. Not persistent — apt state is in the image layer. |
| `init_commands` | `[]` | One-shot commands run at each start, before the daemon. Failures are logged, not fatal. |
| `services` | `[]` | Long-running commands, supervised and restarted with backoff. See below. |
| `shims` | `[]` | Intercept a command name (e.g. `claude`) with a wrapper, for every caller. See Shims. |

---

## Working on Home Assistant

With `expose_ha_config` on, the add-on:

- maps your config to **`/homeassistant`** (read/write) and registers it as a
  Paseo workspace;
- writes `/homeassistant/CLAUDE.md` with house rules (validate with
  `ha core check`, never hand-edit `.storage/`);
- writes `/homeassistant/.mcp.json` pointing Claude Code at Home Assistant's MCP
  server. The Supervisor token is referenced as `${SUPERVISOR_TOKEN}` rather
  than written to disk — it rotates on every start, and that directory ends up
  in your backups.

Both files are only created if they do not already exist, so your own versions
are never overwritten.

### Tools available to agents

- **`ha`** — the Supervisor CLI: `ha core check`, `ha core logs`,
  `ha addons list`, `ha backups new`.
- **`hass-api`** — an authenticated wrapper over the Core REST API that needs no
  MCP setup and works from every provider:

  ```bash
  hass-api GET  states/light.kitchen
  hass-api POST services/light/turn_on '{"entity_id":"light.kitchen"}'
  ```

- **`ha-inventory`** — live discovery of *your* instance, so agents stop
  guessing entity ids:

  ```bash
  ha-inventory                    # version, entity counts by domain, areas, add-ons
  ha-inventory entities light     # every light, with state and friendly name
  ha-inventory search kitchen     # fuzzy match on entity id and friendly name
  ha-inventory services light     # services in a domain, with their fields
  ha-inventory areas              # areas and their entities
  ha-inventory state light.porch  # full state and attributes
  ```

  Output is deliberately compact. A raw `GET /states` on a real house is tens of
  thousands of tokens and buries whatever you were looking for.

### How each provider learns about Home Assistant

The canonical guide lives at `/usr/share/ha-paseo/home-assistant.md` — how to
talk to Home Assistant, the file layout, the safety rules (`ha core check`
before restart, never hand-edit `.storage/`), YAML traps like unquoted `on`/`off`,
and a debugging workflow. It is surfaced differently per provider, because each
one discovers instructions its own way:

| Provider | How it finds out |
| --- | --- |
| **Claude Code** | A `home-assistant` **skill** at `~/.claude/skills/`, pulled into context only when the task is actually about Home Assistant. Plus `/homeassistant/CLAUDE.md` and an MCP server. |
| **OpenCode** | The guide is added to `instructions` in `~/.config/opencode/opencode.json`, so it applies in **every** workspace, not just `/homeassistant`. Plus commands and an MCP server entry using `{env:SUPERVISOR_TOKEN}`. |
| **Codex** | `$CODEX_HOME/AGENTS.md` for global guidance, plus `/homeassistant/AGENTS.md`. |

Slash commands are installed for both Claude Code and OpenCode:

| Command | Does |
| --- | --- |
| `/ha-inventory` | Show what exists on this instance and flag anything odd |
| `/ha-check` | `ha core check`, then explain any failure at the offending line |
| `/ha-logs` | Triage the error log, grouped, with the noise called out as noise |
| `/ha-automation` | Write an automation grounded in real entities, validated and reloaded without a restart |

Skills and commands are **rewritten on every start**, so add-on updates reach
the agents. `/homeassistant/CLAUDE.md` and `/homeassistant/AGENTS.md` are only
created if missing, so your own edits are never overwritten.

Codex keeps MCP servers in TOML, and merging a file this add-on does not own
risks destroying your settings — so that one is a paste-in snippet at
`/data/home/.ha-paseo/mcp-snippets.md` rather than something done behind your
back. `hass-api` and `ha-inventory` work from Codex regardless.

---

## Custom providers (including TeamClaude)

Two seams, no add-on changes required.

`/share/paseo/bin` is **first** on `PATH` — ahead of the bundled agent CLIs and
any `update-agents` override — so a wrapper there wins everywhere. Drop a script
in (via Samba, the file editor add-on, or `scp`) and optionally point a provider
at it with
`provider_overrides` — a JSON **string**, since Supervisor options have no JSON
type:

```yaml
provider_overrides: >-
  {"claude": {"label": "Claude (Ednition)", "command": ["claude-teamclaude"]},
   "claude-tapresearch": {"extends": "claude", "label": "Claude (TapResearch)",
                          "env": {"CLAUDE_CONFIG_DIR": "/data/home/.claude-tap"}}}
```

The value is merged recursively into `agents.providers`, so an override can add
`env` or `label` without restating the whole provider. Invalid JSON is logged and
ignored rather than blocking startup.

If you are porting a wrapper from another machine, remember to repoint whatever
it uses as the real binary at `/usr/local/bin/claude`.

---

## Shims: intercepting a command like `claude`

`teamclaude alias --install` — and any other `alias`-based approach — **cannot
work with Paseo**, and this is not an add-on limitation. It writes:

```
alias claude='teamclaude run --'
```

Shell aliases exist only in *interactive* shells and are **not inherited across
`execve`**. Paseo spawns the `claude` binary directly, so no shell is ever
consulted. TeamClaude's own help says as much under `env`: *"handy for agent
multiplexers that spawn claude themselves instead of via `teamclaude run`"*.

Intercepting every caller needs a **real executable earlier on `PATH`**. The
`shims` option builds one for you:

```yaml
shims:
  - target: /usr/local/bin/claude
    env_from: teamclaude env --no-mitm
    require_port: 3456
    passthrough: ["--version", "-v", "auth", "doctor", "mcp", "update"]
```

| Field | Meaning |
| --- | --- |
| `target` | **Absolute path** of the binary being wrapped. Preferred: no PATH guessing, and a wrong path is reported at startup instead of failing later. |
| `name` | Command name to intercept. Defaults to the target's basename. |
| `env_from` | Run this, `eval` its stdout, then exec the **real** command. For proxies and account routers. |
| `command` | Run this **instead**. The caller's arguments are appended. |
| `script` | A full shell body, with `"$@"` and `$REAL` in scope. Escape hatch. |
| `require_port` | Only run `env_from` if something is listening on this local port. |
| `passthrough` | First arguments that bypass the wrapper and go straight to the real binary. |

Use exactly one of `env_from`, `command` or `script`.

**Prefer `env_from` for proxies.** A wrapper that *replaces* the command — such
as `command: teamclaude run --`— inserts another process and lets that process
write to stdout. Paseo speaks a **stdio protocol** to its agents, so a single
stray line (`teamclaude run` prints `Created config at …` on first use) derails
the session and it hangs. `env_from` sets environment and then execs the real
binary, leaving stdout byte-identical — which the test suite asserts.

Shims are written to `/run/ha-paseo/shims`, which is **first on `PATH`** — ahead
of `/share/paseo/bin`, `update-agents` overrides and the bundled CLIs. They are
regenerated on every start and live nowhere else, so **nothing is written to
`/share` or `/data`** and deleting the option deletes the shim.

Two things the generated shim handles that a hand-written one usually gets wrong:

- **Recursion.** The shim directory is removed from `PATH` before your command
  runs, so a wrapper that itself invokes `claude` finds the real binary rather
  than re-entering the shim and forking until the container dies.
- **`$REAL`.** Set to the absolute path of the command being shadowed, so a
  wrapper can `exec "$REAL" "$@"` directly.

`passthrough` matters more than it looks: Paseo probes providers with
`--version` and `auth status` concurrently on every provider-features request.
Routing those through a proxy makes the daemon wait on it, which can stall its
websocket.

### Full TeamClaude setup

```yaml
extra_npm_packages:
  - "@karpeleslab/teamclaude"

services:
  - teamclaude server --headless

shims:
  - target: /usr/local/bin/claude
    env_from: teamclaude env --no-mitm
    require_port: 3456
    passthrough: ["--version", "-v", "auth", "doctor", "mcp", "update"]
```

**`require_port` is not optional here.** `teamclaude env` prints
`ANTHROPIC_BASE_URL` whether or not the proxy is running — it only *comments*
that nothing is listening. Without the guard, a down proxy points `claude` at a
dead port and it hangs. With it, a down proxy degrades to plain `claude`.

`teamclaude service install` writes a systemd user unit and there is no systemd
in a container — `services` is the equivalent, and supervises it the same way.
`--no-mitm` is worth keeping: MITM mode exports `HTTPS_PROXY`, which MCP servers
injected into agents inherit, tunnelling unrelated traffic through the proxy.

Log in once with `teamclaude login` from a terminal pane; credentials persist
under `/data/home`.

To pin specific workspaces to specific accounts, set `TC_ACCT` per provider via
`provider_overrides` rather than branching inside the shim.

## Running your own commands and services

Some tools you want alongside the agents are servers, not one-shot binaries —
a TeamClaude proxy being the obvious case. Two options cover that.

### `services` — long-running, supervised

A list of shell commands. Each runs as the `paseo` user in a login shell (so
`/share/paseo/bin` and your `update-agents` overrides are on `PATH`), and is
**restarted if it exits**, with backoff doubling from 2s to a 60s ceiling so a
broken command cannot hot-loop the machine.

```yaml
services:
  - teamclaude serve --port 8088
  - python3 /share/paseo/bin/metrics.py
```

Output is prefixed and lands in the add-on log next to everything else:

```
[svc:teamclaude] listening on :8088
[svc:teamclaude] exited; restarting in 2s
```

Services are named after the command's first word. Two commands starting with
the same word get `-2`, `-3` suffixes so the log stays readable.

### `/share/paseo/services/` — drop-in scripts

Any **executable** file in that directory is run as a service too, with no
config edit. Useful when the thing you are running deserves to be a real script
you can version outside the add-on:

```bash
# /share/paseo/services/teamclaude.sh
#!/bin/sh
exec teamclaude serve --port 8088
```

`chmod +x` it — non-executable files are skipped with a warning rather than
silently ignored.

### `init_commands` — one-shot, at startup

Runs once each start, in order, before the daemon. For setup rather than
servers. A failure is logged and startup continues, so a broken command cannot
take the add-on down:

```yaml
init_commands:
  - git config --global user.email "me@example.com"
```

For installing packages, prefer `extra_apt_packages` / `extra_npm_packages`.

### Reaching a service you started

These run inside the add-on container. Other processes in the container reach
them on `127.0.0.1:<port>`. To reach one from **outside**, add the port under
the add-on's **Network** section — nothing is published automatically.

## How state is stored

Everything mutable lives under **`/data/home`**:

```
/data/home/.paseo/      daemon state, config.json, agent history
/data/home/.claude/     Claude Code credentials
/data/home/.codex/      Codex credentials
/data/home/.npm-global/ extra_npm_packages
```

This matters more than it looks. The upstream Paseo image declares
`VOLUME /home/paseo`, which Supervisor does not bind — Docker gives it an
anonymous volume that is **discarded on every add-on update**. The add-on
repoints `HOME`, `PASEO_HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and the `XDG_*`
paths at `/data`, so nothing important is ever written to that volume.

Environment variables alone are not sufficient, and this is the subtle part:
`gosu` — which both the upstream entrypoint and this add-on use to drop to
uid 1000 — derives `$HOME` from `/etc/passwd` and re-exports it, overriding the
inherited value for every child process. The image therefore also runs
`usermod --home /data/home paseo`, so passwd and the environment agree. Without
that, agent credentials quietly land on the throwaway volume and disappear at
the next update. `scripts/verify.sh` asserts `/home/paseo` stays empty for
exactly this reason.

`/data` is included in Supervisor backups, so your agent credentials are too.
Worktrees default to `/share` to keep backup size down, though `/share` is still
captured in a *full* backup.

---

## Security

Read this bit.

With the default options this add-on gives a language model:

- **read/write on your Home Assistant configuration** (`/homeassistant`),
- **a Supervisor token with `manager` role** — enough to restart Core, and to
  install, reconfigure or remove other add-ons,
- **the Core REST API**, so it can call any service on any entity.

That is the point of the add-on, and it is genuinely dangerous. What is in place:

- The password is mandatory; the add-on will not start without one.
- Agents run with Paseo's normal permission prompts. Nothing here passes
  `--dangerously-skip-permissions`, and you should not add it.
- The seeded `CLAUDE.md` requires `ha core check` before any restart.

What is on you:

- Try it on a non-critical instance first.
- Take a backup before letting an agent loose on your config.
- Do not expose port 6767 to the internet. Keep it on your LAN, reach it over a
  VPN, or use the relay.

### AppArmor

The add-on ships `apparmor: false`. Paseo spawns many subprocesses, manages git
worktrees and can drive a browser; the default Supervisor profile blocks enough
of that to produce confusing failures. A tailored profile is follow-up work
rather than something to pretend is already done.

---

## Keeping things up to date

Three separate things move at very different speeds, so they update differently.

### The agent CLIs (claude, codex, opencode, copilot, gemini)

These release constantly — Claude Code often ships several times a week — and
waiting on an add-on release for each one would be absurd. The image ships
**pinned** versions, and you can move ahead of them yourself.

From a terminal pane in the Paseo UI:

```bash
update-agents status          # what is installed, and what is shadowing what
update-agents all             # update every agent CLI to latest
update-agents claude          # just one
update-agents claude@2.1.300  # pin one to an exact version
update-agents reset           # drop the overrides, go back to image versions
```

Updates install into `/data/home/.npm-global`, which comes **first** on `PATH`
and lives on the persistent volume — so they survive restarts *and* add-on
updates.

**That is also the catch.** Once an agent is installed there it shadows the
image copy permanently, and future add-on updates will no longer change the
version you actually run. `update-agents status` flags this explicitly, and
`update-agents reset` undoes it. If an add-on update seems not to have changed
your Claude Code version, this is why.

Set `auto_update_agents: true` to run `update-agents all` on every boot. It is
off by default: it makes startup slow and network-dependent, and gives up
reproducibility.

### Paseo itself

Pinned to an exact upstream release tag in `paseo/build.yaml`, never `latest`.
It moves when the add-on is rebuilt and republished, and you take it by updating
the add-on in Home Assistant like any other.

### Knowing when anything is behind

Everything being pinned is good for reproducibility and bad for staleness —
nothing would tell you the world had moved on. A scheduled workflow
(`.github/workflows/check-updates.yaml`) runs weekly, compares every pin against
upstream, and keeps a single **"Upstream updates available"** issue up to date
with a table of what is behind. Run it on demand from the Actions tab.

Why pin at all? Unpinned `npm install -g` means rebuilding add-on version
`0.3.1-1` in three months silently produces different agent versions — the
version number stops meaning anything.

## Updating Paseo

The base image is pinned to an exact upstream release tag in `paseo/build.yaml`,
never `latest`. The add-on linter rejects digest references there, so the
resolved digest is recorded in a comment alongside it for audit rather than
enforced by the build. To move to a new Paseo release:

1. Confirm the tag has both `linux/amd64` and `linux/arm64`.
2. Update both `build_from` lines and the digest comment in `build.yaml`.
3. Add a `CHANGELOG.md` entry, push, then tag `v0.3.2-1`.

Use the release script, which enforces the ordering below:

```bash
./scripts/release.sh 0.3.2-1
```

**Do not edit `version` in `config.yaml` by hand.** The tag is the source of
truth; CI writes the version into the image it builds and then commits the bump
to `main` itself, but only once both architectures have published.

Because CI pushes to `main`, a local checkout goes stale after every release.
Tagging from a stale base puts the tag on divergent history — the script
refuses, rebasing first and checking the tag is reachable from `origin/main`.

That ordering matters. Supervisor reads `config.yaml` from the default branch
and pulls `<image>:<that version>`. Bumping it before the images exist makes
every instance offer an update that fails with `[404] manifest unknown` — which
is exactly what happened releasing `0.3.1-2`. Releasing is now just:

```bash
./scripts/release.sh 0.3.2-1
```

---

## The terminal

Terminal panes start a **login** shell as the `paseo` user. The container ships
no dotfiles of its own, so on first start the add-on seeds three into
`/data/home`:

| File | What it gives you |
| --- | --- |
| `.bashrc` | 50k-line shared history appended per command, colour, git-aware prompt, aliases, bash-completion, `gh` completion (cached), fzf key bindings |
| `.bash_profile` | Sources `.bashrc` — a login shell would not otherwise read it |
| `.inputrc` | **Up/Down searches history for what you have typed**, case-insensitive completion, Ctrl-arrow word jumps |

They are **only written when absent**, live on `/data`, and survive restarts and
add-on updates — so edit them freely. Delete one and restart to get the default
back.

Also installed for interactive use: `bash-completion`, `fzf` (Ctrl-R over
history), `tree`, `htop`, plus the `ripgrep`, `jq`, `less` and `nano` that were
already there. Add more with `extra_apt_packages`.

Completion works through bash-completion's lazy loader, so `git <Tab>`,
`apt <Tab>` and `ssh <Tab>` all resolve on first use.

The prompt shows the working directory, the git branch when there is one, and
the exit status only when a command fails.

## Diagnosing: `ha-paseo-doctor`

Run it from a terminal pane. It reads **live state**, so it does not matter how
long ago the add-on started — with `log_level: debug` the daemon floods the log
and the startup lines scroll away within seconds.

```
$ ha-paseo-doctor

Add-on
          version   0.3.1-10
          listen    0.0.0.0:6767
          mode      relay
          password  (blank)

Daemon
  OK      responding on 127.0.0.1:6767

Shims
  OK      claude -> /usr/local/bin/claude  (require_port 3456)

Services
  PROBLEM NOT running: teamclaude server --headless

TeamClaude (this container -- NOT your desktop)
  PROBLEM no accounts configured here -- run 'teamclaude login' in this terminal
  PROBLEM proxy NOT listening on 3456
```

It covers the things that are otherwise invisible: whether a shim is actually
in effect for a given command name, whether a service is running or
crash-looping, which ports are listening, and whether per-container credentials
exist.

**Accounts are per-machine.** A proxy like TeamClaude keeps its accounts in its
own config inside this container (`/data/home/.config/`). Logging in on your
desktop does not carry over — you must log in once from a terminal pane here.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Open Web UI does nothing / LAN browser cannot connect | No password set, so relay modes bind loopback. Set a password, or use `connection_mode: local`. |
| `403 Host not allowed` | Add the DNS name you are using to `hostnames`. |
| Web UI loads but will not connect | The static UI is served without auth; the API is not. Add a direct connection with the password. |
| A provider is missing from the app | Its CLI is not installed or not on `PATH`. Check `extra_npm_packages`, or `/share/paseo/bin` for wrappers. |
| A provider is there but every request fails | Not logged in. Run `agent-login` in a terminal pane. |
| `codex login` opens a browser that never completes | Its callback is `localhost:1455`, which is your laptop, not the HA box. Tunnel it or use `--with-api-key`. |
| An add-on update did not change my Claude Code version | An `update-agents` override in `/data` is shadowing the image copy. Run `update-agents status`, then `update-agents reset`. |
| A wrapper in `/share/paseo/bin` is not found in a terminal | Should not happen — `/etc/profile.d/ha-paseo-path.sh` restores `PATH` in login shells. Check the file survived, and that the script is executable. |
| MCP server shows as failed | The **MCP Server** integration is not enabled in Home Assistant. `hass-api` works regardless. |
| Agents cannot reach the internet or your other machines | Add-on containers route through the HA host; check the host's own connectivity first. |

Daemon logs are in the add-on log and at `/data/home/.paseo/daemon.log`.
