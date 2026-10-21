# Validation — 084

- Scoped gate: 238 Ruby files clean; 431 tests, 4703 assertions, no failures/errors/
  skips. Pure tests cover front triangle distance/tolerance and private bounded
  caches, changed geometry/visibility/rules/values, invalid rules and failed loads.
- Native baseline reproduced the interaction limitation: a point just inside a
  narrow front edge became inset, while a point just outside had no placement.
  An exactly centered 18 mm rim hit already worked on the simple fixture.
- Native fixed checks passed on a temporary five-panel cabinet with 18 mm sides:
  exact edge and 6-screen-pixel near-edge points on both sides acquire five real
  outside faces; center/farther interior retain four inset contacts. Repeated on
  a rotated, mirrored, nonuniformly scaled host. Explicit Inside, a disabled mount,
  a hidden front rim and a rear-camera hit retain their required behavior.
  This uses scripted native screen picks, not a manual pointer session or a claim
  that the user's exact host was identified. Receipt: outputs/door-pick-after.json.
- Native Replace baseline on Khung noc lot: about 1896/965/889 ms for a cold source
  followed by repeated equal-sized targets. After cache changes, warmed equal-sized
  targets measured roughly 329–437 ms; varying target sizes measured 670–703 ms.
  Cold source clicks still measured roughly 1.7–2.5 s in different runs. Source
  parsing/validation and first calculations remain necessary; these are local
  scenario measurements, not a performance guarantee for every DC.
- Native varied replacements retained exact target bounds and independent UUIDs.
  Editing T1 in the first result did not affect another result. Protecting the
  loaded definition eliminated the previously observed source-recovery pass on
  a later Replace after that T edit (recovery_calls=0). Geometry/definitions/
  selection were restored by aborting the entire fixture transaction.
  Receipts: outputs/replace-profile-before.json, replace-profile-after.json and
  replace-profile-varied.json. Validation used existing PID22980, port7891.
- Runtime package rebuilt and all 109 archived files verified against source.
- Reloaded into existing PID22980/7891 and PID26160/58644. Model, selection, saved
  Library preference bytes and any pending placement retained. No SketchUp/file
  was opened and no user SKP/config was rewritten. Receipts: outputs/reload084-*.json.
- Other plugin projects untouched. No commit or push for this follow-up.
