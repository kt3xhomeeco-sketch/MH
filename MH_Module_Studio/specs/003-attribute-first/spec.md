# Attribute-first module rules

Requested behavior: DC ATT formulas are the primary source of dependencies.
Sample comparison is a fallback, not a prerequisite for readable DCs.

Acceptance:
- Capture root, intermediate and leaf ATT, preserving instance overrides.
- A single supported cabinet DC yields thickness and setback rules.
- Resolve local, parent and unique named references; arithmetic, comparisons,
  IF, AND, OR, NOT, MIN, MAX and ABS without imported-code execution.
- Recalculate expressions for requested values, including nonlinear branches;
  do not use numerical probe slopes for geometry changes.
- Preserve current envelope, validate geometry and retain source isolation.
- Show ATT vs comparison provenance and fallback diagnostics.
- Persist the formula program and editable settings on independent trial copies.

Initial boundary: aligned nested frames with positive scale and a root frame of scale 1. Geometry formulas
requiring rotation/mirroring, nested geometry formulas below scaled ancestors, nonzero local geometry origins, opaque functions,
ambiguous names, unsupported syntax, copies/visibility changes or mismatched
cached geometry fall back to observations or report no rule. Appearance/text
expressions are outside this geometry compiler. Unused formulas are retained but
do not count as translated rules. No ABF decryption or arbitrary evaluation.
