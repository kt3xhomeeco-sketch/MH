# Plan

Change only the separate Parametric HTML/CSS and its presentation JS. Shared
scroll container with full-width gray bands; tables retain IDs, column order,
editing handlers and JSON protocol. Existing ATT detail keeps all scoped data.
Use native title chrome; do not simulate a second Windows title bar in the page.
Inline fields remain real accessible controls, with borders on focus only.

Collapse state is window presentation state; reopening for a linked input expands
its group, focuses and scrolls it into view. Native reload first captures draft and
collapse state through the existing child bridge, then closes/reopens the child
after its real asynchronous close callback, restores state and verifies the UI.
No solver/schema change and no source/model mutation. Constitution gates hold.
