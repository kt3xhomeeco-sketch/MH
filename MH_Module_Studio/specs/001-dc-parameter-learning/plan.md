# Implementation plan: DC parameter learning

Date: 2026-10-14. No branch changes. Scope: this extension only.

Add portable Core helpers to map labeled DC thickness inputs to physical panel
thicknesses. Infer a unit factor only from a unique match across the observations.
Group samples by all other editable DC input values and fit the existing single
parameter solver on a group with two or more distinct target values. Preserve
source snapshots; attach provenance and fixed controls to the resulting rule.

Panel supplies choices and selected input to the local UI. The last independently
changed thickness input is proposed automatically; selection remains explicit.
Show all recognized thickness values, fixed controls and used/excluded states.
Keep optional rule fields backward compatible. Validate available live DC context
before planning; keep original geometry, envelope, overlap and trial guards.

Constitution check: portable core, no DC formula evaluation, no source mutation,
preserved envelope, independent importer and honest validation limits all retained.

Validation: captured three-state regression fixture, unknown/ambiguous units,
controlled grouping, fixed setback guard, existing portable tests, UI smoke,
read-only learning and preview on SketchUp PID 8120 / VBO port 58233. Do not
change the other open SketchUp instance. Native clone/Undo remains a separate check.
