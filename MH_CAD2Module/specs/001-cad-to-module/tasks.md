# Tasks

## Setup and foundations
- [x] T001 Establish Spec Kit specification, constitution, plan and quality checklist in specs/001-cad-to-module/.
- [x] T002 Research actual Drawing1 geometry and host/API decisions in research.md.
- [x] T003 Implement immutable source library and local ODA conversion in worker/library.py.

## US1 — Automatic module boxes
- [x] T004 [US1] Implement panel evidence, enclosures and depth inference in worker/geometry.py.
- [x] T005 [US1] Implement product discovery, requests and Excel lists in worker/main.py.
- [x] T006 [US1] Add project settings, async jobs and label placement in settings.rb, jobs.rb, model.rb.
- [x] T007 [US1] Add product input and management/CAD viewer in main.rb and ui/.
- [x] T008 [US1] Verify translation/unit changes, missing depth, panel grouping and label world placement in test/.

## US2 — Explain and correct
- [x] T009 [US2] Add selected-product evidence and correction session observers in corrections.rb.
- [x] T010 [US2] Add split/merge/resize/add/reposition and source marking in corrections.rb and ui/.
- [x] T011 [US2] Persist immutable before/after SKP+JSON and scoped experience replay in storage.rb and worker/.

## US3 — Templates and delivery
- [x] T012 [US3] Add compatible-size SKP template replacement in templates.rb.
- [x] T013 Add RuboCop, Ruby/pytest checks, packaging and usage docs in tools/, README.md and TOOLING.md.
- [x] T014 Run native SketchUp smoke/Undo checks, package RBZ and record validation.md.

Dependencies: T003 -> T004/T005 -> T006 -> T007/T008 -> T009/T010 -> T011/T012 -> T013/T014. Backend geometry and standalone placement tests can execute independently after their dependencies. Deliver integrated journeys, not disconnected mockups.

## User-directed plan-first update
- [x] T015 Filter leaders/section glyph blocks; preserve text titles and marker metadata for view roles in worker/main.py and views.py.
- [x] T016 Derive plan bays first, match construction tiers and section joints, and infer separated unlabelled views without front-first fallback.
- [x] T017 Apply user-confirmed material priors and stock-verified exterior trim classification; separate trim references in model/state/correction snapshots.
- [x] T018 Add check-only front view control, stage overlays, target-scoped cache and regressions; run native SP01 measurement/Undo checks and build on its real label.


## US4 — Similar geometry learning
- [x] T019 Specify measured-anchor transfer, partial examples and ambiguity outcomes; add regression fixtures/tests.
- [x] T020 Implement accepted-example compilation, topology matching, measured face transfer and consensus in worker/learning.py.
- [x] T021 Integrate exact/partial/similar learning after both worker input paths; expose explanations in management UI and docs.
- [x] T022 Run pytest, Ruby/RuboCop, real-example checks, native temporary reconstruction and package 0.3.0 without building a user SP.

## User regression repair
- [x] T023 Reproduce SP28/SP29/SP30 from failed worker jobs and preserve their view fixtures.
- [x] T024 Repair fragmented caps, framed doors, section correspondence, stock strips, whole-tier coverage and auxiliary coordinate offsets; invalidate derived caches separately.
- [x] T025 Pass regression/full checks, native temporary checks and real three-product retry; package 0.3.1 and record results.

## US5 — Build stages
- [x] T026 Specify stage defaults, persistence, 1600 mm provisional height and plan-only evidence/learning boundaries.
- [x] T027 Add Settings checkboxes, independent plan-only worker path and stage-separated caches.
- [x] T028 Verify stage persistence/UI, real and standalone plan geometry, full-mode regressions and native temporary construction; activate plan only and package 0.4.0.

## SP32 short trims
- [x] T029 Capture real selected-edge regression and implement short-trim extraction, measured neighbour binding and solid auxiliary proxies.
- [x] T030 Pass scoped checks and native verification, add the two missing SP32 trim proxies with immutable history, and package 0.4.1.
- [x] T031 Preserve scanned CAD coordinates/plane instead of labels for direct SketchUp scans, including capture offset, source hash, native placement and correction rebasing.

