# Plan

Use the existing portable Ruby core and native SketchUp/bridge reader. Retain a
bounded hierarchy graph. Add a recursive-descent parser with a fixed function
whitelist and a typed length boundary (stored inches, explicit formula units).
Use actual root dimensions after stretching. Validate formula baseline against
actual geometry, then calculate before/after formula geometry for requested
values. Numerical probes only identify candidate controls and UI motion hints.
Keep regression rules only for unsupported inputs. Save programs in the module
bundle and current values on trial roots. Never invoke the DC redraw engine.

Verify one-sample setback, nested parent chains, thickness interactions,
nonlinearity, units, stale root dimensions, code rejection, cycles, imported-rule
validation, metadata, UI and native read-only preview. Native Undo is outside
this feature's verification; do not claim it passed.
