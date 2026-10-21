# Physical thickness beyond a parent edge

User reports selected owned Nẹp Bù Phải 50 (native PID 495697) rejects T=80.
This is the exact existing NẸP BÙ TRÁI library payload, with an instance name.
Feature 047 tested T only below 50, missing the perpendicular thickness passing
the other fixed-width panel. Reproduce against the selected object's saved rules.

Keep the front width 50, backing span 50 and physical T exact. Outer bounds are
max(50,T) by T+50 by current height. Increasing then decreasing T must restore
these bounds without making the next redraw consume previous overflow as input.

Retain construction inputs separately from measured union bounds. Permit an
unexposed, undeclared parent axis to overflow only where every protruding part is
an existing thickness driver on that axis. Unrelated groove/position/own edits,
exposed lengths and explicit declared outputs retain their validation. Native
Scale establishes a new requested construction frame; impossible Scale remains
an atomic error. Geometry damage and collisions remain rejected.

The per-instance construction frame must survive copies, SKP save/overwrite,
Library import and assembly members. Parametric's Module.Len references use that
same frame. No source ATT formula or fixed 50 mm span is rewritten.

Acceptance: actual selected module's private copy through T20/80/200/18.6/80/20;
save at T80, import, edit, overwrite, native Scale and edit again. Preserve source
objects and files during QA. Run existing groove/formula/assembly/Copy tests and
the scoped RuboCop/package gates.