## Scans without manual codes
- [x] T032 Remove direct-scan code entry, generate internal history identifiers and preserve geometry-based learning identity.
- [x] T033 Verify request/worker/native routing and UI, reload the live app, and package 0.4.2.

## US6 — User-drawn correct boxes
- [x] T034 Specify manual correction lifecycle and collective geometry normalization; implement actual-edge capture and cuboid validation independent of input axes.
- [x] T035 Add Sai/Quét box đúng/Kết quả đúng/Hủy sửa, preserve originals and explicit immutable accepted history; support exact plan-stage replay only.
- [x] T036 Pass geometry/worker/browser/native checks, verify real accepted-event replay, reload live runtime and package 0.5.0.
- [x] T037 Remove the manual box-scan step; accept and validate the current native selection, preserving ignored CAD and empty-selection sessions.
- [x] T038 Verify simplified UI/native workflow and quality gates, reload live runtime and package 0.5.1.
- [x] T039 Profile the user's accepted boxes and native UI; add immediate pending, correlated saved/error feedback, duplicate prevention and completed cursor behavior.
- [x] T040 Verify feedback/retry/native acknowledgements and quality gates, reload preserved live model and package 0.5.2.
- [x] T041 Add lightweight receipt/result acknowledgements, read-only status recovery, eight-second feedback, duplicate caching, session validation and explicit missing-bridge handling.
- [x] T042 Verify dropped request/reply and twenty-minute simulated cases plus native no-duplicate history, reload preserved live model and package 0.5.3.
- [x] T043 Reproduce wrong-source feedback from actual single/two-bay scans; restrict correction targets, expose source identity, validate extents and replay measured X/back offsets.
- [x] T044 Relink the three preserved external boxes to the matching CAD, restore the mistakenly modified source, and verify a fresh real-worker/native rebuild with immutable repair history.
- [x] T045 Complete quality gates/UI verification, reload 0.5.4 and package the fix.
- [x] T046 Reproduce SP40 overlap from real scan, verify internal identity isolation and implement nonoverlapping plan chains/auxiliary subloop deduplication with regressions.
- [x] T047 Pass quality/native gates, verify current CAD, retry SP40, reload and package 0.5.5.

## Solid auxiliary trims / Settings (0.5.6)
- [x] T048 Specify and implement remembered default-on auxiliary creation checkbox and solid physical trims without altering recognition/learning identity.
- [x] T049 Verify browser persistence, Ruby settings, full quality gates and native on/off geometry; convert current SP40 owned trims, reload dialog and package 0.5.6.

## Circular plan profiles (0.6.0)
- [x] T050 Implement measured circular plan profiles, ArcCurve solids and manual prism capture with preserved learning metadata.
- [x] T051 Include SP41 curved end in automatic plan recognition and complete source bounds; retain wrong-source guard.
- [x] T052 Verify Ruby/Python/UI/native regressions; migrate active SP41 correction metadata, reload and package.

## SP42 placement / Group output (0.6.1)
- [x] T053 Fix complete learned-source coordinate basis with actual SP42 regression and correction acceptance coverage.
- [x] T054 Generate Groups and verify requested product grouping behavior.
- [x] T055 Pass quality/native checks, repair current SP42 result without moving imported CAD, reload and package.

## Automatic plan-rule induction (0.7.0)
- [x] T056 Implement accepted corpus/features/anchor programs and independent validation/activation guards.
- [x] T057 Wire automatic background refresh after acceptance and plan builds; show catalog state/provenance.
- [x] T058 Verify worker, transport/UI/native invariants, refresh real library without inventing training data, reload and package.

## Product work log (0.7.1)
- [x] T059 Implement stable activity identities, complete lazy timelines and safe row-scoped native actions.
- [x] T060 Replace error/history feeds with expandable product work rows and Select-first correction controls.
- [x] T061 Verify Ruby/Python/RuboCop/browser/native behavior, preserve user geometry, reload and package.

