# MH Isolate

Fast object-only isolate/unisolate for SketchUp 2025.

## Behavior

- The default mode only processes sibling Groups and ComponentInstances in the current editing context.
- It never traverses nested Edge/Face geometry.
- Locked objects and objects already hidden by their instance state or original Tag are preserved and skipped.
- Because locked sibling objects are skipped, they can remain visible during isolation.
- Original Tags are restored using persistent IDs. Recovery data is stored in the model attribute dictionary `MH_isolate`.
- Loose Edge/Face isolation is opt-in from `Extensions > MH Isolate > Include Loose Edge/Face (Slower)`.
- `Zoom to Isolated Objects` is enabled by default and can be toggled from the same menu.
- Unisolate restores visibility and selection but intentionally keeps the current camera.

## Commands

- `MH Toggle Isolate/Unisolate`
- `MH Isolate Selected`
- `MH Unisolate`
- `Force Restore / Cleanup`

Commands can be assigned keyboard shortcuts from SketchUp Preferences.
