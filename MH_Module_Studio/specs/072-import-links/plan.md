# Plan

- ImportTemplate owns portable validation, geometric slot matching, partial fit,
  and master-to-member thickness variable edits. Existing ATT remains the only
  internal module evaluator.
- ImportLinks owns native host face capture, placement, host-only filled preview,
  persistent contact creation, and reversible door reservation state in contacts.
- AssemblyParameters owns native master member identity/synchronization. Integrate
  at the existing Assembly transaction boundary, after explicit parameter updates
  and before contact/envelope solve. Preserve independent shared definitions.
- Parametric configures and saves the template in the existing own rule/payload.
  HUD delegates template previews to ImportLinks and legacy imports unchanged.
