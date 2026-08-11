# Home Assistant add-on: Paseo

Run [Paseo](https://paseo.sh) — a self-hosted orchestration layer for Claude
Code, Codex, OpenCode and Copilot — as a Home Assistant add-on, with the agents
wired into your Home Assistant configuration.

Think of it as the [claude-code-ha](https://github.com/ESJavadex/claude-code-ha)
idea with Paseo as the surface instead of a single terminal: multiple agents,
real workspaces and git worktrees, and desktop, web and phone clients.

## Install

### 1. Add the repository

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdanielcbaldwin%2Fha-paseo)

Or by hand:

1. **Settings → Add-ons → Add-on Store**
2. Top-right menu (⋮) → **Repositories**
3. Paste `https://github.com/danielcbaldwin/ha-paseo` → **Add** → **Close**
4. Refresh the store; **Paseo** appears under a new heading

### 2. Configure it

Install **Paseo** and press **Start**. Every option has a working default, so
there is nothing you must fill in first.

Watch the **Log** tab. If you left `password` blank, one is generated for you
and printed there in a banner — copy it, you'll need it to connect:

```
============== Generated Paseo password ==============
  Df1pd0sMOIIB06Zi47xsa8Bh4Ekn
======================================================
```

It's saved to `/data/.paseo-generated-password` and reused on every restart. Set
the `password` option yourself if you'd rather choose one. Add any DNS name you
plan to use to `hostnames` (IPs always work without it).

### 3. Connect a client

There's no sidebar panel — [see why](#two-things-worth-knowing-up-front). Pick one:

- **Paseo app, direct connection** (recommended) — Settings → Add host →
  Direct connection. Host = your HA box's IP, Port = `6767`, **SSL off**,
  password as configured. No pairing link needed. Works on your LAN, or from
  anywhere if you already have a VPN to it.
- **Relay** (the default) — the join URL is printed in the add-on **Log** on
  start. Works without any network changes. Set `connection_mode: local` to
  turn it off, or `custom_relay` to point at a relay you run yourself.
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
WebSocket would break. Connect the Paseo app directly to `<host>:6767` on your
LAN, over a VPN, or via Paseo's relay. The **Open Web UI** button works too.

**This gives a language model broad control of your smart home** — read/write on
your configuration plus a Supervisor token with `manager` role. That is the
point, and it is genuinely dangerous. The
[security section](paseo/DOCS.md#security) is not boilerplate; please read it,
and try this on a non-critical instance first.

## License

MIT