## Inline product-row controls (0.7.2)
- [x] T062 Move four primary actions beside every product heading and scope collapsed-row feedback/acceptance.
- [x] T063 Verify browser transport and native dialog, preserve model, reload/package.

## Local AI plan assistant (0.8.0)
- [x] T064 Install/verify portable runtime and model on E, benchmark real inference.
- [x] T065 Integrate measured-candidate AI selection, safe fallback/cache/audit and settings/status UI.
- [x] T066 Pass worker/Ruby/RuboCop/browser/native gates, enable in live app, document and package.

## Shared plan measurements (0.8.1)
- [x] T067 Profile identical scan/library with AI off/on; remove duplicate source measurement without changing output.
- [x] T068 Verify cache invalidation, full quality/native gates, reload and package.

## AI-led search and automatic construction (0.9.0)
- [x] T069 Implement broad accepted-sample search, current-CAD proposal remapping/composition and physical validation.
- [x] T070 Integrate AI search/final choice, bounded runtime/cache/deadline, trace/UI and automatic native preflight.
- [x] T071 Verify unit/browser/RuboCop/real-model/native gates, preserve live model, reload and package.

## Unequal-depth scan fix (0.9.1)
- [x] T072 Reproduce the failed 35-edge scan; recognise measured stepped rear and preserve unresolved source geometry.
- [x] T073 Guard measured recess coverage across AI proposals/native preflight and feedback capture.
- [x] T074 Pass quality/native/real-model gates, reload/package and rebuild only the verified failed source.

## Recessed trims and visible scan feedback (0.9.2)
- [x] T075 Reproduce all three latest scans; fix carcass/door registration and measured front return width.
- [x] T076 Expose scan progress/result and open Management with the concrete reason on failure.
- [x] T077 Verify tests/lint/native/real AI, reload/package, and retry only unchanged sources matching the current model.

- [x] T078 Add explicitly provisional source-envelope fallback, retained diagnostics and native source checks.
- [x] T079 Preserve manual correction/exact replay of failed sources; compact AI prompts while retaining both rounds and all choices.
- [x] T080 Verify preview correction natively, benchmark real inference, finish gates and deploy 0.9.2.

## Keep old boxes and repeat direct scans (0.9.3)
- [x] T081 Diagnose source-hash guard blocking intentional new scans; remove it while retaining scan-code protection.
- [x] T082 Verify quality/native isolation and unchanged originals; reload/package and retry the failed new scan.

## Arc and stock evidence (0.10.0)
- [x] T083 Recognise complete circular runs including axial chords; preserve analytic extrema/native ArcCurves.
- [x] T084 Measure all requested stock spacings, straight/concentric closed-strip evidence and 18+18 seams; integrate plan/AI/history/manual feedback.
- [x] T085 Verify regression/performance/native/UI/full gates; reload and package without changing existing products.

## Scan latency and manual Y registration (0.10.1)
- [x] T086 Profile the actual dense scan and remove redundant rectangle/watch work without losing source checks.
- [x] T087 Add geometry stages/lightweight elapsed progress and preserve near-source manual box registration.
- [x] T088 Verify dense equivalence, native correction/source guards/progress, repair accepted result when originals match, and deploy/package.

## Geometry-only OY sweep (0.11.0)
- [x] T089 Commit before edits and preserve verified archive/manifest.
- [x] T090 Implement stock/Y-span scan, depth groups and double-wall seam evidence.
- [x] T091 Integrate plan-only/DWG worker without AI/old partition transfer; keep exact feedback/frame.
- [x] T092 Show engine/evidence/times/archive status and preserve correction/history/source safety.
- [x] T093 Verify synthetic/real/native/UI/full gates, reload and package.

## Opening UI latency (0.11.1)
- [x] T094 Profile initial state; remove duplicate initialization, repeated product scans and global member searches.
- [x] T095 Verify fresh native membership, real CEF initialization/entry isolation, existing gates and release.

