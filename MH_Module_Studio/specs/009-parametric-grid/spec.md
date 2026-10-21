# Approved continuous Parametric grid

User approved outputs/mockup-parametric-fusion-v1.png. Keep the separate window,
variable/part columns and existing actions; replace the two framed regions with
one continuous scrollable grid. Highlight group rows separate module variables,
part fields and existing collapsed ATT details, with accessible collapse/expand.
An icon plus adds a variable. Flat white/gray styling, compact rows and inline
cell editing follow the approved mockup. Source and formula behavior stay intact.

Acceptance: 9 variable columns (untitled export/delete), 7 part columns, independent
group collapse without losing edits, shared grid scrolling at 850px width, reachable
toolbar/actions, no duplicate root ATT rows in the variable list (original rows
remain in the existing scoped ATT detail). Focus links reopen collapsed variables.
Native reload preserves both committed state and any unsaved child draft.

Validation: existing standalone editor smoke coverage plus meaningful group/focus/
draft/overflow checks and visual review; scoped RuboCop/Ruby gate, runtime package,
native VBO UI check if current session is available. No geometry changes needed.
