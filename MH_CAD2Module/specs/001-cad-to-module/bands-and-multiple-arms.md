# Continuous plinth/roof and SP35 multi-arm scope

2026-10-21, user-directed correction, release0.25.0/r38.

## SP25

The former recogniser required walls taller than100mm to prove a front bay, so it omitted the50mm plinth. It treated the30mm roof discrepancy independently for each996mm body below it, splitting a genuinely continuous1992mm band.

The archived front has explicit closed bands X618..2610 at Z0..50 and2700..2730. Two located side sections1-1/2-2 contain standard18mm end faces at both levels. The measured plinth is1992×292×50mm,18mm behind the door plane after the symbol-arrow depth reversal. The roof is1992×310×30mm. These band heights are assembly envelopes, not new standard board thicknesses. No product-specific coordinate or height is used in the algorithm.

`worker/continuous_bands.py` reads the actual closed front band and corroborating stock faces/marker location/orientation. The former five closed bay parts remain, with one plinth and one roof added; only the unmatched final tail remains provisional. Native band preflight validates the front interval, elevations, both section pairs and actual depth arithmetic.

Existing layouts refresh only changed parts. Unchanged Groups retain their identities; untouched shared definitions or locked unchanged Groups are read without mutation. Changed shared/locked geometry, edited/moved/deleted parts, active corrections and different source revisions remain protected. Before/after SKP snapshots and immutable refresh history are retained.

## SP35

The source has two actual horizontal5-5 cut strokes on fronts A/B. The plan envelope is2170.038×1830mm. The old1200mm shallow-view gate rejected it before using the symbols. A valid horizontal marker plus closed stock geometry now permits this large plan; a title alone or a vertical marker does not.

`worker/plan_components.py` reuses compatible-style, indexed stock pairs in X and Y. It keeps three closed footprints and one unclosed footprint with side-depth corroboration rather than replacing the whole L with a single box. Measured planar footprints are512.001×325,968.037×580,666×680 and1102×500mm; the last is along the perpendicular arm. Eight closed narrow auxiliary pieces are retained.

Ordered front signatures select open-front A for the X arm and open-front B for the Y arm. A perpendicular module can also be visible in the other elevation: overlapping projections are alternatives, not extra physical modules. The B front chooses the580mm projection of the X arm, without creating another module. Standard stock and explicit24mm turned-trim faces delimit furniture;110mm architectural rectangles do not enlarge the furniture sums.

- A: module widths2146.038 + auxiliaries24 =2170.038mm, matching its furniture span. Full source front width2390.038mm is retained separately.
- B:1102 + projected580 + auxiliaries48 =1730mm, matching its furniture span. Full source front width2073mm is retained separately.

Side sections confirm actual depths580,500 and690.001mm. The open right-hand plan footprint is680mm deep, so its10.001mm disagreement is explicitly retained. It remains a provisional box, never silently resized. The first325mm footprint has no matching depth section. Individual SP35 tiers are still pending; its boxes currently use the linked measured whole-SP stock envelope Z26.999..2620mm, not claimed as exact module heights. Front B's arm association is not a fabricated global W offset; unresolved display registration remains diagnostic.

## Verification

Python covers continuous bands, actual SP35 markers/sums/footprints, false-name/vertical-marker rejection, source ownership and pending heights. Portable Ruby checks reject altered band/depth/stock/axis/XY/provisional proofs. Native tests construct the actual solids and all source groups, check retry idempotency and protect user geometry inside aborted QA operations. Full gate and live/package results are recorded in validation.md.

Completed:412 Python tests/47 existing warnings (128.02s),84 Ruby tests/319 assertions, scoped RuboCop/rubocop-sketchup28 files clean. Later diagnostic text passed8 targeted Python cases; the host preference default passed all Ruby checks and native refresh regressions. Browser tests checked new SP35 sums/warnings, SP25 seven confirmed parts/one tail, ordinary manager and compact entry.

`native_sp35_components_check.rb` passed in2.394s:4 solids,8 auxiliaries,14 CAD/reference Groups; all individual tier heights remain pending. `native_partial_plan_check.rb` passed13 scenarios in34.233s across the whole suite, including an omitted host auxiliary flag, shared/locked unchanged Groups, changed/moved/missing/manual/foreign-source protection and retry idempotency. No-auto-Manager regression passed. These native QA operations were aborted with the original file/root geometry/registry/selection/layers/settings preserved. Expected caught rejection exceptions and existing settings/observer tracepoints were not new uncaught failures.

Actual resident SP35 worker request used current source revisionf3abb4...:1.653s compute/2.462s roundtrip, disk index load0.0151s, identical furniture sums2170.038/1730 and unchanged root entities. Timings are separate from construction/snapshot duration.

Live `2.skp` SP25 repair used the product's own archived556ddc... source because the original CAD file had acquired a new whole-file hash elsewhere. Its complete SP25 imported outlines/styles matched exactly. No source guard was bypassed. Eight unchanged Groups (including a tail with a copied definition) retained their IDs; only two old roof Groups were removed and one continuous roof plus one plinth added. CAD identities/transforms/visibility and the assembly transform were preserved; before/after snapshots and immutable history were saved to the existing library. User SKP was not saved. Live proof: `outputs/sp25-bands-live-result.json`; resident proof: `outputs/sp35-resident-result.json`.

Package `outputs/MH_CAD2Module-0.25.0.rbz`:84 byte-verified runtime files, SHA256 `94d990a3427a8605a2c87bf9438a061d40c9e08f6dca7858a5e8a1a454318122`. SP35 association is confirmed at the planar arm/sum level;325mm depth has no corroborating cut,680/690 remains provisional, individual tiers and global registration of the perpendicular B front are not falsely reported as solved.
