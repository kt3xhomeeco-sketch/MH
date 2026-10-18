# Feature Specification: MH CAD2Module

Created: 2026-10-18. Status: Ready for implementation.

## User Scenarios & Testing

### US1 — Build products from remembered CAD sources (P1)
Configure CAD sources and the app-local library once, type product codes/names in a small dialog and receive module boxes centred on matching labels in SketchUp. Excel lists supply the same requests. Rectilinear cabinet drawings are the first supported family; evidence must suffice for width, depth and height. Measure geometry without dimensions, including drawings without view labels.

Acceptance: settings survive reopening; missing and duplicate labels are explained; SP60 yields two lower carcasses and one continuous upper carcass from panel geometry; no label is moved. Unresolvable drawings produce diagnostics, not fabricated boxes.

### US2 — Explain and correct results in SketchUp (P1)
Selecting a generated product opens reasoning and its CAD region. In correction mode, edits automatically produce immutable before/after records. Split, merge, resize, reposition and missing-box addition are supported. Undo is recorded as history, not promoted as a new trusted answer. Structural examples are reused only for matching evidence signatures and explicit corrected state.

### US3 — Independent library and reusable templates (P2)
Changing or deleting original CAD/SKP files does not destroy previous examples. Source bytes are content-addressed; generated/corrected product components are saved separately. Replacement with a reusable SKP module preserves placement and requires compatible dimensions or a parametric adapter; static templates are never distorted to fit.

## Functional Requirements
- FR01: Small product entry dialog; separate management/CAD/corrections panel.
- FR02: Persist source paths, library, Python and converter per project; remember defaults across sessions.
- FR03: Standalone ODA for DWG, direct DXF, XLSX/CSV product lists. Never launch AutoCAD.
- FR04: Archive before parsing; cache by bytes and parser version. Report Xref dependency status.
- FR05: Retain region, geometry handles, measurements and applied rules for explanations.
- FR06: Recognise axis-aligned panels; split double walls, retain single partitions; infer depth only from compatible section/plan evidence.
- FR07: Match label group name or Curic text. Use world bounds centre X; fail on duplicate/missing labels.
- FR08: Centre the entire product on global X, front Y=0, floor Z=0; retain module assembly offsets. Refuse silent replacement of existing products.
- FR09: Auto-save errors and correction transactions with source, before and after; preserve revisions.
- FR10: CAD viewer supports pan/zoom and highlighted source geometry. Region marking helps diagnose missing modules but is not required for supported automatic builds.
- FR11: Actionable errors and progress; parsing does not block SketchUp's UI.

## Key Entities
Project settings; source revision; product region; module analysis/evidence; product instance; correction session/event; scoped example; template reference.

## Edge Cases
Unknown units, nonrectilinear geometry, absent sections, conflicting depths, repeated frames, duplicate labels, unavailable library, changing source, corrected rebuilds, cancellation, malformed files and nested labels must be handled or diagnosed. No promise of arbitrary drawing understanding.

## Success Criteria
SC01: SP60 yields 860×582×2110 (two) and an upper module 1720×582×432 at Z=2160 without DIM data. The upper carcass alone remains 382 high; the full two-leg support adds 50 mm. The 407 mm door finishes 25 mm above the support plane (top-support-fix.md).
SC02: Box dimensions and product/label centre X agree within 0.1 mm.
SC03: Corrections remain recoverable after source changes; snapshots never overwrite prior versions.
SC04: Normal supported use requires only product entry and Build after setup.

## Assumptions
Placement uses global axes. Initial support is orthogonal furniture with declared convertible units. Ambiguity is reported. Template fitting preserves construction.

## Accepted updates during implementation
- Default library is app-local for now; a later move copies data and updates aliases without deleting originals.
- Add Quét chọn immediately beside Nhập mã SP. It captures selected native CAD edges and opens the same code entry dialog. DWG path is optional for this lane.
- Third development control is Karpathy Guidelines, matching MH_modul_studio; pytest is additional verification.
- 0.2.0: plan/horizontal-section bays precede horizontal tier splitting; open-door elevation and vertical sections supply construction evidence, closed-door elevation remains check-only. Leaders/callout blocks are filtered. Missing plan evidence cannot fall back to front-first recognition.
- 0.2.0: SP01/2.dwg produces four modules with a separate 24 mm frontal trim made from 18 mm stock. Confirmed material priors 6/8/12/15/18/25/36 preserve measurements; 36 only suggests a 2×18 laminate. Trim wire references preserve placement/extent and correction history without becoming modules.


