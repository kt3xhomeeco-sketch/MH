# Scalar ATT formula reference units

The selected `3.CC Chân bệ.skp` fails geometry verification because FLOAT/STRING
spacing formulas consume length references as millimeters instead of the declared
authoring unit. Native DC parse probes on independent scratch geometry establish
that `LenX/4` for 700 mm returns 17.5 under CENTIMETERS and 6.8897637795 under
INCHES. Scalar results remain scalar; numeric literals and COPY counts do not
receive length conversion. Explicit length formula units retain their behavior.

Use declared `_lengthunits` for scalar FLOAT/STRING reference evaluation, shared
by numeric, symbolic and editable-cell owners through Program.formula_unit.
Preserve the existing fallback when authoring units are absent. Do not infer units
from labels or cached formula error strings. Regress native plinth geometry and
edits, run full portable/native checks, convert and reimport actual SKP, retain
source fingerprints, update the full report, package/reload the existing session.