## Named product plan reference (0.12.0)
- [x] T096 Add product/context/view classification and measured elevation/callout checks before named-source recognition.
- [x] T097 Add isolated candidate previews and source-bound confirmation; preserve direct-scan fast path.
- [x] T098 Build separate measured edge/arc reference with settings toggle and module placement.
- [x] T099 Verify synthetic/real/DXF/native/UI gates, preserve model and package/live reload.

## Multiple named plans and auto labels (0.13.0)
- [x] T100 Keep supported horizontal plans despite size mismatch; arrange independent view results with1000 mm clear gap.
- [x] T101 Add Registry-style auto labels with8000 mm minimum/dynamic span, consistent correction placement and per-view logs.
- [x] T102 Verify real SP01, orange fallback/correction/undo/label clearance, full gates, package/reload and retry failed request.

## Detail-section exclusion (0.13.1)
- [x] T103 Reproduce SP04 seven-versus-three error; bound whole-product size tolerance and check independent peer plans.
- [x] T104 Verify source/threshold/peer regressions, full gates/native rollback, package/reload and repair unchanged generated SP04 results.

## Full CAD scope, missing L plans and SP range (0.14.0)
- [x] T105 Reproduce SP08 clipping and six titleless SP11 sheets; preserve stock profiles and perpendicular plan branches.
- [x] T106 Add inclusive start/end entry with single-field/list compatibility and validation.
- [x] T107 Verify geometry/range/browser/native gates, source-safe live repair and package/reload.

## Indexed parallel panels / resident cache (0.15.0)
- [x] T108 Replace all-later parallel comparisons with stock-offset and interval lookup; verify caps/real thickness/seams and directional/L footprints.
- [x] T109 Add revision/spatial source cache, persistent serial worker, change/cancel/death guards and exact-feedback index.
- [x] T110 Verify cold/warm/source-change/native polygon/lifecycle/UI gates, measure actual latency, reload/package and preserve model/history.

## Section-first elevation (0.16.0)
- [x] T111 Specify independent stage/shared panels and link marker orientation/position to plan bays.
- [x] T112 Implement section tiers, front checks, multi-plan cut levels, conservative provisional recovery and source-frame corrections.
- [x] T113 Verify full scoped gates, native solids/worker/UI, actual-source read-only results, package and guarded live reload.

## Direct scanned L recovery (0.16.1)
- [x] T114 Reproduce2016-edge native failure; recover perpendicular closed bays, auxiliaries and common rail without filling the empty L/gap; preserve exact feedback and rotated layouts.
- [x] T115 Verify full Python/Ruby/RuboCop gates, browser explanation, cold/warm native worker and aborted native source-bound builds on the user's pasted Untitled1 plan; package and guarded reload.


## Combined direct scan (0.17.0)
- [x] T116 Specify native annotation capture, crop/transform/source-watch behavior and independent plan-only stage.
- [x] T117 Implement readable text/symbol and exploded-cut recognition, section composition/source placement, provisional correction targets and UI diagnostics.
- [x] T118 Verify metadata/ambiguity/multiple-plan Python regressions, full scoped gates, native transformed/stale/cropped source-bound solids, actual Untitled1 stage isolation and UI; package and guarded reload.


## Deeper exterior panels / framed fronts (0.17.1)
- [x] T119 Reproduce actual new Untitled1 scan; retain measured outer panels and the complete front frame rather than infill only.
- [x] T120 Verify actual multiview/rotated regressions, source-bound native solids/toggle/volumes, UI/full gates, package and safe reload without replacing user geometry.


## Full registered elevations and measured L trim (0.18.0)
- [x] T121 Record source-bound user clarification:692 mm separates carcasses; top30 mm band is cabinet trim, not ceiling/wall.
- [x] T122 Implement independent strict geometric registration, short parallel trim proof, native source/projection checks and UI diagnostics.
- [x] T123 Verify Python/Ruby/RuboCop/UI and actual-source native solids/toggle, package/reload; build a new measured result while preserving edited user boxes.

