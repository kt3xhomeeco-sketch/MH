# Plan

Use a second retained UI::HtmlDialog in Panel, synchronized through the same
request and publish adapter. A new standalone HTML/JS/CSS page avoids a popup
inside Chromium and shares no mutable browser globals with the 3D UI.

Store optional parametric_variables on the own RuleSystem bundle, separate from
the existing validated ATT engine parameters. Validate every load and edit.
Stable IDs/bindings distinguish imported inputs from custom variables. A small
safe scalar evaluator reuses DCFormulas::Parser and arithmetic, with dependency
cycle checks; it supplies existing editable targets rather than replacing the
geometry solver. Text/behavior are retained as data. No source DC modifications.

Root input formulas are own overrides; original translated formulas and scoped
attribute dictionaries remain intact. Size/position table uses actual module
frame bounds and original scoped ATT formula evidence. No inference from names.

Constitution gates: current envelope, ATT-first, safe parsing, independent trial,
project scope, runtime-only packaging and distinct native verification all hold.
Increase explicit package manifest for three new UI assets; no new Ruby file.
