# Changelog

## 0.3.1-4

- **The generated password is now written back into the `password` option**, so
  it is visible in the Configuration tab instead of only in a log line. Reading
  it previously required a shell, which you could only get through Paseo, which
  needed the password.
- **Regenerating is now possible**: clear the field and restart.
- The write-back reads the current options and sends the full set back.
  Supervisor replaces options rather than merging, so a partial write would have
  discarded every other setting — there is a test asserting unrelated options
  survive it.

## 0.3.1-3

- **The `password` field is no longer marked required in the UI.** Home
  Assistant treats any schema entry without a trailing `?` as mandatory and
  shows it with a `*`, which contradicted `0.3.1-2` generating a password when
  none is set. `provider_overrides` and `provider_env` are now optional too.
- Releases no longer advertise a version before its images exist. The git tag
  is the source of truth; CI publishes first and only then bumps `config.yaml`
  on `main`. Updating to `0.3.1-2` briefly failed with
  `[404] manifest unknown` for this reason.

## 0.3.1-2

- **The password is now optional.** Leave it blank and a 28-character one is
  generated on first start, printed to the add-on log, and saved to
  `/data/.paseo-generated-password` (mode 600) so it is reused across restarts.
  Previously the add-on refused to start without one. There is still no
  unauthenticated mode — 6767 is published on the LAN and the daemon holds a
  Supervisor `manager` token.
- **Fixed: boolean options set to `false` were silently ignored.** jq's `//`
  treats `false` as absent, so `.x // true` returned `true` even when `x` was
  explicitly `false`. This defeated `expose_ha_config: false` — opting out of
  agent access to the Home Assistant config did nothing — plus
  `print_pairing_link`, `relay_use_tls` and `relay_public_use_tls`.
- **`connection_mode`** replaces `relay_enabled`, with three choices:
  - `relay` *(new default)* — Paseo's hosted relay; the join link is printed to
    the add-on log on start
  - `local` — no relay, direct connections only
  - `custom_relay` — a relay you run yourself, via `relay_endpoint`,
    `relay_public_endpoint` and the matching TLS flags
- `app_base_url` for pointing pairing links at a self-hosted Paseo web app
- Switching away from `custom_relay` now *removes* the endpoint keys, so a stale
  self-hosted address cannot linger in the config
- An empty `relay_endpoint` under `custom_relay` falls back to `local` with a
  warning rather than quietly using the hosted relay
- Dropped `.ts.net` from the default `hostnames` and removed VPN-specific
  assumptions from the docs
- Full install walkthrough in the README

## 0.3.1-1

Initial release. Packages Paseo 0.3.1 as a Home Assistant add-on.

- Built on `ghcr.io/getpaseo/paseo`, pinned to an exact release tag
- Bundles `claude`, `codex`, `opencode`, `copilot` and `gemini` at pinned
  versions, plus `ha`, `gh`, `ripgrep`, `jq` and `python3`
- `update-agents` to move any agent CLI ahead of the image without waiting for
  an add-on release; overrides persist across add-on updates and
  `update-agents status` flags when one is shadowing the image version
- `auto_update_agents` option to do that on every boot (off by default)
- `agent-login` to show which providers are authenticated and exactly what to
  run for the ones that are not
- `provider_env` option for API keys, exported to the daemon and every agent —
  needed because Gemini CLI has no login subcommand and Codex's browser flow
  uses a localhost callback that cannot complete from a remote container
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