## Single solid L trim (0.18.1)
- [x] T124 Add source-scoped confirmed50x30 trim representation with retained actual-panel proofs and native validation/UI.
- [x] T125 Verify all scoped gates/native/UI, guarded live trim-only update and package; document symbol sample directory without claiming template recognition is implemented.

## Complete aligned CAD references (0.19.0)
- [x] T126 Preserve uncropped source for combined named imports even with unresolved heights; retain independent plan-only/direct scan behavior.
- [x] T127 Put each CAD view in a separate root Group; align XOY/XOZ, cuts alongside, closed/open-front semantic tags and bounded stock-pair matching.
- [x] T128 Run scoped gates/browser/native source-solid/reference checks, preserve live user model, package and safe reload; document actual limitations.

## Cut-level placement, compact entry and direct edits (0.20.0)
- [x] T129 Measure horizontal-cut Z with ambiguity guards; stack CAD at shared XY, reuse references and preserve module/source transforms.
- [x] T130 Add compact entry actions without messages/hints, numeric/generic codes through source/labels/cache and fresh scoped action routing.
- [x] T131 Keep boxes visible after Sai, accept direct edits of owned boxes, reject foreign product boxes and preserve before/after data.
- [x] T132 Complete full scoped/targeted Python, Ruby/RuboCop, browser and native tests, verify package, guarded reload and compact entry.

- [x] T133 Reproduce actual SP20 missing markers; stack references at sharedXY with explicit1000 mm provisionalZ; preserve measured heights/direct CAD/modules.
- [x] T134 Enter builds from entry dialog; verify disabled/repeat/IME and both code fields.
- [x] T135 Full Python/Ruby/RuboCop/browser/native regression, package and safe live reload; record actual limits.

- [x] T136 Vertical/side CAD references parallelYOZ; fronts stayXOZ; verify native transforms, arcs and depth direction.
- [x] T137 Single plan placedZ0 regardless of source cut height; preserve proof and multi-plan/direct-scan behavior.
- [x] T138 Required gates, safe load/package; guarded relayout of latest imported references when unchanged.

- [x] T139 Actual SP24 regression: local repeated-code families, caption recovery, six horizontal cuts and source order.
- [x] T140 Visible nested arrows, cut-position/edge fallback, native proof validation and full-outline/row ownership.
- [x] T141 Full-source B/C registration, same-width peers, L polylines across title borders and contained front details.
- [x] T142 Required tests/browser/native actual-source QA, package and safe live load; only repair unchanged original references.

- [x] T143 Reproduce wall-contaminated plan depth/SP27; separate closed standard-stock datums from complete source bounds; index pairs/endpoints, preserve bevelled and diagonal panels.
- [x] T144 Register side minimumY against the cabinet arm intersected by cutX after direction rotation; register plan levels from cabinet minimumY; explicit pending datums, native validation and diagnostics.
- [x] T145 Run required gates/native actual source, record wall/nonstock regressions and timing; package0.21.1, safe live load without moving original scans or edited user geometry.

- [x] T146 Reproduce actualSP25 unclassified2-2/3-3; unique external vertical-symbol+stock-height fallback, preserve local duplicate-code scoping and reject ambiguity/wrong geometry.
- [x] T147 Vertical/side referencesMH_DWG2; retain other semantic tags; native rootGroup/tag checks.
- [x] T148 Separate open front to the right500 mm; preserve registeredYOZ and add source-orderedXOZ copies with500 mm edge gaps; independent display/proof validation and UI.
- [x] T149 Required gates/browser/native actual-source regressions, guarded in-place SP25 repair/backups/history, package0.22.0 and safe live load.

- [x] T150 Reproduce SP25 retry61d75182: source still8+3 views, primary/two old box sets trigger duplicate guard, only last shared child becomes cropped fallback.
- [x] T151 Separate complete CAD restoration from named module reuse; validated explicit source owner across jobs, no silent shared fallback, idempotency and existing CAD-edit guards.
- [x] T152 Full Python/Ruby/RuboCop and browser/native retry regressions; restore10 missing live references, retain3 box sets/front and back up verified partial fallback before replacement.
- [x] T153 Package0.22.1, safe runtime load and final live reference/owner check; record evidence/limits.

