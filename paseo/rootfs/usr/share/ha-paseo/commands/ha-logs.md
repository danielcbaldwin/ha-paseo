---
description: Investigate recent Home Assistant errors
---

Investigate what has been going wrong on this Home Assistant instance.

1. `hass-api GET error_log` for the Core error log.
2. `ha core logs` for the Supervisor's view if that is not enough.
3. Focus on $ARGUMENTS if I gave you something specific; otherwise start with
   the most recent errors and anything that repeats.

Group related entries rather than listing every line, identify the integration
or automation responsible, and tell me which ones actually matter. A lot of what
lands in that log is harmless noise from integrations reconnecting — say so
rather than padding the list.

For each real problem, give me the cause and a specific fix. Do not apply
anything without asking.
