# Ordered view chains, release0.23.0

Implemented2026-10-21 in the existing app; Spec Kit prerequisites and repository Karpathy guidelines applied. No branch, commit, delegation, C/Rust migration, AutoCAD launch, original-source modification or accepted-library deletion.

## Behaviour and evidence

Names propose roles. Closed standard-stock faces produce deduplicated stations on physicalW/D/H; gap tokens index at most the next3 stations. Hypotheses256, large repeated buckets128 and returned candidates8 bound work; ambiguity remains explicit. Front-to-front merged structural strokes carry a separate non-stock basis when door drawings hide panels. Only this fallback may use non-stock strokes; it does not grant height evidence.

Preferred open-front chains connect partial plans at their source horizontal-cut heights. ActualSP24 A/B width comparison has an18 mm phase ambiguity; the open front and cut-height station chain resolve B/C at25 mm inset and preserve full returned L polylines. ActualSP25 partial open/complete fronts share their measured chain; cuts2-2/3-3 retain marker links to the complete front. Duplicate markers, wrong full source heights and tied equal poses remain unresolved. Local-arm D chains compare CADY with side CADX after arrow direction; H chains independently check section floor. Logical coordinates stay independent of the500 mm standing inspection row.

User clarifications were incorporated while implementing: choose highest matching ratio, allow missing/wrong stations and supported10–20% overall discrepancies. A single middle stretch is checked in linear source order using at least two stations each side, equal stock thicknesses, unchanged other gaps and two constant offsets. No aggregate50% exclusion applies to this proof. Exact translation can match only50% while both ordered chains agree100%; anchor the larger side (left on equal support), retain raw geometry and explicitly warn that the other side remains displaced. Never scale geometry or turn this non-rigid association into an unproven measured module height. Unchanged generic size-only/detail guards continue where no measured chain exists; enlarged/detail captions remain excluded.

## Checks

- Required check script:379 pytest passed,47 dependency warnings,84.69s;72 Ruby tests/276 assertions passed;24 runtime Ruby files scoped RuboCop/rubocop-sketchup clean.
- A final direct-link fallback was then added for a missing/ambiguous intermediate open-front link. Its40 affected Python tests passed in10.52s; fresh regeneration of8 QA products changed no source transforms/module origins/sizes. Nine regenerated actual/synthetic products independently passed Ruby proof validation.
- Three browser suites passed: CAD views, main manager and compact entry. Manager shows axis, matching percentage, slicing and unresolved evidence; entry actions/Enter remain intact.
- ActualSP24 native:23 independent root Groups,6 measured horizontal levels, symbol directions, correct B/C complete extents,25 mm inset and no duplicate references;5.659s including six builds/source geometry/snapshots.
- ActualSP25 native:11 independent root Groups,3 YOZ cuts plus3 XZ copies,500 mm open-front/copy gaps andMH_DWG2;1.120s.
- ActualSP27: full source depth785 mm retained while cabinet-side datum stays0…600 mm;0.289s. Wall-shift tamper rejected.
- Native low/source scan:5 imported CAD Groups versus0 generated reference Groups for direct scan, true arc preserved;0.487s/0.181s.
- Native single-source700→displayZ0 and SP20Z0/Z1000 passed, including trueArcCurve onYOZ;0.412s/0.596s.
- Native retained-box retry restored10 missing references to11, preserved old edits and rejected wrong-source/missing-owner cases, repeat idempotent;1.609s.
- Native synthetic one-gap case: source front4518 mm retained, coordinate matches50%, ordered matches100%, gap difference−2800 mm, two independent CAD Groups, height provisional and tampered gap rejected;0.264s.
- Drawing1 remains supported: upper3-3 provisional; lower4-4 two860×600×2110 mm modules atZ50. Door-only front transfer passes independent Ruby validation.

W graph timings on archived fixtures: SP24≈0.131s,SP25≈0.159s,SP27≈0.006s,SP20≈0.012s. These are correspondence times, excluding parsing, full pipeline and native geometry creation; they are not end-to-end speed claims.

All native checks used aborted operations and verified model entities, registry, tags, settings, selection and disk file preservation. Existing rescued Settings JSON/eval tracepoint noise remains outside this feature; deliberate malformed-proof checks generated expected rescued ArgumentErrors. No live user product was replaced for testing.

## Delivery

Runtime0.23.0 safely loaded on SketchUpPID25676, modelE:/MAC/OneDrive/Desktop/1.skp. Verified geometry, modified state, camera, selection, tags, registry and file hash unchanged; no model save. Idle worker stopped so next request loads current Python. Manager was closed, so its new diagnostics appear on next opening. Original source/index/history remains; derived recognizer33 invalidates analysis cache only. Existing model results are retained; new inference applies to new builds.

Packageoutputs/MH_CAD2Module-0.23.0.rbz has73 byte-verified entries. SHA256666a01bf9a3c2462558141ce7feac822cd7902f66e906eb5059e375291a09f36. Receipts: outputs/view-registration-package-result.json, view-registration-live-load-result.json, view-registration-native-result.json and the SP24/SP25/SP27/reference-restore/YOZ native receipts.

Remaining limits: one edited gap is recognised only when both ordered sides have enough measured stations; multiple edits/missing chains or equally supported poses remain pending. A single rigid CAD placement cannot align both sides of a stretch. The warning and provisional height are intentional, while actual source coordinates stay available for inspection/correction. This release does not claim all module heights or all arbitrary CAD view associations are solved.
