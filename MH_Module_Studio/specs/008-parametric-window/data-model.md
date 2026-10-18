# Data model

Optional RuleSystem.parametric_variables: array of objects with id, binding
(existing ATT/geometry key or null), name, symbol, category, unit, value, formula,
exported. IDs and case-insensitive symbols are unique. Binding keys never change
when aliases change. All original bindings remain; custom variables can be
removed only after their references are removed. Numeric evaluation detects
cycles/missing references and checks target ranges; text/behavior remain data.

This array is stored in project rule JSON and trial rule_json. Exported native
parameters retain stable keys plus own name/symbol/category/formula; exported
custom variables carry variable_id and data status in exposed_parameters_json.
Unexported variables remain available internally to formulas.

Published parametric_sheet contains rule_id, categories, variables (plus computed
value/editability/source), parts (key/name/path, six measured values and scoped
ATT evidence), and all scoped attributes. Revision and latest snapshot ID protect
against stale edits, including separate instances of the same template.
