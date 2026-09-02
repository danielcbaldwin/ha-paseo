---
description: Validate the Home Assistant configuration and explain any errors
---

Run `ha core check`.

Note: the add-on already gates restarts on this — `ha core restart` runs
`ha core check` first and refuses if it fails — so running it yourself here is
about *understanding* a failure before you get blocked by it, not a formality.

If it passes, say so plainly and stop — do not restart Core unless I asked you
to.

If it fails:

1. Quote the actual error.
2. Open the offending file at the reported line and show me the real cause,
   not just the message. Watch for the usual suspects: unquoted `on`/`off`/`yes`
   /`no`, tab characters, wrong indentation, a missing `!secret` key, or a
   reference to an entity that no longer exists (check with
   `ha-inventory state <entity_id>`).
3. Propose the fix and wait for me to approve it before editing.

Also check `hass-api GET error_log` if the failure is not obvious from the
config check alone.
