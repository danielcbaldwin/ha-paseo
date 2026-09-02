---
name: home-assistant
description: >-
  Work with the Home Assistant instance this agent is running on -- discover
  entities, areas and services, call services, read logs, and safely edit the
  configuration at /homeassistant. Use whenever the task mentions Home
  Assistant, an automation, a scene, a script, a smart-home device (light,
  switch, sensor, climate, lock, cover, media player), an entity id, or
  anything under /homeassistant.
---

# Home Assistant

You are running inside the Paseo add-on on a live Home Assistant system, with
read/write access to `/homeassistant` and a Supervisor token.

## Always discover first

Do not guess entity ids — this instance is queryable:

```bash
ha-inventory                    # version, entity counts by domain, areas, add-ons
ha-inventory entities light     # every light with state and friendly name
ha-inventory search kitchen     # fuzzy match on entity id and friendly name
ha-inventory services light     # available services and their fields
ha-inventory state light.porch  # full state and attributes
```

## Act

```bash
hass-api GET  states/light.kitchen
hass-api POST services/light/turn_on '{"entity_id":"light.kitchen"}'
hass-api POST template '{"template":"{{ states(\"sun.sun\") }}"}'
ha core check       # validate config -- ALWAYS before restarting
ha core restart     # the add-on runs `ha core check` first and refuses if it fails
```

## Non-negotiable rules

1. `ha core check` must pass before any restart. The add-on **enforces** this:
   `ha core restart` (and a restart/`reload_core_config` via `hass-api`) runs
   `ha core check` first and refuses on failure. Do not reach for
   `HA_PASEO_FORCE_RESTART=1` to get around a real error — fix the config.
2. `ha backups new --name "before <change>"` before destructive work.
3. Never hand-edit `/homeassistant/.storage/` — it is UI-owned state.
4. Reload a single domain rather than restarting Core where possible.
5. Never print values from `secrets.yaml`.
6. Ask before anything irreversible.

## Full reference

Read `/usr/share/ha-paseo/home-assistant.md` for file layout, YAML conventions
(including the `"on"`/`"off"` quoting trap), UI-managed file handling, and the
debugging workflow.
