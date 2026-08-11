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
2. Set a **password**. The add-on refuses to start without one — port 6767 is
   published on your LAN and the daemon holds a Supervisor token.
3. Add any hostname you will reach it by to **hostnames** (Paseo returns
   `403 Host not allowed` for names that are not on the list). IP addresses and
   `localhost` always work without an entry. The defaults cover `*.lan`,
   `*.ts.net` and `homeassistant.local`.
4. Start the add-on and watch the log for `starting Paseo`.

### Connecting a client

There is **no sidebar panel**, by design — see "Why no Ingress" below. Use one
of these instead:

| Route | How |
| --- | --- |
| **Tailscale** (recommended) | In the Paseo app: Settings → Add host → Direct connection. Host = the HA box's Tailscale IP, Port = `6767`, SSL **off**, password as configured. **No join URL needed.** |
| **LAN** | Same, using the HA box's LAN IP. |
| **Relay** | Set `relay_enabled: true` and restart — the join link is printed to the add-on log. |
| **Browser** | The **Open Web UI** button on the add-on page. |

### Getting the join / pairing URL

A pairing link is only needed for the **relay**. For a direct connection you
just enter host, port `6767` and the password — there is nothing to pair.

Getting a shell inside a Home Assistant add-on is awkward, so the link is put
where you can actually read it:

1. Set `relay_enabled: true` in the add-on Configuration tab.
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
not something that should happen behind your back — so when `relay_enabled` is
off, the log tells you how to connect directly instead.

### Logging the agents in

Open a terminal pane inside a Paseo workspace and run `claude`, `codex` or
`opencode` once to complete each OAuth flow. Credentials land under
`/data/home/` and survive restarts *and* add-on updates.

---

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `password` | *(empty)* | **Required.** Masked in the UI. Hashed by the daemon at startup. |
| `hostnames` | `homeassistant.local`, `.lan`, `.ts.net` | DNS names allowed to reach the daemon. |
| `log_level` | `info` | `trace`, `debug`, `info`, `warn`, `error`. |
| `relay_enabled` | `false` | Paseo's hosted end-to-end encrypted relay. Off by default. |
| `workspace_root` | `/share/paseo/workspace` | Where worktrees are created. Kept on `/share` so clones stay out of add-on backups. |
| `expose_ha_config` | `true` | Register `/homeassistant` as a workspace and write agent config into it. |
| `ha_mcp_url` | `http://supervisor/core/mcp_server/sse` | Requires the **MCP Server** integration in Home Assistant. |
| `provider_overrides` | `"{}"` | JSON string merged into `agents.providers`. See below. |
| `auto_update_agents` | `false` | Update every agent CLI to latest on each boot. Slow, network-dependent, not reproducible. |
| `print_pairing_link` | `true` | Print the relay join URL to the add-on log at startup (only when `relay_enabled`). |
| `extra_npm_packages` | `[]` | Installed into the persistent `/data/home/.npm-global` at each boot. |
| `extra_apt_packages` | `[]` | Installed at each boot. Not persistent — apt state is in the image layer. |

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

`/share/paseo/bin` is on `PATH`. Drop a wrapper script there (via Samba, the
file editor add-on, or `scp`) and point a provider at it with
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
- Do not expose port 6767 to the internet. Use Tailscale or the relay.

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
2. Update both `build_from` lines and the digest comment in `build.yaml`, and
   the `version` in `config.yaml` (`<upstream>-<addon revision>`, e.g. `0.3.2-1`).
3. Add a `CHANGELOG.md` entry, tag `v0.3.2-1`, and let CI publish.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Add-on exits immediately, log says `the 'password' option is empty` | Set a password in Configuration. |
| `403 Host not allowed` | Add the DNS name you are using to `hostnames`. |
| Web UI loads but will not connect | The static UI is served without auth; the API is not. Add a direct connection with the password. |
| A provider is missing from the app | Its CLI is not installed or not on `PATH`. Check `extra_npm_packages`, or `/share/paseo/bin` for wrappers. |
| An add-on update did not change my Claude Code version | An `update-agents` override in `/data` is shadowing the image copy. Run `update-agents status`, then `update-agents reset`. |
| A wrapper in `/share/paseo/bin` is not found in a terminal | Should not happen — `/etc/profile.d/ha-paseo-path.sh` restores `PATH` in login shells. Check the file survived, and that the script is executable. |
| MCP server shows as failed | The **MCP Server** integration is not enabled in Home Assistant. `hass-api` works regardless. |
| Agents cannot reach the internet or your tailnet | Add-on containers route through the HA host; check the host's own connectivity first. |

Daemon logs are in the add-on log and at `/data/home/.paseo/daemon.log`.
