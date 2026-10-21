# Follow-up: repeated Scale with inactive geometry

User report: first Scale succeeds, second Scale reports an envelope change.
Read-only native capture: outputs/scale-failure-020-26424.json, owned Khung module,
8 parts including hidden Len Chân Trước and Xà đỡ Sau. Root scale was already
approximately X=1.8648, Y=1, Z=1.6482. Shrinking any axis by 0.5 reproduced the
reported envelope rejection against the captured data.

Cause: safe ATT evaluation deliberately froze hidden geometry at captured sample
bounds. Absolute Scale reconstruction restored those old bounds into the newly
scaled model; a hidden part could then extend beyond a shrunken visible cabinet.
The original native Scale tests mostly expanded a fixture without hidden parts,
so they did not cover this case.

Fix: accept current frozen parts in ATT evaluation. Scale reconstruction and
ordinary parameter deltas keep inactive geometry exactly as it currently exists.
Default source-learning evaluation still uses the source capture. Hidden state
guards remain enforced. An unchanged hidden placeholder can remain smaller than
0.1mm after Scale; moving geometry still receives normal size checks. Keep all
geometry in envelope computation and retain the strict 0.001mm envelope guard.
No global tolerance changes or skipped active panel checks.

Regression uses the existing 8-part offset-origin fixture: expand X/Z, shrink
X/Y/Z separately, expand again and shrink together, assert inactive bounds are
not reset, saved parameters retained, evaluation idempotent, further parameter
edit succeeds. Native verification uses a private temporary copy of the actual
user module and restores selection/definitions; original modules are read-only.

Native result: outputs/native-hidden-scale-020.json has ok=true. Six consecutive
Scale transactions on a temporary shared-definition copy of actual root 810707:
X×1.1, X×0.5, Y×0.5, Z×0.5, XYZ×[1.8,1.7,1.6], XYZ×0.7. Every step preserves
the requested envelope, exact scaled inactive geometry and saved parameter values;
Core.plan is idempotent. Native Undo/Redo and a subsequent board-thickness edit
to 20mm also passed. Both original user modules retain their definitions,
transforms, part bounds, visibility, stored rules and values. Temporary geometry/
new unused definitions removed; selection restored. This test uses native API
transformation commits through the real observer, not a physical mouse drag.

Final gate: 48 scoped Ruby files clean under RuboCop; 146 tests / 1,741 assertions,
zero failures/errors/skips. Reloaded via VBO in PID26424 and PID12360; rebuilt
the 35-entry RBZ manifest with CRC validation. Observer last_error is nil after
the native regression. No geometry changes in the working-project PID12360.
