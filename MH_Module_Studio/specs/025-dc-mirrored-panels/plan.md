1. Audit non-curved source transformations and nested drawer barriers.
2. Extend signed diagonal frame evaluation, affine positions and cell formulas.
3. Add regression scenarios; run scoped RuboCop and all tests.
4. Retry failed non-curved conversions in an owned SketchUp process, validate
   new exports with real edits/reverse/idempotence, preserve prior report rows.
5. Record results/remaining barriers, package verified runtime.

Reference: SketchUp's Constraining Attributes of a Dynamic Component explains
that constrained child sizes/positions retain their specified dimensions after
parent scaling: https://help.sketchup.com/en/sketchup/constraining-attributes-dynamic-component
Native matrix signs and source bounds, rather than names, determine reflection.
