# Tasks and acceptance evidence

- [x] Stable Options nodes, focus/drafts, batched edits, thumbnail cache.
- [x] Options Save SKP and independent assembly payload/import.
- [x] Module/part display names, safe filename and current-value export.
- [x] Exact filler T and 50 mm backing, output depth growth/shrinkage.
- [x] Portable tests for policy, names, batched jobs and assembly payload.
- [x] Native private-copy filler edits, saved names/current values, three-member
  eight-contact assembly roundtrip, batched values and subsequent Scale.
- [x] Browser rename/assembly presentation checks, Options focus across structural
  changes and the existing Options/DC LIST/assembly browser suites passed.
- [x] Scoped gate: 143 Ruby files lint clean; 290 tests / 3154 assertions passed.
- [x] VBO reload of the visible Options dialog: new Save SKP button verified,
  no pending drafts existed, model/selection retained. Parametric was closed;
  its new page is verified in browser and loads on the next normal open.
- [x] Final RBZ built and manifest/archive verified.

Native evidence: outputs/native-047.json (34 checks), including untouched source
DC -> own generated model -> SKP -> import and repeated T edits, plus overwrite
backup. Reload: outputs/reload-final-047.json; browser: outputs/browser-047.json.
Browser checks are distinct from native
geometry checks. External assembly links and whole nested assembly export are
guarded, not silently flattened. No new native Undo claim is made by this feature.
All native QA uses private objects and restores user selection/source fingerprints.
