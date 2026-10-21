# Verification — 2026-10-15

Spec Kit prerequisites resolved spec/plan/tasks for this feature. Scoped gate:
54 Ruby files inspected, no RuboCop offenses; 160 tests / 2,099 assertions, no
failures, errors or skips. New cases cover standard math arities/domains and
degree/radian semantics; implicit COPY=0, explicit copy offsets, topology guards;
scoped/ambiguous references; numerical STRING metadata; complete source-template
recognition and malformed/injected text rejection; loader interception before
evaluation, inherited-method restoration, exception/oversize cleanup and worker
thread refusal.

Read-only SDK compiler audit of all 227 captured source files, checked against
their current SHA-256: 48 -> 81 compile, no compiler regressions. SDK bounds do
not certify native geometry. Reports: outputs/dc-functions-024/coverage-before.json
and coverage-after.json. The after audit uses the verified per-file mapping data
from native-functions.json; it never executes captured source.

Native SketchUp 2025, VBO PID10304 / port7891, own test copy at
outputs/dc-functions-024/1.skp. The installed ABF loader was intercepted at its
abf_eval boundary and stopped before evaluation/registration using a unique
catch/throw tag. Complete nominal-parent readers were recognized as data; unused
unbound helper templates were recognized but never made callable. No licensing
or permission methods were replaced. Prior experiments used an intentional
capture exception; the final adapter uses control flow without reporting a
capture exception as an error. No imported function implementation was called.

Native function audit: all 227 source hashes unchanged, 2,291 distinct verified
reader mappings (including unused generated readers), no imported methods
registered, original abf_eval restored. Eight mappings shared by the upper
left/right corner cabinets were verified from the right cabinet's complete
templates and included as static fallbacks. Remaining referenced unknown:
DADX in four curved-panel files; no implementation was found in the installed
function class or readable extension sources. This function remains unsupported.

Full native conversion generated 65 candidates. Every candidate's editable
inputs were checked at +/-0.1 mm where within range: apply real geometry,
verify, repeat calculation for idempotence, reverse and verify again. All 65
passed. Previous 37 exports retained; 28 additional modules published into
D:/Cong viec/Sketchup/DC/Modul_studio. Sources, original test-model roots,
definitions and selection retained. The authoritative .conversion/report.json
has native_verification_status=complete, native_verified=65,
source_hashes_verified=true and user_model_retained=true.

162 source files remain unconverted, grouped by their primary diagnostic:

| Diagnostic | Files |
|---|---:|
| Rotation, mirroring or scale at module root | 47 |
| Formula under a scaled intermediate group | 27 |
| Loose root faces/edges | 25 |
| No internal edit compatible with fixed envelope | 23 |
| No measurable panel thickness | 19 |
| Formula vs current geometry mismatch | 11 |
| Degenerate group | 8 |
| Other formula/geometry checks | 2 |

Final native checks also exercised SDK file-read enrichment on the UI thread:
the LC100 sample's previously unknown references became verified aliases and
compiled into portable serialized rules. Two newly converted modules (LC100 and
KT co ban) each completed actual 17.6 -> 19.6 -> 16.6 -> 17.6 mm thickness cycles,
with unchanged outer bounds and stable repeat calculations. All six steps pass.
outputs/dc-functions-024/native-final.json has ok=true, model_retained=true,
eval_hook_restored=true and no_imported_functions_registered=true.

Conversion and function reports remain developer artifacts, not runtime assets.
The main Studio Ruby code was reloaded via VBO and Library refreshed to include
the 65 verified SKPs. Existing saved Studio samples/rules are not silently
recompiled; reread the source DC to import newly supported references.

Final SHA-256 checks confirmed all 37 prior exported SKPs are byte-for-byte
unchanged and all 65 current export hashes match their report entries. RBZ
packaging completed with the unchanged explicit 37-entry manifest (18 Ruby files
including the loader); CRC validation passed. Developer tools, captures, test
models, specs and reports remain excluded.

Follow-up DADX research: see research-dadx.md. Saved evaluations match signed
parent LenX at 104 references in four files, including 26 references where the
nominal attribute has the opposite sign. This is observational evidence rather
than a recovered implementation; production support/conversion counts unchanged.
