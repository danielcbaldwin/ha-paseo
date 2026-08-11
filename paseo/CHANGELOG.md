# Changelog

## 0.3.1-1

Initial release. Packages Paseo 0.3.1 as a Home Assistant add-on.

- Built on `ghcr.io/getpaseo/paseo`, pinned by digest
- Bundles `claude`, `codex`, `opencode` and `copilot`, plus `ha`, `gh`,
  `ripgrep`, `jq` and `python3`
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