## US4 — Reuse accepted examples on similar geometry (2026-10-18)
The user selects the next product only after this implementation is delivered. Do not build a user product during development. Existing accepted SP15/20/21/22/27 samples seed the library; only explicit accepted feedback trains it. Match construction-view edge incidence, not codes, filenames, handles or dimensional identity. Bind each box face to a measured CAD edge or a measured thin-panel centre; remeasure changed bays independently. Require plan, open-front and section agreement, preserve stock thickness, separate auxiliary roles, reject conflicting examples, unbound planes, changed topology and newly crossed continuous panels. Partial examples cannot authorize an automatic complete product. Expose the example, target handles, rules and rejection reason. Corrections accepted later become available on the next scan. Cache derived rules independently of the existing geometry parser version and preserve immutable history.

## Regression repair — user trials SP28/SP29/SP30
The user subsequently tried these three products and reported errors. Repair and retry these requested codes. Recover continuous cap rows split into visible/hidden geometry, retain measured framed-door depth and an external top lid. Match repeated tiers only with matching depth and both section planes; preserve uncut-panel checks. Classify stock-width side/inter-bay strips only from exact plan footprints. Keep floor/front offsets correct after auxiliary bounds change. A missing lower tier must block even when its column has a recognised upper tier. Keep the existing accepted examples and the SP01 24 mm trim rule unchanged.

## US5 — User-selected build stages
The user wants to validate the plan stage before adding elevation analysis. Add persistent checkboxes Mặt bằng and Mặt đứng in Settings. Default: Mặt bằng on, Mặt đứng off. Elevation uses plan as a prerequisite: enabling elevation checks plan; disabling plan clears elevation. No stage selected blocks analysis explicitly. Plan-only construction reads footprint divisions and positions exclusively from plan geometry, including a selected standalone plan without any elevation/section. All provisional boxes are 1600 mm tall at Z=0; this user-authorised height is clearly labelled as a default, not a CAD measurement. Do not split horizontal tiers or replay full-layout examples in this stage. Enabling both retains the established full recognition. Separate stage caches and exclude plan-only corrections from full-height training. Retain existing model geometry; verify with temporary native boxes and leave the live app set to plan only.

### SP32 short-trim correction
The user confirmed the main dimensions and requested two missing 50 mm deep trims be constructed to full cabinet depth. Plan-stage LINE recovery must retain short closed rectangles. For adjacent stock-width strips whose measured depth is 50 mm, use the uniquely matching neighbour's front/back planes to create separate solid auxiliary proxies at the provisional 1600 mm height; preserve the original 50 mm source footprint and explain the user-specified depth rule. Conflicting neighbouring depths require review. Repair only the two missing auxiliary parts in the live SP32 result, preserve all four existing module dimensions and local placements, and keep the completed product centred on its label. Do not apply this provisional rule to full-elevation construction.

### Direct scan placement update
The subsequent user instruction supersedes label anchoring for selected SketchUp CAD: build directly at the scanned plan coordinates/plane. No label is required for this lane. Preserve the scanned plane's offset, including nested native transforms; source capture hashes include plane and offset. Keep DWG-path construction centred on its existing SP label. Correction normalisation must preserve the source anchor. For the current SP32 repair re-capture its current source position (CAD was moved after the earlier scan), add only the two missing trims and preserve existing module dimensions and relative coordinates.

### No manually entered product code for direct scans
Complete rectangle selection starts construction without opening a code-entry dialog. Generate an internal scan identifier for jobs/history; label the visible product Vùng quét CAD. Manual codes remain part of the DWG-path workflow. Geometry signatures, source snapshots and accepted corrections stay independent of the generated identifier. Keep provisional plan-stage corrections excluded from full-height learning. Detect a repeated scan of an already built source/stage rather than stacking duplicate results.

