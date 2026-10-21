# 028 — Module assembly constraints and direct viewport editing

## User intent
Link faces belonging to different modules. Include contact/signed offset, centering,
fit between faces, angle/perpendicular, measured-clearance references and repetition
left/right/up/down. Edit gap, angle, count and repeat direction directly on a native
viewport HUD. Drag a normal-axis handle to adjust offset without a separate dialog.

## Acceptance
- Pick actual panel faces inside top-level groups/components; retain stable panel
  anchors through owned parameter redraws. Preserve the reference module.
- Contact/center fit uses current geometry, including changed panel thickness.
- Repeat count includes source; fixed clear gap or equal gaps inside two boundaries;
  equal mode can include both ends. Direction is the source module's local axis.
- HUD exposes values, +/- controls, VCB typing, direction/mode controls, saved rule
  selection/removal and normal drag preview. Mouse release commits one Undo step;
  Escape cancels a pending gesture. Invalid/conflicting/cyclic rules roll back.
- Saved model rules survive reopen; deferred model observers re-evaluate after
  parameter edits/Move/Scale. Pure calculations never load SketchUp.
- Run scoped RuboCop/tests, package and native isolated fixture scenarios. Keep
  user model unchanged during verification and reload the runtime via VBO.

## Boundaries
Existing ATT/Scale solvers remain responsible for owned module internals. Fit
explicitly authorizes a new envelope and invokes Scale reconstruction. Native DC
must be converted before fit. Non-box panel faces are rejected explicitly. This
version uses top-level modules and planar box-panel anchors; explode recovery and
arbitrary curved-surface mating are outside scope.
