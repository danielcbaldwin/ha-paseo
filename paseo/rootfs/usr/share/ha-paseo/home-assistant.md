# Working on this Home Assistant instance

You are an agent running inside the **Paseo add-on** on a live Home Assistant
system. This is somebody's actual house: lights, locks, heating, alarms. A bad
edit here is not a failing test, it is a cold house at 3am.

The Home Assistant configuration is at **`/homeassistant`**. You have read/write
access to it and a Supervisor token with manager rights.

## Discover before you act

Never guess an entity id. This instance is discoverable — look:

```bash
ha-inventory                      # version, entity counts by domain, areas, add-ons
ha-inventory domains              # how many entities in each domain
ha-inventory entities light       # every light, with state and friendly name
ha-inventory entities light on    # ...only the ones that are on
ha-inventory search kitchen       # fuzzy match over entity id and friendly name
ha-inventory services light       # services in a domain, with their fields
ha-inventory areas                # areas and the entities assigned to them
ha-inventory state light.porch    # full state and attributes for one entity
```

## Talking to Home Assistant

`hass-api` is a pre-authenticated wrapper over the Core REST API. No token setup
needed — it uses the add-on's Supervisor token.

```bash
hass-api GET  states                                       # all entity states
hass-api GET  states/light.kitchen                         # one entity
hass-api POST services/light/turn_on '{"entity_id":"light.kitchen"}'
hass-api POST template '{"template":"{{ states(\"sun.sun\") }}"}'
hass-api GET  error_log
hass-api GET  config
```

`ha` is the Supervisor CLI, for everything above Core:

```bash
ha core check          # validate configuration -- ALWAYS before a restart
ha core restart
ha core logs
ha addons list       # newer Supervisors: `ha apps list`
ha backups new --name "before <change>"
```

If the **MCP Server** integration is enabled, a `homeassistant` MCP server is
also available. `hass-api` works whether or not it is.

## Rules

1. **Validate before restarting.** Run `ha core check` after editing any YAML.
   Never restart Core on a configuration that has not passed. This is
   **enforced**, not just asked for: `ha core restart` (and a restart or
   `reload_core_config` issued through `hass-api`) runs `ha core check` first and
   refuses if it fails. There is an escape hatch — `HA_PASEO_FORCE_RESTART=1` —
   but it exists only for a genuine emergency where the check itself is wrong;
   never use it to paper over a real error.
2. **Back up before destructive work.** `ha backups new --name "before <change>"`
   takes seconds and has saved entire weekends.
3. **Never hand-edit `.storage/`.** That directory is owned by the UI and is
   JSON state, not configuration. Editing it corrupts registries. Use the REST
   API or the frontend instead.
4. **Prefer a reload over a restart.** Reloading one domain
   (`hass-api POST services/automation/reload`) is far cheaper and safer than
   restarting Core, which drops every connection in the house.
5. **One change at a time**, validated, before starting the next.
6. **Do not touch `secrets.yaml`** except to read which keys exist. Never print
   its values, and never move a secret into a file that gets committed.
7. **Ask before anything irreversible** — deleting entities, removing add-ons,
   restoring a backup, or bulk-editing the registry.

## Where things live

```
/homeassistant/
  configuration.yaml     main config; !include pulls in the rest
  automations.yaml       UI-managed automations (keep the format the UI expects)
  scripts.yaml           UI-managed scripts
  scenes.yaml            UI-managed scenes
  secrets.yaml           credentials -- read key names only, never values
  custom_components/     HACS and manual integrations
  .storage/              UI-owned state -- DO NOT EDIT
  home-assistant.log     current log
```

## Conventions

- YAML is 2-space indented. Never tabs.
- Quote anything ambiguous: `"on"`, `"off"`, `"yes"`, `"no"` are booleans in
  YAML unless quoted, which is a classic source of silent breakage.
- Entity ids are `domain.object_id`, lowercase with underscores.
- Prefer `!secret` references over inline credentials.
- When editing UI-managed files (`automations.yaml`, `scripts.yaml`), preserve
  the existing `id:` keys — the UI matches on them, and dropping one orphans
  the automation.

## Debugging

```bash
ha core check                            # config validation
hass-api GET error_log                   # what actually went wrong
tail -n 200 /homeassistant/home-assistant.log
ha-inventory state <entity_id>           # is the entity even there?
hass-api POST template '{"template":"{{ ... }}"}'   # test a template safely
```

A template that misbehaves in an automation will misbehave the same way through
the template API, and testing it there costs nothing.
