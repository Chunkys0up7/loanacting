---
name: demo-document-request
version: 1.0.0
description: When the loan is awaiting documents and has an open document goal, request the document from the operator.
tools_required: [request_document]
---

# Demo: document request

Foundation's one bundled skill pack, proving the load → trigger → tool
path (spec.md SC-014). Not a real compliance rule — see `references/rationale.md`.

When this skill's trigger matches the loan's current status and open
goals, the planning loop invokes the `request_document` tool named in
`tools_required` above.
