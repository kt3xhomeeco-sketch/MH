# Data model
`module_rule_system` v1 contains parts, parameters, exposed keys, constraints, warnings, envelope and optional `formula_engine` (legacy validated own ATT/sample rules).
Constraints carry stable ID, type, enabled/drive flags, provenance and semantic face references `{part, axis, side}`. Supported operations: thickness, fix, contact, offset, align, between, center, formula.
Trials store own rule JSON and parameter values using existing instance identity, separate from template IDs.
