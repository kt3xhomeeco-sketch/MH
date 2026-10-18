# Tasks

- [x] Add validated image percent preference, independent from circle pixels.
- [x] Add immediate slider and centered shrink/zoom with circle clipping.
- [x] Portable preference defaults/clamping and adapter persistence without
  changing circle pixels. Scoped gate: 149 Ruby files lint clean; 296 tests /
  3259 assertions passed.
- [x] Chromium: legacy default100, slider50/200 dispatch, acknowledgement/output,
  independent circle24 and compact layout passed. Visually inspected Settings.
- [x] Native renderer: 15 aspect/zoom combinations, radii, centered UV windows,
  coordinates within texture and constant ring layout verified. outputs/native-052.json.
- [x] Reloaded live Settings through VBO; actual slider150 request updated the
  persisted preference, retained circle60, no errors/overflow. Restored original
  image zoom after QA; source files/model geometry untouched. outputs/live-052.json.
- [x] RBZ rebuilt and explicit runtime archive/manifest verified.
