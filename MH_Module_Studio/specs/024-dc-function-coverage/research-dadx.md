# DADX investigation — 2026-10-15

Result: in all 104 parent/child references captured from the four curved-panel
SKPs, the saved DADX evaluation equals the parent's signed `LenX`. The resulting
`DADX() - LenX` equals the child's actual local X translation. This is evidence
about the saved configurations, not the original function implementation.

Evidence: outputs/dadx-research/evidence.json and the reproducible read-only
outputs/dadx-research/analyze.py. Every source SHA-256 still matches the original
SDK inventory. The 104 references include repeated subassemblies/shared child
definitions; they are not 104 independent resize experiments.

The child `_x_error` attribute preserves an evaluated expression such as:

```text
-1.2075699484457212 + -1 * <span class=subformula-success>-0.10646038666606045</span>
```

The original formula is `dadx()-lenx`. In this case the saved formula units are
centimeters; the parent's stored LenX is -0.47542123954556 inches. Multiplication
by 2.54 gives exactly the first number in the expression. Subtracting the child's
signed LenX produces the actual local X origin. Across all references the maximum
parent-LenX discrepancy is approximately 1.1e-14 mm and the maximum translation
discrepancy is approximately 1.8e-15 mm (floating point rounding only).

Crucial distinction: in 26 references, `_lenx_nominal` has the opposite sign from
the parent's `lenx`. DADX follows signed `lenx` in these references. It must not
be blindly mapped to the existing nominal-parent alias or positive bounding-box
width. The difference can reach 24.15 mm in these saved configurations.

The four source files are:
- 2.TC. Tấm Cong 1 đầu 1 tam .skp
- 2.TC. Tấm Cong 2 đầu 1 tam .skp
- 2.TC. Tấm Cong 2 đầu 2 tam .skp
- TC Tấm Cong .skp

Public documentation search did not locate a SketchUp-specific DADX definition.
The official supported-functions list does not include it:
https://help.sketchup.com/en/sketchup/dynamic-component-supported-functions

Read-only VBO inspection of current SketchUp 2025 PID21612 found no DADX/DADY/DADZ
definitions among the named loaded modules/classes, including private/protected
methods. DCFunctionsV1 has only the ordinary BasicObject/Kernel missing-method
handlers. Readable extension sources also contained no implementation.
outputs/dadx-research/runtime.json records the inspection. No opaque function,
redraw or imported Ruby was executed; no production code/model/source SKP changed.

Practical interpretation: the formula positions the child at the parent's signed
X endpoint by subtracting the child's own signed X span. Before a general import
mapping is accepted, obtain the original function body or validate controlled
dimension/scale/mirror changes on independent copies. Four files also contain
rotated/mirrored geometry outside the current evaluator's supported frame model;
recognizing DADX alone would not certify their conversion.