## US6 — Correct by drawing boxes (0.5.0)
After a scan/build, Sai snapshots the incorrect result and hides it. The user draws separate root-level Groups/Components, scans the correct boxes and explicitly clicks Kết quả đúng. Read transformed vertices rather than axis-dependent definition bounds; arbitrary local origins, rotated/scaled/mirrored instance frames do not alter physical dimensions. Require physical axis-aligned cuboids in the product/CAD frame. Normalize the entire collection together to retain relative positions, reject overlap/incomplete boxes, preserve source instances as hidden originals and replace only owned proxies. Hủy sửa restores prior visibility. Record immutable source/before/after snapshots and explicit acceptance. Plan-only samples have no vertical tiers and may replay only at the same geometry signature/parser version, with provisional height 1600; they never train full-height or similar-geometry rules.

### Direct box selection update (0.5.1)
Remove Quét box đúng. After drawing, the user selects boxes with SketchUp's own selection tool and clicks Kết quả đúng. Read the current selection at acceptance, without an earlier capture or stored IDs. Enable acceptance during an idle manual correction; empty or invalid selection reports an actionable error and leaves the session open. Preserve ignored CAD/other entities in mixed selections; hide only accepted box originals. All geometry validation, placement and learning limits above remain.

### Visible acceptance acknowledgement (0.5.2)
The user reports the plugin responds slowly while SketchUp remains usable. Profile the actual accepted source boxes and native UI before changing geometry/storage. Display pending feedback immediately beside Kết quả đúng, prevent repeated submissions, and correlate the native result to the pending request. Explicit saved/error feedback remains beside the button even after the correction session closes. Only active processing uses a wait cursor; a completed/disabled button must not look busy. Invalid selection re-enables retry. Do not claim a reproduced storage slowdown if profiling does not show one.

### Lost-response recovery (0.5.3)
The user reports twenty minutes without feedback. Treat an unacknowledged request as a transport failure, not proof of slow geometry or successful completion. Send lightweight receipt/completion acknowledgements independently of full CAD UI publication. Poll request status read-only every two seconds; after eight seconds show an explicit no-response state instead of an indefinite spinner. Never automatically repeat a save. A matching saved reply recovers missing completion; native unknown status after the deadline permits manual retry. If the native bridge is absent at send time, report it immediately. Retain pending protection while the result remains unknown and allow Làm mới to query it. Cache the latest request result for duplicate requests and validate the originating correction session. Test lost request, lost reply and twenty simulated minutes without duplicate saves.

### Correct external-box source binding (0.5.4)
User draws three boxes outside the generated assembly; editing original generated boxes is not required. A real accepted event linked those external boxes (1310×600 total) to the wrong two-bay CAD (2254×600), so scanning the actual single-bay CAD (1274×591) could not match the saved signature. Select the explicit product or the sole recorded latest build; never fall back to arbitrary model enumeration/stale CAD focus. Show source dimensions/count during correction. Reject plan layout extent changes larger than two exterior 36 mm panels to prevent gross source mismatches. For unique unchanged module widths, align X faces and back planes to CAD independently of hand-box placement; preserve a bounded plan origin offset for replay. Explain unmatched learning rather than claiming feedback was applied. Repair this actual feedback binding using the preserved external boxes at the matching single-bay CAD, keep immutable old records with an exclusion reference, restore the unrelated two-bay product and verify a fresh worker/native rebuild matches all three user boxes.

### SP40 overlapping plan candidates (0.5.5)
User suspects scans without names collide with earlier products. Actual failed requests have distinct internal codes and a source/signature different from earlier feedback. Failure is an 18 mm overlap between the middle bay and an enclosing right-bay candidate. Choose a maximum measured-width chain of nonoverlapping adjacent bays; an invalid candidate must not interrupt a valid chain. Coincident X/back side-pair candidates retain the innermost construction front, with door frontage measured separately. Keep one full measured auxiliary strip instead of also constructing its recovered subloops. SP40 must build widths 1072/300/982, depth 170, height provisional 1600, origins X=18/1090/1390, plus two separate 18×170 auxiliaries. Preserve no-code scanning, reject overlap before reporting ready and retain earlier SP32/wardrobe results.

