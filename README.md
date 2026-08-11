# Home Assistant add-on: Paseo

Run [Paseo](https://paseo.sh) — a self-hosted orchestration layer for Claude
Code, Codex, OpenCode and Copilot — as a Home Assistant add-on, with the agents
wired into your Home Assistant configuration.

Think of it as the [claude-code-ha](https://github.com/ESJavadex/claude-code-ha)
idea with Paseo as the surface instead of a single terminal: multiple agents,
real workspaces and git worktrees, and a phone client that can reach it all from
anywhere on your tailnet.

## Install

1. **Settings → Add-ons → Add-on Store**
2. Top-right menu (⋮) → **Repositories**
3. Add `https://github.com/danielcbaldwin/ha-paseo`
4. Install **Paseo**, set a password in **Configuration**, and start it

Full documentation: [`paseo/DOCS.md`](paseo/DOCS.md).

## What you get

- Paseo daemon on `:6767` — API, WebSocket and web UI on one origin
- `claude`, `codex`, `opencode`, `copilot` preinstalled
- `ha`, `gh`, `git`, `jq`, `ripgrep`, `python3` for actually getting work done
- `/homeassistant` mapped read/write and registered as a workspace
- `hass-api`, an authenticated wrapper over the Core REST API
- `ha-inventory`, live discovery of your entities, services and areas
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
