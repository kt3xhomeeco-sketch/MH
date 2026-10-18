# Implementation plan

1. Reproduce the boundary lock using the actual captured DC fixture.
2. Let ATT drive its unoverridden parts; enforce the aggregate envelope through
   existing final geometry validation. Keep exterior anchors for own constraints.
3. Create the parent directly as a component definition/instance, with group leaves.
4. Validate portable regressions and temporary native modules. Back up and repair
   the reported owned module in one Undo transaction using verified ATT geometry.
5. Reload through VBO, run the scoped quality gate and rebuild the RBZ.
