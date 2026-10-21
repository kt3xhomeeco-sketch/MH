# Partial partition: SP25, 2026-10-21

User requirement: keep every independently recognised module; one bad region cannot force the complete SP back to its envelope. Compare A-A, B-B, C-C in the common X0..2610 interval, retain the unmatched end as a correction box.

## Cause

The old complete-layout finishing step raised on A-A's unclosed oblique end and B-B's short auxiliary whose rear edge differed by about0.186mm. The caller replaced the entire plan with one envelope. Repeating this for three horizontal sections created three full-width boxes. The0.23.3 depth/height fix correctly measured310/2730 but did not repair this partition failure.

## Implementation

`worker/partial_plan.py` runs after ordinary combined recognition for failed repeated named plans with a proven common rigid width registration and an open front. Reuse the indexed stock-pair bay scan; filter context strokes, retain actual bay/depth witnesses from each source plan, and require closed standard-stock front walls plus bottom/top caps. An uncertain gap or overlapping candidate affects only that interval. Even one good bay survives. No SP code, source coordinate or2610 threshold is hard-coded.

Assemble one physical layout and retain all three horizontal source references with their independent measured/provisional levels. Plan-only, direct scans and manually confirmed layouts remain on their existing paths. This release does not generalise the new reconciliation to every layout or infer sections from names alone.

Native `PartialPlan` preflight validates source signatures, registration offsets, plan bay widths, front closure, measured heights, repeated310mm side-depth witnesses, XYZ arithmetic and non-overlap. Residual boxes remain provisional even when their containing SP envelope is measured. An untouched old preview may be replaced in an undoable operation with before/after SKP snapshots and an immutable event. Edited/moved/locked/manual/source-changed previews are retained and report why replacement was rejected. CAD/reference identities and transforms do not change.

## Actual SP25 result

- Common structural interval: X0..2610mm, depth310mm, supported by vertical cuts1-1/2-2/3-3.
- Left bay: X25..600, width575, Z860..1460, height600mm.
- Middle bay: X618..1614, width996, Z50..2160 and2160..2700, heights2110/540mm.
- Right bay: X1614..2610, same heights, width996mm.
- Solid auxiliaries: widths25/18, full depth310, heights600/2730mm.
- Provisional tail: X2610..3694.829, size1084.829×310×2730mm.
- Two provisional roof bands: each996×310×30mm atZ2700. Front caps end at2700 while the vertical sections/outer trim reach2730. This discrepancy does not invalidate the five closed bay parts. Empty space above the short left bay is not filled.

Known limitation: no located vertical-cut marker belongs to the final996mm bay; its heights are proved by its own open-front wall/cap profiles, not by inventing a cut at its X. The310mm section consensus corroborates product depth. Temporary CAD inspection levels0/1000/2000 are never used as module-height evidence.

## Verification artifacts

- `tools/sp25_partial_fixture.py`: actual source index4, cold disk and resident timings, `outputs/sp25-partial-product.json` and timings JSON.
- `test/test_partial_plan.py`: actual closed bays, local missing-wall failures including one surviving bay, protected manual/scan paths, unique source segment ownership and retained reference levels.
- `test/partial_plan_test.rb`: native portable proof accepts the partial result and rejects tampered height/wall/cap/pose/depth/residual/trim data.
- `tools/native_partial_plan_check.rb`: new build10 independent solid Groups; guarded replacement, unchanged CAD, idempotency and five rejection cases, all inside an aborted QA operation.
- Archived pre-partition output retains the old envelope-height/depth/reference-restoration regression scenarios.

## Completed release gates

408 Python tests/47 existing warnings,116.93s;80 Ruby tests/306 assertions; scoped RuboCop/rubocop-sketchup27 runtime files clean. Three browser suites passed, including explicit five measured modules/three provisional regions,310mm depth, complete section titles, numeric SP entry/Enter/correction controls and ordinary UI.

Native partial QA passed new10-solid-Group construction and untouched-preview replacement, CAD/transform preservation, retry idempotency and moved/edited/locked/manual/foreign-source guards (13.508s across all seven scenarios, not one build). Native SP25 view construction passed with11 independent source/copy Groups (1.067s); archived reference restoration passed (2.828s); no-auto-Manager passed. Archived product-height and depth/style regression suites passed (9.653s/9.562s over six scenarios each). All operated inside aborted QA operations and preserved the user's file, root entities, registry, selection, tags and settings. Expected caught negative-test exceptions and existing settings/third-party observer tracepoint noise were not test failures.

Actual indexed-source analysis:2.258s from disk then1.341s in the same Python process; index load0.0187/0.0010s. Native resident request from current configured source passed independently (compute3.247s, roundtrip4.386s for the first process request while other QA ran). These figures exclude production geometry/snapshot time and are not a claim that a complete build always finishes in1–2s.

Runtime0.24.0 safely loaded in `E:\MAC\OneDrive\Desktop\2.skp`. The user removed the last box during implementation, so no deleted product was recreated and no file was saved. Next explicit build uses the new layout. Package `outputs/MH_CAD2Module-0.24.0.rbz`:81 byte-verified runtime files; SHA256 `85b00059571e416e70c574d9158c18b7a92b52371318a5c7817c52c2367734c0`. No commit/branch, original DWG modification, accepted-library deletion or other-plugin edit.