### Solid auxiliary trims and creation setting (0.5.6)
Physical side/edge/end/plan trims are closed solid proxies, retaining measured positions and dimensions. Settings adds a remembered, default-on “Tạo khối phụ (nẹp)” checkbox. It auto-saves and is disabled during worker execution. Off suppresses trim_parts at new native construction only; modules, standalone wall/panel parts, measured product placement/bounds, recognition data and accepted library examples remain unchanged. Changing the setting is not a correction or learning event. Existing products are not automatically removed/rebuilt. Explicit user-drawn correct boxes remain authoritative regardless of this creation preference. Convert the current SP40's two owned wire trims to solids in a named undoable operation with independent before/after snapshots.

### Circular plan profiles (0.6.0)
Support closed vertical prisms whose plan boundary contains straight axis-aligned segments and circular arcs. Recover circular runs from measured CAD/native vertices, validate radial error, and construct SketchUp ArcCurve via add_arc (positive sweep with reversed normal for clockwise runs, as referenced in MH_panel). Keep profile center/radius/signed sweep and segment counts in source metadata, manual correction state and exact plan learning. Do not flatten a rounded accepted result into its bounding box. Reject open, noncircular, holed or nonprismatic manual inputs with actionable errors. Keep arbitrary local axes supported through transformed physical coordinates. Plan-only height remains provisional 1600.
For SP41 include the entire connected curved end in plan evidence and bounds (2860×350, previously 2758×350). Recover a filled outer curved end proxy from a closed exterior side outline, avoiding duplicate interior panel strips. Manual source validation uses the complete measured source plan envelope, preserving wrong-source protection. Upgrade the active SP41 correction metadata without accepting the user's result or replacing/hiding their external geometry.

### Learned source origin and Group output (0.6.1)
SP42 direct-scan replay must place the accepted full layout at the complete imported CAD plan origin. Rectangular recognition may cover only the final 682 mm bay, while accepted plan layout covers 2860 mm; never place that full layout at the partial recognized envelope's origin (2178 mm error). Store an explicit source_plan_envelope origin basis for accepted/replayed layouts; build source_box and source placement consistently from that basis plus bounded learned offset. Preserve correct legacy examples by interpreting accepted normalized layouts against their complete source envelope. Preserve original imported CAD and independent history. Use native Group rather than ComponentInstance for generated modules/auxiliary solids. User confirmed each generated module is a separate root-level Group with no outer product Group/Component. Store product membership/frame in model metadata, preserve legacy containers for existing products, and keep selection, corrections, templates and snapshots working. Snapshot files may organize a whole assembly for independent history, but live geometry must remain unwrapped.

### Automatic plan-rule induction (0.7.0)
After explicit Kết quả đúng, acknowledge/save immediately and automatically run a windowless background worker to refresh derived plan rules. Refresh also occurs before plan replay/build, reusing a content-verified catalog when unchanged. No AI or self-modifying runtime code. Learn only measured scalar anchors/constant bounded offsets and circular profiles from accepted manual plan examples. Group conditions by input construction topology, fixed stock evidence and circle topology; output grouping/plane relationships are inferred from accepted layouts. Require at least three distinct geometry signatures with matching output structure, leave-one-signature-out validation with zero failures, and target-side remeasurement/ambiguity guards. Exact geometry replay has priority. Changed topology/bay counts are outside this rule family, never resized arbitrarily.
Retain immutable accepted/source history; new feedback/exclusions invalidate and revalidate derived rules automatically. Show active/waiting/blocked counts, source example count and reasons in the manager, and distinguish plan_exact from plan_rule output provenance. Reconstruct source-coordinate placement, Groups and native ArcCurves consistently. Never auto-accept or change existing live user geometry during training.

### Product work log (0.7.1)
Replace separate error/history feeds with one expandable row per scan/build identity. Unnamed scans read “Vừa quét SP không có mã”; distinct scans remain separate. Expansion shows all associated scan/build/error/correction history and measured construction data, including records beyond the old 30-item limit. Place Select before Sai/Kết quả đúng and existing correction actions directly under the expanded row. Select restores all surviving owned output parts, never CAD or external manual inputs. Row actions must resolve that row’s product, reject another correction session, preserve external box selection during acceptance, and handle removed/ambiguous outputs safely. Preserve eight-second acceptance recovery and immutable history; legacy records are read without rewriting them.
