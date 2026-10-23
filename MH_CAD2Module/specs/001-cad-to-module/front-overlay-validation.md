# Front overlay and horizontal band verification,0.23.1

Implemented2026-10-21 using the existing Spec Kit feature, repository Karpathy guidelines and scoped release checks. Latest actualSP25 job9eb649ce-84b6-3d26-6267-13040297de57 already linked the closed/open fronts logically, but cad_display deliberately moved the open front500 mm to the right. The user explicitly selected overlaying both fronts onXOZ, superseding that older display rule.

front_bands sweeps closed standard-stock vertical spans and selects up to three distributed horizontal heights from regions with the most shared stations. It uses cached indexed W signatures and independent same-height consensus. It does not hard-code product codes/heights or compare every line against every parallel line. ActualSP25 verifies at976.4/1151/1325.6 mm within the user-identified860–1460 mm region; all three support the same8103.634 mm open-to-closed source translation. Cropped source geometry is retained. Family recognition/front registration share this check; Ruby independently verifies consensus, slice heights and actual panel crossings.

New front_overlay display mode keeps all fronts at logicalXOZ transforms with separateGroups/tags; extraXZ copies start500 mm beyond the rightmost front and retain theirYOZ originals. Archived layouts still validate. PlanReference fingerprints generated native edges; undoable restore also repositions unchanged references when proof/source/old transforms agree. Legacy Groups use temporary source checks inside the operation; temporary geometry is removed. Edited, manually positioned or locked Groups are preserved. Unchanged retries do not repeat relayout or rewrite data unnecessarily. Before-reference/transform records remain in immutable history.

Removed implicit Manager opens from report_error and build completion for provisional boxes. Messages/errors remain in existing state/history; explicit Manager actions still work. Native controller tests exercise provisional results, missing products, native build errors and worker failure: zero automatic Manager opens, no real model/dialog writes.

## Verification

- Required gates:383 pytest passed,47 dependency warnings,89.88s;74 Ruby tests/281 assertions;24 runtime Ruby files scoped RuboCop/rubocop-sketchup clean. Final Ruby/lint rerun passed after the edited-placement retry optimization.
- Four new Python cases cover actual croppedSP25, different-height alias rejection, same-height repeated ambiguity and unrelated gap chains. Ruby cases reject invalid slice heights and forbidden front display offsets while retaining archived layouts.
- CAD manager, general manager and compact entry browser suites passed with overlay messaging, tags, actions andEnter behaviour.
- Actual nativeSP25:11 rootGroups,3 YOZ cuts plus3 XZ copies; fronts overlaid with separateMH_DWG1/MH_DWG tags, three verified heights, extra-copy500 mm spacing;1.146s. No model-state/file changes after aborted QA.
- Native migration test: legacy front repositioned; IDs/module boxes/closed front unchanged; legacy source scratch removed; repeat idempotent. Additional drawn edges and manual transforms block relayout. User state preserved after aborted QA.
- NativeSP24:23 Groups, six measured levels and cut/direction/full-B-C regressions passed;5.771s. Retained-box restoration10→11/source-owner/edit/idempotency checks passed;2.294s. Low/direct scan source/arc tests passed, including zero duplicated direct-scan CAD. Single700→displayZ0 and SP20Z0/Z1000/trueYOZ arc checks passed.

## Live correction and delivery

Guarded actual repair targeted ownerassembly-6848aaec-ec50-ac98-7b02-4b7f480b056a in E:/MAC/OneDrive/Desktop/1.skp, exact job and11 source IDs. Only open front621741 and XZ inspection copies622331/622486/622605 moved. All source identities, module boxes, other entities, selection, camera and disk-file hash were checked unchanged. Backupoutputs/sp25-overlay-before-20261021-010912.json and normal restore history retain the old reference/transforms. Operation is undoable; no model save. Repair script is specific to that captured state and must not be rerun blindly.

Runtime0.23.1 safely loaded and idle worker stopped; recognizer34 invalidates derived analyses while preserving original sources/index/history. Final live check finds11 sourceGroups, front overlay, all three height proofs and Manager still closed. Future retained-box builds can apply the same guarded relayout; manually edited CAD remains protected.

Packageoutputs/MH_CAD2Module-0.23.1.rbz:74 byte-verified entries; SHA25685feff3ec5cca228346085073b360617eedb2b4f1e8ef82f489ede93eaf92242. Receipts: outputs/front-overlay-package-result.json, front-overlay-live-load-result.json, front-overlay-migration-native-result.json, no-auto-manager-native-result.json, sp25-overlay-live-repair-result.json and actual-source native receipts.

Limits: height checks require enough overlapping stock stations. Ambiguous/insufficient association and module heights remain explicit pending states; overlay does not deform source CAD or imply that all module partitions/heights are solved. Existing rescued Settings JSON/eval tracepoint noise is unchanged; deliberate QA failures are isolated from real history. No commit, branch, delegation, originalDWG edit, AutoCAD launch or accepted-library deletion.
