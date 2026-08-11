# Changelog

## 0.3.1-1

Initial release. Packages Paseo 0.3.1 as a Home Assistant add-on.

- Built on `ghcr.io/getpaseo/paseo`, pinned to an exact release tag
- Bundles `claude`, `codex`, `opencode`, `copilot` and `gemini` at pinned
  versions, plus `ha`, `gh`, `ripgrep`, `jq` and `python3`
- `update-agents` to move any agent CLI ahead of the image without waiting for
  an add-on release; overrides persist across add-on updates and
  `update-agents status` flags when one is shadowing the image version
- `auto_update_agents` option to do that on every boot (off by default)
- Weekly `check-updates` workflow that files an issue when any pin falls behind
- Relay join URL printed to the add-on log at startup (`print_pairing_link`),
  since getting a shell into an add-on is awkward
- `/etc/profile.d` fix so login shells (Paseo terminal panes) keep
  `/share/paseo/bin` and the npm override dir on `PATH` — Debian's
  `/etc/profile` hardcodes `PATH` and would otherwise drop both
- All state relocated to `/data/home` so credentials and history survive add-on
  updates, rather than landing on the anonymous `/home/paseo` volume
- `/homeassistant` mapped read/write and registered as a Paseo workspace
- **Every provider is taught about Home Assistant**, each through its own
  discovery mechanism: a `home-assistant` skill and slash commands for Claude
  Code, global `instructions` plus commands and an MCP entry for OpenCode, and
  `AGENTS.md` for Codex. Managed files are refreshed on each start; files in
  `/homeassistant` are only created if missing
- `hass-api` helper for authenticated Core REST API calls from any provider
- `ha-inventory` for live discovery of entities, domains, services and areas, so
  agents stop guessing entity ids
- `/ha-inventory`, `/ha-check`, `/ha-logs` and `/ha-automation` slash commands
- `provider_overrides` option and `/share/paseo/bin` on `PATH` for custom
  provider wrappers such as TeamClaude
- Refuses to start without a password
