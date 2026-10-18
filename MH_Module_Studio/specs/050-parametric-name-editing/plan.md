# Plan

- Panel preserves module-name metadata and snapshot identity on display renames.
  File-only drafts use Parametric.rename_display without requiring a live root.
- ModuleFile accepts the original source SKP and its signature when the new
  filename differs, preserving geometry rather than regenerating verified boxes.
- Parametric UI permits name edits with dirty variable drafts and updates their
  revision without discarding the drafts. Defer one save action across an active
  rename acknowledgement; keep all failure recovery in the existing response UI.
- Browser tests cover native event ordering. Portable controller tests cover
  file-only names and stale guards. Native tests use private copies/files and
  verify saved names plus later parameter edits. Preserve live UI drafts on reload.