- [x] T154 Gap-indexed W/D/H stock signatures, unique station votes and standard-stock closed geometry; front-to-front merged-stroke fallback for door-only marker carriers.
- [x] T155 Prefer highest-ratio open-front/cut-height registration, retain partial/missing geometry, reject conflicting equal poses; local-arm D and cut-position H checks, independent display layout.
- [x] T156 User clarification: ordered two-sided single-middle-gap stretch recognition even at50% coordinate matches/over50% total size difference; preserve geometry, warn about unaligned side and keep unresolved heights provisional.
- [x] T157 Python/Ruby regressions and independent native proof validation; maintain actualSP24/SP25/SP27, direct scans, missing-reference restore and cache history.
- [x] T158 Final required gates/browser/native, package0.23.0 and safe idle runtime load; record timing, preservation and practical limits.

- [x] T159 Reproduce latestSP25 job9eb649ce; distinguish intentional500 mm display offset from logical pairing, obtain explicit front-overlay clarification, add data-derived2–3 height verification for cropped fronts.
- [x] T160 Overlay front Groups/tags, retain side copies500 mm beyond all fronts, validate new mode and archived layouts; prevent automatic Manager opens for builds/errors/previews.
- [x] T161 Guard existing-reference relayout with source/native geometry/previous placement checks, preserve edits/locks/boxes and idempotency; aborted native regressions and guarded liveSP25 correction with backup/history.
- [x] T162 Required gates/browser/native, package0.23.1, safe idle runtime load, current live/reference proof checks and evidence.

- [x] T163 Separate measured SP-envelope height from pending module-tier partition; native height proof, raised/noisy/conflicting/missing-height cases and final replay protection.
- [x] T164 Guard in-place untouched1600 envelope refresh; protect moved/edited/locked/manual/source-changed boxes and retain CAD/Group identities/history.
- [x] T165 Python/Ruby/RuboCop/browser/native gates, guarded liveSP25 height update, package0.23.2 and idle runtime load; document evidence/limits.

- [x] T166 Diagnose SP25 raw-context depth regression; preserve resolved DXF/native stroke metadata, compatible stock datum/depth witnesses and style-aware cache/watch identity.
- [x] T167 Separate cabinet/raw bounds in bay checks and previews; corroborate SP25 depth using1-1/2-2/3-3, validate small drafting discrepancies and native proof.
- [x] T168 Guard in-place preview depth shrink, retain height/CAD/user edits/deletions, run native source-style capture/watch/hash and preview refresh regressions.
- [x] T169 Required gates/browser/native, safe live retainedSP25 repair, package0.23.3/runtime/index4 timing and evidence.

- [x] T170 Reproduce SP25 all-or-nothing curved-end/short-trim failures; reconcile A-A/B-B/C-C using rigid stock registration and retain independent closed bays.
- [x] T171 Local provisional gaps/tail/roof bands, measured front wall/cap profile proof, unique complete source/reference levels and one common layout; no hard-coded SP coordinates.
- [x] T172 Guard untouched preview replacement with snapshots/history and unchanged CAD; protect moved/edited/locked/manual/source-changed boxes, portable/native proof tests.
- [x] T173 Required regression/browser/native gates, package0.24.0/r37, safe idle runtime load and actual timing/preservation evidence.

- [x] T174 Reproduce missing SP25 plinth and split roof; measure continuous front bands against linked side stock faces and preserve actual18mm inset/292mm plinth depth.
- [x] T175 Recognise SP35 horizontal5-5 despite large L span; independent perpendicular stock components, provisional unclosed end and projected-arm/auxiliary sums against furniture fronts A/B.
- [x] T176 Native profile/component preflight and selective refresh of unchanged/affected Groups; guard edits/movement/deletion/source changes and retain untouched shared/locked Groups without mutating them.
- [x] T177 Required gates/browser/native, safe runtime/live repair, package0.25.0/r38 and actual evidence/limits.
