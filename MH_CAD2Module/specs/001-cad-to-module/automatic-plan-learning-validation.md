# Automatic plan learning 0.7.0

Implemented with Spec Kit specification/plan/tasks and Karpathy Guidelines. No model/API AI or AutoCAD process is involved.

## Acceptance criteria and evidence

- Three independent plan geometries with varying widths/depths produce an active measured-anchor program only after every held-out geometry is reconstructed within 0.05 mm. Unseen 1090/470 mm bays at depth 710 mm remeasure correctly. A circular variant remeasures an unseen radius 140 mm from actual CAD circle evidence. Both synthetic programs live under outputs/l only.
- One/two samples or repeated correction of the same geometry do not activate. Conflicting grouping, partial samples, excluded events, changed stock/topology and disagreeing anchor expressions do not transfer. Updated feedback invalidates the catalog. Parser updates, damaged catalog checksums and missing status files are handled without changing accepted history.
- Actual worker geometry action chooses the learned rule on a new source and preserves its source XY origin and plane offset. Same-geometry accepted feedback remains higher priority. Full-height layouts retain their existing path.
- Saved acknowledgement precedes queueing; background failure does not invalidate saved boxes. Queue deduplicates pending libraries and waits for an existing job. Learned status and source provenance appear in the manager. Existing lost-request/reply/20-minute transport tests remain applicable.
- Native SketchUp 2025 PID 2724: two unseen learned assemblies built as manifold root Groups; dimensions, source origin [30000,40000], Z offset 73 and native R140 ArcCurves passed. Temporary geometry and assembly metadata were aborted/restored; the user's selection and geometry were preserved. Receipt: outputs/plan-rules-native-result.json.
- Native flat Groups lifecycle/acceptance regression and actual SP42 origin/R150 regression passed. The former asserts exactly one learning queue request after acceptance, with training stubbed to prevent test samples entering the real library.
- A real windowless learn_plan worker invoked through the normal queue completed successfully against the current library. It found four eligible distinct plan examples in four construction families: zero active, four waiting, zero blocked. No synthetic examples entered that library. A whole-model geometry comparison before/after background learning was unchanged.

## Limits

This is conservative topology-preserving rule induction. It does not infer different bay counts, arbitrary furniture families, missing parts or full elevation/tier layouts. Each output plane must bind consistently to measured input edges/stock centres with bounded fixed offsets; arcs require measured CAD circles. Inactive families retain exact replay/base recognition with a status explanation. A matched active rule whose target evidence disagrees stops for review. Plan-only height remains explicitly provisional 1600 mm. Training alone never rebuilds an existing product.

## Release gates

Final automated/native/UI/package counts are recorded in the release receipt outputs/plan-learning-release.json and TOOLING.md. Runtime RBZ excludes library, outputs, tests and development tooling.

Completed: 96 pytest, 21 Ruby / 80 assertions, scoped RuboCop on 16 runtime Ruby files, six browser checks, three native geometry regressions and the live HtmlDialog callback. Final loaded version 0.7.0; native queue refreshed catalog schema 3. Runtime package has 36 files and excludes user/development data.
