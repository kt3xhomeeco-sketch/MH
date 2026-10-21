# Verification — 2026-10-15

## Behavior preserved

Before editing, saved source copies and numerical baselines in
outputs/architecture-026. The three real captured fixture snapshots retain exact
parameter metadata, six sheet cells/formula text, parameter plan bounds/errors
and Scale plan bounds/errors after refactoring. Full hash-checked SDK audit of
227 source files is byte-equivalent JSON before/after: 88 compile, 59 reader
failures, 80 compiler failures. No new DC coverage or changed diagnostic policy.

## Portable gate

Spec Kit prerequisites resolve this spec/plan/tasks. Scoped RuboCop inspects
67 Ruby files without offenses. Full suite: 170 tests, 2,205 assertions, no
failures/errors/skips (previously 164 / 2,136).

Six new tests establish: cold core load with precisely the 18 declared pure
components and no host APIs; static token-based host-dependency exclusion;
separate numeric/symbolic/sheet program method owners; detached learned/built
rules and source snapshots; frozen saved inputs across sheet/preview/failed-edit
and Scale operations; output edits and alias maps cannot change global data;
independent numeric instance state; ATT failure evidence remains available to
Studio's geometry fallback. Existing dialog, rule, parametric, HUD, geometry,
function-capture and repeated Scale tests remain active.

## Native cold start and existing data

Started a new owned SketchUp 2025 process PID9456, VBO port60082, at
outputs/architecture-026/1.skp. This verifies the refactor without legacy class
methods remaining in memory. Numeric Program has no sheet/symbolic extensions;
host discovery is absent from DCFormulas. File enrichment through the extracted
DCFunctionCapture adapter resolves actual LC100 references, compiles a stable
rule, restores abf_eval and registers no imported functions. Model roots,
definitions and selection retained.

Rechecked all 69 previously exported modules in actual SketchUp: editable
parameter changes at +/-0.1 mm where admissible, apply, verify, idempotent
recalculation, reverse and verify. All 69 pass, with original test model retained.
All 227 source hashes and 69 output SKP hashes still match their original report
entries. No source or exported-library geometry files were overwritten.

Reused the existing native Scale suite in that isolated process, retaining its
assertions and changing only the pinned process guard/output path. All 21
recorded checks pass, including geometry/idempotence, single and batch Undo,
Redo history, post-Scale parameter edit, move/rotate filtering, rotated and
mirrored Scale, independent shared-definition copies, converted-library import,
unsafe shrink rollback and injected partial-apply failure rollback. Cleanup
restores original roots/definitions/selection. Library configuration is switched
only in memory for this test and restored; preferences are not written.
Artifacts: cold-native.json, native-library.json and native-scale.json under
outputs/architecture-026.

The known 025 limitation on automatic Scale of two corner cabinets' non-box
Viền remains. Native Scale suite results do not assert that every one of the
69 exports supports every Scale operation. Verified-box, envelope, topology,
curve/DADX and nested-scale limitations are preserved.

## Live reload and packaging

Reloaded user SketchUp PID21612 / port7891 through VBO, using dependency order
and removing obsolete hot-loaded sheet/symbolic methods from numeric Program.
Parametric's old implementation methods and DCFormulas' old host-discovery
method are removed; public facades remain. Post-reload numeric and sheet checks
pass; model entities/definitions/selection/modified state are unchanged.

One explicit runtime_manifest.json now drives both lint staging and packaging:
18 portable calculation files, 10 adapter files and 20 assets/docs. RBZ contains
49 entries including the loader (29 Ruby files); CRC and source/manifest checks
pass. Tools, tests, Specs, captures and test models remain excluded. Public saved
rule and library payload schemas are unchanged. ARCHITECTURE.md records
ownership, intentional shared math, data-copy boundaries and future change rules.
