# Verified result — 2026-10-16

Environment: existing Untitled, SketchUp 2025 PID 9504 / VBO 7891.
No SketchUp process was started. The other open project was not inspected or edited.

## Two selected source cases

Hộp Treo -2 Dọc (1266556) now reads/compiles with distinct repeated-name keys,
physical intermediate STRING lengths and verified orthogonal surface geometry.
The app changes 17/18.6/20/25 mm board thickness while retaining 800x450x500.
Native shell mesh edits do not move glued descendant parts a second time.

Nóc 2 Thân (1266716) has root LenZ access VIEW and no root-Z geometry dependency.
The accepted policy contains Z only. Width/depth stay 400x350; height follows 2*T:
34/37.2/40/50 mm. A forged X exception and a manual cell exceeding predicted Z
are rejected by portable tests. Scale Z twice retains board thickness, and
subsequent edits remain valid.

- `outputs/cabinet-039/native.json`: 24 actual checks, passed; roots/files retained.
- `outputs/cabinet-039/derived-scale.json`: 3 actual derived-Z checks, passed.
- `outputs/conditional-038/native.json`: 17 visibility/conditional native checks.
- `outputs/conditional-038/async-native.json`: 6 queued Scale/Undo/Redo checks.
- `outputs/conditional-038/regression-native.json`: 102 assembly/options/import/HUD checks.
- `outputs/cabinet-039/final-reload.json`: both real Library entries prepare after reload;
  frame version 2, derived axes [] / [2], source roots/definitions/selection retained.

Native DC redraw comparison was blocked by an external DC Component Options
dcbridge.js callback error. It is not counted as passing. Expected geometry was
checked from captured source ATT, independent size assertions and actual owned
model geometry. Source objects/files were never edited; temporary QA copies were
removed.

## Library

038 refresh: 27 own files upgraded and reimport/edit verified. Full 227-source
report was retained through the subset refresh.

039 rerun: 131 previously failed MH sources, 14 new successful exports with native
reimport and a parameter edit each; 98 remain failed and 19 curved sources skipped.
Source report now records 110/227 converted, 117 remaining. All 227 source SHA-256
values match. Customized older exports were preserved. The full report is at
`D:/Cong viec/Sketchup/DC/Modul_studio/.conversion/report.json` (CSV/MD alongside).

Hộp Treo and Nóc 2 Thân were published as two additional sources from DC/Dat,
with separate `dat-039.json` audit; they do not change the denominator 227.

## Verification and package

`bundle exec ruby tools/check.rb`: 113 files, no RuboCop offenses; 240 runs,
2640 assertions, zero failures/errors/skips. Covers immutable source inputs,
duplicate identities, readonly proof, manual override limits, repeated Scale,
matching numeric/symbolic/editable-cell authored frames and direct-mesh transforms.

`python tools/package.py`: manifest-based RBZ integrity passed. Versioned v2 input
DLLs are included; tests, developer tools, source DCs and captures are excluded.
Actual HUD verification passed after matching viewport factor 2.5 instead of the
API's reported factor 1. Both input coordinate consumers use the measured factor.

Limits remain explicit: no new Copies generation or rotation changes, no curved
panel regeneration / DADX, and no full Piecewise Affine branch algebra. Exact
supported numeric conditional ATT and editable conditional expressions remain
available. Unsafe hidden-part activation still fails size/collision checks;
recognizing a parameter does not certify every possible value.
