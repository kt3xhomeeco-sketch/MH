# Tasks

- [x] T01 Repurpose tick flags to visibility and remove calculation/edit gating.
- [x] T02 Native standalone window, observers, safe auto-update and menu hooks.
- [x] T03 Compact input UI with debounce, queued changes and error recovery.
- [x] T04 Portable/UI/native validation, VBO reload, documentation and packaging.

RuboCop 33 files clean; 113 Ruby tests / 658 assertions pass. Updated scenarios
verify hidden inputs still calculate and remain editable in authoring. Electron
checks main/Parametric regression plus options auto-apply/debounce/queue, failed
drafts, stale field events on root switch, visibility and text injection.

Native SU2025 PID31852 via VBO: outputs/native-options-013.json reports direct
18.6→20→21mm edits, visible-only flags, stale/invalid rejection, shared component
copy independence with fresh instance identity, geometry/parameter Undo + Redo,
and unchanged live Studio rule. outputs/native-options-ui-013.json uses a real
separate HtmlDialog: typing20 automatically changes geometry, actual thumbnail,
5 dense inputs (~210px body), no canvas/Apply, selection clear and 4 inputs after
hiding a field. Owned QA geometry/definitions removed. Native main reloaded with
form/camera/tree preservation. Standalone window stays open awaiting selection.

Runtime manifest: 13 Ruby / 12 UI files + README = 26 RBZ entries. Developer
tests/specs/tools and outputs excluded. API references checked against official
SketchUp ComponentDefinition, SelectionObserver, ModelObserver, AppObserver docs.
