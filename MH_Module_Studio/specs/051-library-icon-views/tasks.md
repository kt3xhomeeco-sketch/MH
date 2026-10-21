# Completion and evidence

- [x] Implement per-file thumbnail camera/cache owner and runtime manifest entry.
- [x] Add Library selector/update and shared HUD Settings controls with ring paging.
- [x] Preserve source fingerprints and old settings on failure; replace stale
  Library images and GPU textures. Retain unsubmitted selections during refresh.
- [x] Portable tests: persistence, isolated choices, regeneration, failed rendering
  and unchanged source bytes. test/library_thumbnails_test.rb.
- [x] Native SketchUp: eight actual 256px PNGs, distinct cameras, sidecar reload,
  GPU refresh/Settings metadata and source objects/selection/camera retained.
  outputs/native-051.json. Visually inspected 3D, front and top images.
- [x] Chromium: both view controls, async stale response, draft retention,
  independent modules, retry, paging, native PNGs and compact layout passed.
  test/library_views_browser.cjs; outputs/library-views-051.png and hud-views-051.png.
- [x] Final scoped gate: 149 Ruby files lint clean; 296 tests / 3254 assertions
  passed. RBZ built and explicit archive/manifest contents verified.
- [x] Reloaded through VBO in the new Untitled session (PID17292). Actual Library
  has 116 entries, eight view choices and enabled Update, pending=false. HUD
  Settings shows four current-ring rows, eight choices each, no error/overflow.
  outputs/live-library-051.json and outputs/live-hud-051.json. Source SKPs were
  not assigned new views during this live UI presence check.

## Follow-up: edit views directly in Library only

- [x] Removed per-icon view rows, ring-page controls, handlers, CSS and image
  metadata from HUD Settings. Library retains the selector and Update action;
  ring textures continue to use Library's persisted image.
- [x] Chromium confirms independent Library editing, async/error recovery and
  absence of the icon editor in Settings. Size, position, Edit and folder shortcut
  controls still dispatch correctly. Scoped gate remains 149 clean files,
  296 tests / 3254 assertions passed.
- [x] Reloaded the actual dialogs through VBO. Library: eight choices, Update
  enabled, pending=false. Settings: no icon editor, all existing controls and
  six folder shortcut rows present, no error. Retained folder input drafts.
  outputs/live-library-only-051.json and live-settings-library-only-051.json.
