# Tasks

- [x] Extend percent normalization and slider through300; explain clipping.
- [x] Centered magnification clipped to original circle; retain complete fit<=100.
- [x] Trim unused white margin in memory with three-pixel safety space.
- [x] Portable mesh/fit/clipping/crop/color/source tests passed. Scoped gate:
  151 Ruby files clean;301 tests /3806 assertions, no failures/errors.
- [x] Chromium Library/HUD workflow passed, including250% dispatch and independent
  circle size. Actual Settings reloaded with max300.
- [x] Native SDK:30 aspect/zoom cases, bounded vertices/UVs and one-pixel border
  passed; prepared sample256x256 became195x251 without changing source bytes.
  GPU textures refreshed; native-054.json and trimmed-hud-054.png.
- [x] Actual HUD remained active without draw errors. Live slider230% observed;
  retained this user choice after removing the QA timer's restoration to100.
  Circle63 retained; stored230% verified. retained-zoom-054.json.
- [x] RBZ archive/manifest rebuilt and verified.
