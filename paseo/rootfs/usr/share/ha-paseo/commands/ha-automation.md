---
description: Write a Home Assistant automation, grounded in real entities
---

Build an automation for: $ARGUMENTS

Work in this order:

1. **Find the real entities.** Use `ha-inventory search <text>` and
   `ha-inventory entities <domain>`. Never invent an entity id. If several
   entities plausibly match what I asked for, show me the candidates and ask
   which one I meant.
2. **Check the services** you intend to call with
   `ha-inventory services <domain>` so the fields are right.
3. **Test any template** with
   `hass-api POST template '{"template":"..."}'` before putting it in the
   automation.
4. **Show me the YAML** and wait for approval.
5. On approval, append it to `/homeassistant/automations.yaml` with a unique
   numeric `id:` — the UI matches on that key, and reusing or omitting one
   breaks the editor.
6. `ha core check`, then reload with
   `hass-api POST services/automation/reload`. Do not restart Core.
7. Tell me how to trigger it manually to confirm it works.

Prefer explicit `trigger`/`condition`/`action` blocks over clever templating —
this file gets edited by a UI and by humans, and legibility wins.
