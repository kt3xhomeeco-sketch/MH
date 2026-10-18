# Verification

Already-open SketchUp model `1`, PID 25420 / VBO 53244. Independent copies of
assembly 450543 only; original entities, definitions, selection and fingerprint
were retained. No source SKPs were rewritten.

- Scoped gate: 119 Ruby files with no RuboCop offenses; 249 tests, 2702 assertions,
  zero failures/errors/skips.
- Native edit checks: seven checks covering repeated T1=20/18.6/17.6/30, private
  T2=9/8, unchanged other member inputs, atomic failure and formula probe/native
  agreement on cabinet/door anchors with rotated/reflected wrappers and members.
- Previous native Scale suite rerun: all 11 scenarios passed, including shrinking,
  enlargement, repeated axes and two side-by-side cabinets.
- Actual observer/Undo/Redo suite: nine checks passed. Aggregate bounds stay fixed
  through common T1 edits, Undo/Redo and subsequent Scale. An unrelated standalone
  Scale queued immediately before an assembly edit still reconstructs correctly.
- Actual ModuleOptions callback/observer checks: five passed, covering aggregate
  bounds, unchanged-input no-op, no second Scale reconstruction and coalesced UI
  refresh timers. Source state retained after asynchronous cleanup.
- Electron option-window smoke passed, including unchanged values, queued edits,
  returning to the prior value while a new value is in flight, stale input/root
  switching, errors and readonly formulas.

Controlled same-source profile (two repeated T1 edits, includes rule editing and
test verification): before 0.724/0.695 s, after 0.550/0.582 s, approximately 20%
less measured work despite adding aggregate preservation. Native Scale prepare
calls fell from five to three, native result verifications from seven to five.
These are local fixture measurements, not a latency guarantee for all libraries.
Per-root observer acknowledgement and option refresh deduplication were verified
separately after that profile.

Captures: `outputs/assembly-edit-041/{before-controlled,after-controlled,native,
options-native}.json`, plus copies of the Scale/async reports. Calculation-only
probes cover owned leaf/root anchors; other anchors retain native probing. Repeat
layouts retain their existing source/copy semantics and skip aggregate fitting.

Packaged `outputs/MH_Module_Studio-0.1.0.rbz` through the explicit manifest.
Final VBO reload succeeded in model `1`, including the already-open compact
options window. Assembly 450543 remained selected; source fingerprint and
definition identities were retained (`reload-final.json`).
