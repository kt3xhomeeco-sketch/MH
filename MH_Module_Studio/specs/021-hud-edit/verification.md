# Verification — 2026-10-15

Spec Kit prerequisites resolve this feature's spec/plan/tasks. Scoped gate:
50 Ruby files clean in RuboCop; 150 tests / 1,997 assertions, no failures,
errors or skips. Portable coverage includes small-icon layouts, edge-clamped
cursor anchors, centered placement, ordering, cross-folder insertion, stale/
missing entries, normalized preferences, separate Edit destination vs Library
browsing, and cancelled/stale drag events.

Native helper compiled with GCC 15.2 x64, -Wall -Wextra -Werror, static libgcc
and no PE timestamp. Binary imports Windows/UCRT APIs only; no Ruby ABI callbacks
or third-party runtime DLLs. WH_GETMESSAGE is restricted to the current UI thread
and model-window descendants. It never installs a global keyboard hook.

Native SketchUp 2025 PID26424, pinned VBO:
- Physical B (Paint Bucket assigned) produced HUD query b.
- Physical R (Curic Pie Menu assigned) produced query br; HUD remained active.
- Physical Esc closed HUD and removed capture. Physical B afterward activated
  PaintTool, proving ordinary shortcut routing resumed.
- Space was checked through posted native key messages to the pinned window;
  it closed HUD and removed capture. A physical Space attempt was safely refused
  when the foreground changed to a different application, before sending input.
- Native reorder handlers, persisted preferences, Library bridge drop, stale token,
  outside drop cancellation, normal module selection after Edit, both position
  modes and actual 24px View.draw2d rendering passed.
- outputs/native-hud-021.json: ok=true, user_model_retained=true,
  shortcuts_unchanged=true. No changes to SKPs or user geometry/selection.

Physical cross-window pointer capture check:
outputs/physical-hud-drag-021.json has started=true, ended=true, ok=true,
cleanup=true. A temporary HtmlDialog card used pointer capture and the production
HUD bridge; real mouse-down/moves/up transferred a module into native radial
slot 2, with the HUD/filter still active and no model placement. Preferences,
selection and original roots restored; temporary dialog closed. This exercises
the real CEF-to-native boundary. Actual Library card gesture dispatch is covered
separately in Chromium. An earlier HTML5/OLE drag switched SketchUp's Tool and
was replaced with pointer capture; it is not the shipped input path. Foreground
and window-under-pointer guards prevented actions in other apps during retries.
Current physical checks ran at UI scale 1.0; other monitor DPI modes were not
physically exercised.

Chromium test/library_ui_smoke.cjs passed: existing Library folder/list/search/
size/thumbnail/escaping behavior plus Edit card gestures, session payloads,
HUD exit, slider minimum 24, position selector, Edit toggle and compact settings
layout. No browser console errors. External drags carry identifiers through the
bridge, without an OS file/URL drag.

VBO reloaded Ruby in PID26424 and PID12360. The visible main Studio UI in PID26424
was reloaded with form/camera/tree state retained; child Parametric left intact.
outputs/native-hud-ui-021.json has ok=true, committed_rule_unchanged=true,
state_retained=true and edit_button_present=true. No temporary request override,
QA dialog or native capture remains active after checks.

RBZ explicit manifest: 37 entries including 18 Ruby files (loader included),
native/hud_input.dll and UI assets. Tests, C source/compiler tooling, specs and
reports excluded. Packaging validates CRC and entry count.

Follow-up: circular thumbnails and one-placement HUD cycle
---------------------------------------------------------
Thumbnail textures now use a 48-triangle circular disk, center-cropped UVs with
preserved aspect ratio and a 1px inset. Native report
outputs/native-hud-image-fit-022.json checked eight actual textures at each of
24/86/140px: disk radius, UV bounds, draw success and model/selection cleanup.

Selecting a module now hides the complete HUD, including its hit targets.
Only the placement preview is drawn; browse keys are ignored until placement
finishes. After one successful Library.place call, pending/input/hover are cleared
and the same HUD returns with its folder/query retained. Esc/Space still exit.
Import errors also clear pending and return the HUD.

Scoped gate: 50 Ruby files clean, 152 tests / 2,017 assertions, no failures/errors/
skips. New portable regression cases cover hidden click targets, drawing before a
valid input point, and ignored invisible browse controls.
outputs/native-hud-placement-023.json: two native handler-driven cycles using
actual Library.prepare/place and actual ComponentInstances; drawing via a View
proxy confirmed no overlay while pending, a wire preview, and overlay return.
Clicks at the former icon coordinate placed exactly one component per cycle.
InputPoint was supplied by a deterministic test double; this was not a physical
mouse placement test. show_options was temporarily replaced to avoid changing
the user's options dialog and restored afterward. A deliberately stale fingerprint
exercised failed-import recovery (the bridge's traced errors were expected).
Escape released capture. Temporary components/definitions were removed, original
roots/definitions/selection/preferences restored; report ok=true and cleanup=true.
