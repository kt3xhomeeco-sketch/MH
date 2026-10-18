# Isolate calculations from host adapters and UI

Preserve existing formula, constraint, parametric, Scale, import, library and
HUD behavior while giving each calculation a clear owner. No new DC coverage,
UI changes or source-library conversion in this refactor.

The portable core must load in a fresh Ruby process without SketchUp, Geom, UI,
ABF, DCFunctionsV1 or RubyVM introspection. Its entry point must not transitively
load model/file-process/UI adapters. Move formula source capture into a host
adapter; move matrix arithmetic and Scale planning into pure modules.

Keep numeric evaluation, symbolic positions and sheet conversion in separate
classes; feature files must not reopen the numeric Program class to add their
own behavior. Retain saved rule schemas and the existing public calculation
entry points. Extract UI's rule-building policy into a pure calculation service.

Prevent accidental shared mutable input between callers; calculation/preview
must not rewrite saved rules or snapshots. Document intentional shared math and
enforce dependency boundaries with isolated-process regression tests.

Acceptance: existing 164 tests pass, differential fixture outputs and complete
library compiler outcomes remain unchanged, native existing exports remain
editable, repeated Scale/Undo/reload paths retain their prior behavior, explicit
package manifest includes all runtime dependencies and excludes tooling.
