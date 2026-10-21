# Validation

Profiled the same private MH_stretch fixtures in the existing SketchUp 2025
process 22980 / 2.skp before and after this change. Wrapper timers measure
method work separately from the native test's 450 ms polling timer/debounce.
Reported time includes profiler overhead and varies with machine load.

| Method work | Before | After |
| --- | ---: | ---: |
| Paired host/door Scale repair (`ScaleModelObserver.perform`) | 1,869 ms | 534 ms |
| Host width Stretch repair (`ScaleModelObserver.perform`) | 514 ms | 214 ms |
| Door T edit (`Assembly.transact`) | 670 ms | 290 ms |

Paired Scale plans: 5 -> 3; ATT Program constructions: 154 -> 18. Custom variable
evaluation of the 43-variable host uses one Program instead of eight and measured
about 6 ms instead of 35 ms in a separate direct invocation.

All 13 native checks pass, including exactly one atomic Studio repair at 600 mm,
no intermediate committed depth, exact T, repeated Stretch, subsequent T edit
and linked door response. Original geometry, selection and preferences are
retained. This measures the fixture methods, not end-to-end browser input lag
or every possible module/extension combination.

Final scoped gate: 248 Ruby files clean in RuboCop; 451 tests and 4,813 assertions,
0 failures/errors/skips. The verified runtime was reloaded in the existing
SketchUp process without changing the original model, selection or preferences.

Portable regression checks cover custom evaluator isolation after changed
inputs, per-repair calculation scope lifetime, independent returned plans,
rule/geometry/value cache misses and malformed serialized input validation.
