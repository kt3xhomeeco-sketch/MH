# Tasks and validation

- [x] Read all 227 SKP sources with SDK; SHA-256 before/after, no source changes.
- [x] Record baseline: 18 rule-compilable files, 59 structural reader failures.
- [x] Inspect loaded implementations without invoking the imported functions.
  Exactly 27 named functions match one complete instruction signature for reading
  a parent's nominal LenX/Y/Z with the observed cm/inch conversion. Store only
  references/signature, not executable code. Unknown implementations stay blocked.
- [x] Recognize newly loaded names by that same full signature, capture their
  reference mappings in Reader snapshots, and preserve them in portable rules.
- [x] Add observed standard numeric functions and validate arity/domains. Lazy IF
  and CHOOSE; shared evaluation in ATT, own variable and part formula contexts.
- [x] Retain captured hidden geometry while hidden; reject guard changes. Support
  nested child spans explicitly requesting the parent nominal span without
  applying parent scale twice. General scaled formulas remain conservative.
- [x] Derive visible affine rules through fixed conditional/guard branches and
  nominal references; do not simplify branches depending on editable inputs.
  Recompute old derived descriptions with position_rules_version 2.
- [x] Portable regression gate; native geometry/Undo/Redo; live model migration;
  documentation, coverage report and runtime packaging.

Gate: scoped RuboCop 36 files clean; 128 tests / 801 assertions pass. Includes
exact full-body recognition and refusal after an extra instruction, unknown
name rejection, dynamic alias capture without function execution, alias data
serialization without ABF, units, math/arity/domain cases, nested dimensions,
hidden guard handling, no source mutation, source-specific conditional groove
rejection, explicit editable formulas and version-1 description migration.

Coverage: outputs/library-016/analysis-before.json was recorded against pre-change
staged production sources before the quality gate refreshed the stage. Updated
analysis-after.json records 42 files compiling ATT rules (24 added, no regression).
59 files still fail the structural reader (duplicates, singleton/no measured
thickness, root loose geometry); others retain specific unsupported function,
rotation/scale/origin diagnostics. Compilation is not native geometry support.
Developer scan/analyze/report tools and per-file coverage.md record the limits.

Native SU2025 PID26424, VBO port60452: native-library-016.json reports eight active
ATT inputs on the cached original cabinet; created independent component/group
boxes, changed thickness/back/setback/toe height, groove 19→0→8, refused excessive
groove without corrupting metadata, actual Undo+Redo, cleaned owned definitions
and geometry, user's existing model unchanged by QA. In this particular DC,
groove equal to board thickness selects a branch shortening the sides and must
be rejected for changing the envelope; this is not the feature014 fixture.

upgraded-open-module-016.json: the one matching owned module450705 was verified
against the new ATT baseline and backed up to backup-before-att-upgrade-016.
Only its own rule/parameter metadata was replaced, not its geometry/placement.
Preserved root PID and rule ID, mapped original ATT row labels/symbols/visibility.
The Studio and separate options window use the upgraded rule; source DC folder
and original on-disk 1.skp were not saved/overwritten.

native-parametric-ui-016.json verifies the actual CEF window: 27 variable rows,
7 parts, 8 editable ATT fields, thickness input unlocked, no pending request or
unsaved draft, no sheet diagnostic. The back width cell shows
`Module.LenX - 2 * att_2 + 2 * att_8`. Original visible rows were restored by
matching the actual thickness driver part keys, not merely equal scalar values.
Three rows remain visible in the small options window, as before migration.

Limitations: only numeric length controls controlling supported geometry are
editable. Visibility/topology/copy/material editing is not implemented here.
New aliases require an already loaded, exactly recognized implementation; an
SDK-only read cannot recover a private function that has never been loaded or
verified. No protected metadata is decrypted and no ABF helper is executed.
Package stays 26 entries: 13 Ruby + 12 UI + README, with tooling/data excluded.

Function semantics reference: https://help.sketchup.com/en/sketchup/dynamic-component-supported-functions
