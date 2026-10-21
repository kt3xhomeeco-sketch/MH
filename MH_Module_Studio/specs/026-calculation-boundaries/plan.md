1. Record pre-refactor numerical/compiler behavior and preserve source copies.
2. Establish a one-way domain bootstrap; extract math, frame, capture and Scale
   modules. Separate symbolic and parametric program classes from numeric Program.
3. Extract sheet presentation and rule-building policy; leave host controllers
   as callers. Keep compatibility facades where external callers already exist.
4. Add dependency, mutation-isolation and cross-feature regression tests; compare
   baselines and run scoped RuboCop/all tests.
5. Verify native geometry/repeated edits/Scale/reload using an owned session,
   check the package and document module ownership and remaining limitations.
