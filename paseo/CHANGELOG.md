# Changelog

## 0.7.2-4

- **YAML tooling for the agents.** Editing Home Assistant config is most of what
  runs in here, so the image now ships **PyYAML** (`python3-yaml`) and
  **ruamel.yaml** (`python3-ruamel.yaml`, comment- and format-preserving on a
  round-trip edit), **`yamllint`** to validate a file before `ha core check`, and
  **`moreutils`** for `sponge` (in-place pipe edits without the temp-file
  shuffle). All from apt — the system Python is externally managed — so no
  `extra_apt_packages` is needed for the common case.
- **Network utilities for diagnosing connectivity.** Alongside the `curl` that
  upstream already ships, the image now has `dig`/`nslookup`
  (`bind9-dnsutils`), `ping` (`iputils-ping`), `nc` (`netcat-openbsd`),
  `traceroute`, and `ss`/`ip` (`iproute2`) — enough to work out why an agent
  can't reach HA Core, an MCP server or a webhook target.

## 0.7.2-3

- **Agent CLIs and tooling refreshed to the latest upstream pins** (issue #3):
  `@anthropic-ai/claude-code` 2.1.227 → 2.1.251, `@openai/codex` 0.147.0 →
  0.151.0, `opencode-ai` 1.18.16 → 1.18.25, `@github/copilot` 1.0.79 → 1.0.82,
  `@google/gemini-cli` 0.54.4 → 0.57.0, `home-assistant/cli` 5.3.0 → 5.4.0, and
  `gh` 2.97.0 → 2.98.0. Pin-only; the add-on itself is unchanged since 0.7.2-2.

## 0.7.2-2

- **Agents can now actually edit `configuration.yaml`.** The mount was always
  read/write, but the daemon and every agent run as uid 1000 while HA Core
  creates the config files as root, so an in-place edit failed with `EACCES` —
  seeding new files (`.mcp.json`, `CLAUDE.md`) worked because those are born
  owned by 1000, which is exactly why editing existing files did not. The
  entrypoint deliberately never chowns `/homeassistant` (it is your real config
  directory), so instead it now grants uid 1000 an **ACL** (`u:1000:rwX`, plus a
  default ACL for inheritance) over the editable YAML surface, leaving root
  ownership — and therefore HA Core and backup/restore — untouched. `.storage/`
  is excluded (UI-owned state; editing it corrupts the registries), as are heavy
  non-config trees (`custom_components/`, `www/`, `deps/`, `tts/`, `.git/`,
  backups and logs). The grant runs on **every** boot on purpose: a tar
  backup/restore strips ACLs and re-roots ownership, so a one-shot marker would
  silently stop working after a restore. Requires ACL support on the config
  filesystem (HAOS ext4 has it); if `setfacl` cannot apply, the add-on logs a
  clear warning and agents stay read-only on existing files rather than failing
  the boot. Adds the `acl` package.
- **Restarts are gated on `ha core check`.** Now that agents can genuinely edit
  the config, a bad edit followed by `ha core restart` would boot Core into a
  broken state. A guard wrapper at `/usr/local/sbin/ha` (which shadows the real
  binary via PATH order, without touching it) runs `ha core check` before any
  `core restart`/`core start` and refuses if it fails; `hass-api` applies the
  same gate to `services/homeassistant/restart`, `reload_core_config` and
  `reload_all`. Home Assistant validates the config on disk, so this is the real
  "validate before it takes effect" point — there is no hook on an agent's file
  save, but nothing is applied until a restart/reload, and that is gated.
  Enforced, not merely requested in `CLAUDE.md`. Escape hatch for a genuine
  emergency (a flaky check): `HA_PASEO_FORCE_RESTART=1`.

## 0.7.2-1

- **Paseo 0.7.2.** The base image moved from `0.7.1` to `0.7.2`
  (`sha256:da9286410d9dd86208755b789894534d9e200c9021bd45157557aac4146b84fb`). Released automatically; the add-on itself is
  unchanged since 0.7.1-1.

## 0.7.1-1

- **Paseo 0.7.1.** The base image moved from `0.7.0` to `0.7.1`
  (`sha256:622ae1ec9d13b45073bcc0a72b286fc50ca8c6a5c5f3a31b468e67d3fcb11dac`). Released automatically; the add-on itself is
  unchanged since 0.7.0-2.

## 0.7.0-2

- **`provider_overrides` is now authoritative — removing an entry removes it.**
  Seeding only ever merged overrides into Paseo's `config.json` and never took
  them away, so clearing a provider from the add-on config left its old
  definition in place. When that definition pointed `command` at a proxy wrapper
  (a TeamClaude shim, say), Paseo kept spawning the wrapper after you thought you
  had removed it; the wrapper's startup banner corrupts the stdio protocol Paseo
  speaks to the agent, and the session hangs — while `claude` in a terminal pane
  looks perfectly fine, because a human just reads the banner. `ha-paseo-seed-config`
  now records the provider keys it seeds in a sidecar
  (`${PASEO_HOME}/.ha-paseo-managed-providers.json`) and, on the next restart,
  deletes any managed key that has disappeared from `provider_overrides`. Keys
  present now are still recursive-merged, so adding just an `env` or `label`
  without restating a provider keeps working, and a provider you add only from
  the Paseo app is never in the managed set and is never touched.
- **Migration note.** The managed set starts empty on the first restart after
  this ships, so an override you had *already* removed beforehand is not cleaned
  up for you — the add-on has no record that it owned it. Delete it once by hand
  (`jq 'del(.agents.providers.<key>)' /data/home/.paseo/config.json`) and restart;
  from then on the option is the source of truth. See DOCS.md, "Custom providers".

## 0.7.0-1

- **Paseo 0.7.0.** The base image moved from `0.6.1` to `0.7.0`
  (`sha256:819a87d6c8528db00770c6cbb6c00bdc869bea7f3362a5d955f6d37e05400a4d`). Released automatically; the add-on itself is
  unchanged since 0.6.1-1.

## 0.6.1-1

- **Paseo 0.6.1.** The base image moved from `0.6.0` to `0.6.1`
  (`sha256:53f0eda111f041d2ffed5b8fcfb63c75243cd99ab93f93a11182f49b1c16c82a`). Released automatically; the add-on itself is
  unchanged since 0.6.0-1.

## 0.6.0-1

- **Paseo 0.6.0.** The base image moved from `0.5.2` to `0.6.0`
  (`sha256:e53b2147d8f9bfdb7266c0cadc701e90727eea310143dec1d9e568af6d65f54a`). Released automatically; the add-on itself is
  unchanged since 0.5.2-1.

## 0.5.2-1

- **Paseo 0.5.2.** The base image moved from `0.5.1` to `0.5.2`
  (`sha256:85ba0c359f6922755cdba872441e2009d69e6c7bf3d56cc7664d7eaf5eb64138`). Released automatically; the add-on itself is
  unchanged since 0.5.1-1.

## 0.5.1-1

- **Paseo 0.5.1.** The base image moved from `0.4.0` to `0.5.1`
  (`sha256:d43300569274b6d268d42b9feb38af255270ebfe7b20ea633caccc469989ab6c`). Released automatically; the add-on itself is
  unchanged since 0.4.0-2.

## 0.4.0-2

- **`scripts/verify.sh` passes regardless of who runs it.** It failed 24 of 102
  checks in CI while passing on a dev box, which blocked the release gate added in
  `0.4.0-1` from ever going green. Three separate assumptions, none of them about
  the product:
  - The bind-mounted directories were left owned by whoever ran the script. The
    add-on drops to uid 1000, so on a CI runner (uid 1001) container-side writes
    failed — `/homeassistant` above all, which the entrypoint deliberately never
    chowns because it is the user's real config directory.
  - Config assertions ran `sh -c "jq ... <<<'$json'"`. `<<<` is a bash
    here-string; `/bin/sh` is dash on Ubuntu and ash on Alpine, so those checks
    were a syntax error anywhere `/bin/sh` is not bash. Same trap as the
    container's `SHELL` defaulting to dash. They also corrupted any document
    containing a single quote.
  - The connection-mode helper read `config.json` from the host, but the daemon
    writes it mode `0600` as uid 1000 inside a `0700` directory — unreadable to a
    uid-1001 harness, which silently fell back to `{}` and reported a config
    regression that did not exist.
- Step 3 now says so loudly when `config.json` is not valid JSON, instead of
  reporting six unexplained failures.

## 0.4.0-1

- **Paseo 0.4.0.** The base image moved from `0.3.1` to `0.4.0`
  (`sha256:593cb65b1eabee061af8f240fcb4031818e9c330fe66b584c345e3b296531b95`).
- **New Paseo releases now ship by themselves.** A scheduled workflow checks
  upstream every six hours and, on a new stable tag, repins the base image and
  releases `<upstream>-1` — so the add-on version keeps stating which Paseo is
  inside, without waiting on anyone. Prereleases are ignored. Previously a weekly
  job filed an issue and the release still waited on a human, which is why 0.4.0
  sat unshipped.
- **`scripts/release.sh` now refuses a version that disagrees with the pin.**
  Releasing `0.4.0-2` from a tree still pinned to `0.3.1` used to be possible, and
  produced a version number that lied about its contents.
- **`ha-paseo-doctor` reports the Paseo version recorded in the image** as
  `paseo`, next to the add-on `version`. The two should always agree; this makes
  it visible when they do not. Taken from the installed package at build time and
  stored in `/etc/ha-paseo-release`.
- **Releases are verified before they are advertised.** `scripts/verify.sh` now
  runs in CI against the published amd64 image, gating the commit that tells
  Home Assistant a new version exists. A base image that broke the add-on is
  never offered to an instance — which matters now that upstream bumps ship
  without anyone reviewing them.

## 0.3.1-15

- **`ha-inventory` no longer leaks a CLI warning into its output.** Newer
  Supervisors renamed add-ons to "apps": the CLI prints a deprecation notice for
  the old spelling, and older Supervisors 404 on the new one. It now tries
  `ha apps`, falls back to `ha addons`, reads whichever key the response uses,
  and keeps stderr out of stdout. That output is read by agents, where a stray
  warning line is noise they may act on.
- The Home Assistant guide notes both spellings.

## 0.3.1-14

- **Terminal panes were running dash, not bash.** `SHELL` was unset in the
  image, and node-pty falls back to `/bin/sh` — which on Debian is dash: no tab
  completion at all, a bare `$` prompt, and it never reads `.bashrc`. So none of
  the shell setup added in `0.3.1-12` was reaching the pane. `SHELL=/bin/bash`
  is now set in the image.

  Symptom was that even `ech<Tab>` did nothing — completing a builtin needs
  only readline, so that ruled out every explanation except the shell itself.

## 0.3.1-13

- **Builds no longer use `home-assistant/builder`.** That action prints
  "deprecated and no longer maintained" on every run, and unconditionally
  installs cosign from sigstore — a 503 there failed a release before any build
  work started. There is no opt-out, so pinning the action would not have
  helped. Images are now built with `docker buildx` directly.
- The `io.hass.*` labels Supervisor requires are set explicitly from
  `config.yaml`, so they cannot drift from the manifest, and CI now asserts the
  critical ones are present on the pushed image rather than discovering a
  regression as a failed install.
- Label set verified identical to what the old builder produced.

## 0.3.1-12

- **The terminal is no longer a bare shell.** The container shipped no dotfiles
  at all and `bash-completion` was not installed, so panes had no completion,
  no history search and no prompt. First start now seeds `.bashrc`,
  `.bash_profile` and `.inputrc` into `/data/home` — only when absent, so edits
  survive restarts and updates.
  - Up/Down search history for what you have already typed
  - tab completion for `git`, `apt`, `ssh`, `gh` and the rest
  - large shared history, appended per command so panes do not clobber
    each other
  - prompt showing directory, git branch, and exit status when non-zero
- Added `bash-completion`, `fzf` (Ctrl-R over history), `tree` and `htop`.

## 0.3.1-11

- **Fixed: a fresh install could end up with no Home Assistant workspace.**
  `0.3.1-5` stopped registering one whenever the workspace list could not be
  read, to end the duplicate-per-restart bug. That traded one failure for its
  opposite. Now:
  - the list is retried a few times before giving up, since the CLI can fail
    briefly just after the daemon starts answering health checks
  - a successful registration is recorded in
    `/data/.ha-paseo-workspace-registered`, so an unreadable list still creates
    the *first* workspace but can never add a second
  - retries are logged, so a slow start is visible rather than silent

## 0.3.1-10

- **`ha-paseo-doctor`** — one command that dumps live state: bind address and
  mode, daemon health, every shim and the binary it resolves to, whether each
  configured service is actually running, listening ports, per-container proxy
  credentials, and where each agent CLI resolves from.

  The add-on log is a poor diagnostic surface — at `log_level: debug` the daemon
  floods it and the startup lines are gone in seconds. This reads current state
  instead.

## 0.3.1-9

Three real bugs in the shim support added in 0.3.1-7/-8, all of which could
present as a hang:

- **`require_port` did not exist.** It was documented and parsed but never
  written into the generated shim; the edit that was meant to add it silently
  failed to apply and the test that "confirmed" it checked the wrong binary.
  Now implemented, with tests for both the open and closed cases.
- **The PATH guard was prefix-only.** If the shim directory was not *first* on
  PATH it was not removed, so the shim resolved itself and exec'd itself —
  a fork bomb, indistinguishable from a hang. Now removes every occurrence.
- **`target`** (an absolute path) can now be given instead of a bare name. That
  removes PATH resolution from the shim entirely, so recursion is structurally
  impossible, and a wrong path is reported in the log at startup rather than
  failing at runtime.

## 0.3.1-8

- **Fixed the recommended TeamClaude shim, which hung.** `command: teamclaude
  run --` inserts another process that writes to stdout, and Paseo speaks a
  stdio protocol to its agents — one stray line (`Created config at …` on first
  use) derails the session.
- Shims gain **`env_from`**: run a helper, `eval` its stdout, then exec the
  *real* binary. Stdout stays byte-identical, which is what a proxy wrapper
  needs. This is the shape TeamClaude's own help recommends for "agent
  multiplexers that spawn claude themselves".
- Shims also gain **`script`** for a full shell body when neither fits.

## 0.3.1-7

- **`shims`** — intercept a command name (typically `claude`) with a wrapper,
  for every caller: agents spawned by the daemon and terminal panes alike. This
  is what `teamclaude alias --install` cannot do, since shell aliases are not
  inherited across `execve`. Generated into `/run/ha-paseo/shims`, first on
  `PATH`, rebuilt each start; nothing is written to `/share` or `/data`.
  - the shim directory is stripped from `PATH` before the wrapper runs, so a
    wrapper invoking the same command finds the real binary instead of
    recursing
  - `$REAL` gives the absolute path of the shadowed command
  - `passthrough` lets probe-style arguments (`--version`, `auth`) skip the
    wrapper, which matters because Paseo fires those concurrently on every
    provider-features request
- `/share/paseo/bin` now takes precedence over `update-agents` overrides, so a
  user wrapper is never silently shadowed.

## 0.3.1-6

- **Background services.** Tools that are servers rather than one-shot binaries
  — a TeamClaude proxy, say — can now run alongside the agents:
  - the `services` option, a list of commands, each supervised and restarted on
    exit with backoff from 2s to a 60s ceiling
  - `/share/paseo/services/` — any executable there runs as a service with no
    config edit
  - output prefixed `[svc:<name>]` into the add-on log, with duplicate names
    disambiguated
- **`init_commands`** for one-shot setup at each start. Failures are logged and
  startup continues.

## 0.3.1-5

- **Fixed: a duplicate "Home Assistant" workspace was created on every restart.**
  The "already registered?" check matched a `path` key that does not exist on
  Paseo workspace entries — they use `cwd` — so it never matched. It now matches
  `cwd`, and skips registration entirely if the workspace list cannot be read,
  rather than creating another one. Archive any duplicates with
  `paseo workspace archive <id>`.
- **The password is optional again, and nothing is auto-generated.** It only
  affects direct connections; the relay authenticates devices through its
  pairing handshake instead. The bind address now follows from it:
  - password set → `0.0.0.0` (protected; Open Web UI and LAN access work)
  - blank + `relay`/`custom_relay` → `127.0.0.1` (relay only, nothing exposed)
  - blank + `local` → `0.0.0.0`, unauthenticated, with a loud log warning
- Removed the generated-password write-back added in `0.3.1-4`, along with
  `/data/.paseo-generated-password`.

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
