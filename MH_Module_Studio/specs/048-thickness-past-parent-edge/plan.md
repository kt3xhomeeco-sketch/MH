# Plan

- EnvelopePolicy owns construction input bounds and verified thickness-driver
  overflow. Numeric ATT remains the source of every resulting part bound.
- AttributeRules / DCCopies carry formula_envelope through plans; RuleSystem and
  Parametric use that frame consistently. Native Scale resets it to its request.
- Reader reads a normalized component-local frame. Runtime stores it only after
  native geometry verification, inside the caller's transaction. SKP adapters
  restore it before formula checks and preserve it while baking outer Scale.
- Assembly parameter output tracking includes those axes. Unrelated groove
  overflow and damaged geometry remain regression checks.
- Extend the filler fixture beyond the 50 mm threshold and execute native checks
  on a private copy of the exact reported PID, rather than a similar source.
