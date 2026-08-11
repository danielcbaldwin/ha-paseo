---
description: Show what exists on this Home Assistant instance
---

Run `ha-inventory $ARGUMENTS` and summarise the result for me.

If no arguments were given, run plain `ha-inventory` for the overview, then
point out anything notable — domains with a surprising number of entities,
entities that are `unavailable` or `unknown`, or add-ons that are stopped.

Useful subcommands: `domains`, `entities <domain> [state]`, `search <text>`,
`services [domain]`, `areas`, `state <entity_id>`.
