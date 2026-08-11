# Home Assistant add-on: Paseo

Run [Paseo](https://paseo.sh) — a self-hosted orchestration layer for Claude
Code, Codex, OpenCode and Copilot — as a Home Assistant add-on, with the agents
wired into your Home Assistant configuration.

Think of it as the [claude-code-ha](https://github.com/ESJavadex/claude-code-ha)
idea with Paseo as the surface instead of a single terminal: multiple agents,
real workspaces and git worktrees, and a phone client that can reach it all from
anywhere on your tailnet.

## Install

### 1. Add the repository

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdanielcbaldwin%2Fha-paseo)

Or by hand:

1. **Settings → Add-ons → Add-on Store**
2. Top-right menu (⋮) → **Repositories**
3. Paste `https://github.com/danielcbaldwin/ha-paseo` → **Add** → **Close**
4. Refresh the store; **Paseo** appears under a new heading

### 2. Configure it

Install **Paseo**, then open the **Configuration** tab. Only one field is
mandatory:

| Field | Set it to |
| --- | --- |
| `password` | Anything you like. The add-on **refuses to start without one** — port 6767 is published on your LAN and the daemon holds a Supervisor token. |
| `hostnames` | Add any DNS name you'll use. Defaults cover `*.lan`, `*.ts.net` and `homeassistant.local`. IPs always work. |

Everything else has a working default. Save, then **Start**, and watch the
**Log** tab for `starting Paseo`.

### 3. Connect a client

There's no sidebar panel — [see why](#two-things-worth-knowing-up-front). Pick one:

- **Paseo app over Tailscale/LAN** (recommended) — Settings → Add host →
  Direct connection. Host = your HA box's IP, Port = `6767`, **SSL off**,
  password as configured. No pairing link needed.
- **Relay** — set `relay_enabled: true`, restart, and the join URL is printed
  in the add-on **Log**.
- **Browser** — the **Open Web UI** button on the add-on page.

### 4. Log in to the agents

Open a **terminal pane** in a Paseo workspace and run:

```bash
agent-login
```

It reports which providers are authenticated and prints the exact command for
the ones that aren't. Credentials persist across restarts and add-on updates, so
this is a one-time job.

`claude`, `opencode auth login` and `copilot login` all work headlessly.
**Codex** and **Gemini** need a little help —
[see the login guide](paseo/DOCS.md#logging-the-agents-in).

### 5. Try it

In the **Home Assistant** workspace (registered automatically), start an agent
and ask it something real:

```
What lights are on right now?
```

It should reach for `ha-inventory` rather than guessing entity ids.

---

Full documentation: [`paseo/DOCS.md`](paseo/DOCS.md).

### If installation fails

| Symptom | Cause |
| --- | --- |
| Repository adds but no add-on appears | Refresh the store, or reload the page. Check the repo URL has no trailing slash. |
| "Repository is not valid" / clone error | Supervisor clones anonymously — the repository must be publicly readable. |
| Install fails pulling the image | The GHCR package must be public too, and a release must have been published for your architecture. |
| Add-on installs but won't start | Check the **Log**. An empty `password` is the usual cause. |
| Not offered at all on your machine | `armv7`/32-bit ARM is unsupported — upstream Paseo publishes no 32-bit build. |

## What you get

- Paseo daemon on `:6767` — API, WebSocket and web UI on one origin
- `claude`, `codex`, `opencode`, `copilot` and `gemini` preinstalled, pinned,
  and updatable on demand with `update-agents`
- `ha`, `gh`, `git`, `jq`, `ripgrep`, `python3` for actually getting work done
- `/homeassistant` mapped read/write and registered as a workspace
- `hass-api`, an authenticated wrapper over the Core REST API
- `ha-inventory`, live discovery of your entities, services and areas
- `agent-login`, which tells you which providers are authenticated and exactly
  what to run for the ones that aren't
- All credentials and state persisted across add-on updates

### The agents actually know Home Assistant

Each provider is taught through the mechanism it actually reads — a
`home-assistant` **skill** for Claude Code, global `instructions` for
**OpenCode**, `AGENTS.md` for **Codex** — plus an MCP server for the two that
can be wired up safely. They get the file layout, the safety rules
(`ha core check` before restarting, never hand-edit `.storage/`), the YAML traps,
and `ha-inventory` so they look up real entity ids instead of inventing them.

Shared slash commands: `/ha-inventory`, `/ha-check`, `/ha-logs`,
`/ha-automation`.

## Requirements

- Home Assistant OS or Supervised (add-ons are not available on Container/Core)
- **amd64 or aarch64** — upstream Paseo publishes no 32-bit ARM build
- Enough headroom to run several coding agents at once

## Two things worth knowing up front

**There is no sidebar panel.** Paseo cannot be served under a URL subpath, and
Ingress serves add-ons under `/api/hassio_ingress/<token>/`, so its assets and
WebSocket would break. Connect the Paseo app directly to `<host>:6767` over
Tailscale, a VPN, or Paseo's relay. The **Open Web UI** button works too.

**This gives a language model broad control of your smart home** — read/write on
your configuration plus a Supervisor token with `manager` role. That is the
point, and it is genuinely dangerous. The
[security section](paseo/DOCS.md#security) is not boilerplate; please read it,
and try this on a non-critical instance first.

## License

MIT
