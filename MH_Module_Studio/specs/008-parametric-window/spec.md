# Separate Parametric window

User request: open Parametric in its own window; variables above, part dimensions
and XYZ below. Variables have names, symbols, ATT-like categories and add/remove.

## Acceptance
- Opening Parametric leaves the 3D viewport unobstructed. Closing/reopening the
  separate window reconnects callbacks and retains committed module data.
- Upper grid: untitled export tick, name, symbol, category, value/unit, formula,
  provenance/status and remove. Add custom variables; reject duplicate/reserved
  symbols, cycles, missing references and removal of referenced variables.
- Root ATT inputs retain stable binding keys even when their display symbols
  change. Own numeric formulas may reference custom variables and drive existing
  editable inputs, using the safe interpreter; no imported Ruby/JS executes.
- Supported categories cover ATT dimension, position, rotation, Copies/Copy,
  Hidden, material, information, behavior, custom number/text/boolean. Categories
  do not imply unsupported topology/rotation/material/onClick execution.
- Lower grid: one row per part, Dài/LenX, Rộng/LenY, Cao/LenZ, X,Y,Z in mm in the
  module frame; values follow source/preview, formula evidence is inspectable.
  Existing rules remain the geometry authority; measured envelope is preserved.
- Save/open own projects and trial rule_json preserve variable definitions.
  Imported variables needed by existing rules cannot be removed silently.
- Reject stale window edits from another module. Both windows receive action
  results/errors and recover from cancellation without becoming blocked.

## Verification
Portable regression tests for variables/formulas/persistence/geometry; standalone
Electron grid/action/layout/injection checks; existing UI/viewer checks; scoped
RuboCop. Native dialog lifecycle/trial checks only if the intended VBO is live.
