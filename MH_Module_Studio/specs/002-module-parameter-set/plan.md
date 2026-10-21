# Plan: module parameter set

Ruby 3.2 / SketchUp 2025, portable Core plus existing Ruby/HTML adapters.
Add a versioned aggregate rule kind containing the existing validated scalar
rules, captured parameter rows and a common fixed context. Validate its predicted
geometry against captured combinations. Sum per-boundary contributions using
current geometry and run shared envelope/overlap guards on the final plan.

Runtime uses the aggregate in the existing preview/copy/update transaction and
stamps all parameter values. Panel analyzes all DC thickness inputs together;
detail selection becomes a display filter. The trial UI sends a map of targets,
with unlearned fields read-only. Legacy scalar projects remain supported.

Constitution: portable math, own format, independent trials, preserved envelope,
no DC evaluation, no other plugin changes. Validation includes portable combined
geometry and JSON regressions, UI controls, native read-only preview on the
identified sample model, and explicit limits for native mutation/Undo.
