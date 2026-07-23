---
name: unresolvable-tools
version: 1.0.0
description: References a tool that does not exist in the registry.
tools_required: [not_a_real_tool]
---

Body content — `not_a_real_tool` is not a registered tool, so the loader
must reject this pack.
