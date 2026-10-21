# Plan

Reuse Program.symbolic_positions and AffinePosition for exact six-cell expressions.
Serialize text, origin and variable keys as display-only sheet data. Validate an
affine expression against current scene values/bounds; prioritize explicit manual
thickness or identify an override rather than retaining false ATT provenance.
Keep original formulas as separate evidence. Numeric rules/transactions unchanged.

UI: a safe text span for the expression and a smaller mm result, one part-cell
button opening the existing inspector. Scalar cells retain one numeric line.
Preserve column widths, collapse and shared scroll. Tests and native draft-safe
reload use the existing project workflow; all constitution gates remain intact.
