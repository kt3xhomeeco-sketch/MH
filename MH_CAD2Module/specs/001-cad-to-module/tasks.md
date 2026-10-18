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
