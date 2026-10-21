# Duplicate parts and readonly derived envelope dimensions

User adds two live Untitled cases while feature 038 is being finished:
`Hộp Treo -2 Dọc.skp` (PID 1266556) and `Nóc 2 Thân.skp` (PID 1266716),
both in `D:/Cong viec/Sketchup/DC/Dat` in existing SketchUp PID 9504/VBO7891.

Reading duplicate labels must create deterministic occurrence keys without
renaming/modifying source entities. Persisted keys still reject actual collisions.
Native and SDK readers share the same derived-key policy. Trial copies must keep
bindings stable and save unique keys on owned entities.

For Nóc 2 Thân, the explicit root LenZ access is VIEW. All five panel thicknesses
use a1DDTam; Nóc Z also equals a1DDTam, giving total height 2*T. X/Y stay fixed.
Permit an axis to follow exact formula-union bounds only when its source access
is VIEW and complete transitive AST analysis proves that axis's geometry/hidden
outputs do not depend on that same root dimension. Missing/unsupported dependency
analysis cannot establish the proof. Other axes and legacy programs remain fixed.
Own overrides cannot grow beyond the predicted ATT envelope; collision/size and
topology guards remain. Preserve derived-envelope policy in rules and all plans,
including Scale, Parametric manual cells, native verification, saving and reimport.

Masked stale own-hidden flags (seen in Hộp Treo helper geometry) are normalized
only on owned copies, without changing effective captured visibility or source.
Compute pending node updates against actual current metadata before activation.

Additional findings in Hộp Treo: STRING attributes explicitly authored in length
formula units are physical dimensions even outside LIST controls. Its partial
orthogonal shell and separately controlled child surfaces need independent mesh
transforms, with native glue removed only on private owned copies. Reader records
verified orthogonal surface capability; flat axes must never be extruded or
collapsed. Unverified non-box solids keep rigid motion only.

New native reads capture formula_frame_version=2. Explicit formula dimensions and
positions use captured authoring-frame multipliers rather than applying every
resized ancestor again; implicit dimensions still follow parent scale. The numeric,
symbolic and editable-cell consumers must agree. Legacy saved programs retain
their prior semantics. Repeated Scale is an acceptance check, not just first edit.

Verification exposed a HUD viewport mismatch: API reported 1532x899 at scale 1,
while native viewport pixels were 3830x2248. Native helpers must measure the
proportional factor and use it consistently for regions and mouse coordinates.
Use versioned DLL names for live reload, retaining window-scoped input filtering.

Acceptance: inspect source ATT and compare with independently calculated expected
geometry; attempt native DC redraw only on a private copy of restricted builtins.
If external DC UI callbacks block this check, report it rather than claim a pass.
Test thickness values 17/18.6/20/25, repeated edits/Scale/Undo; fixed 400x350
for Nóc, height 2*T; unique Hộp keys/independent copies. Original roots/files stay
unchanged. Finish 038 report refresh, native checks, package and VBO reload too.
