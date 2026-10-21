# Rename Parametric symbols and dependent formulas

The user confirmed the Ký hiệu column. Saving a symbol rename must update
generated detail expressions, stored manual detail formulas and formulas of
dependent variables. Keep variable identity/binding, numerical results and source
ATT intact. Names with similar prefixes, functions, numbers and local/module
dimension fields must not be changed accidentally. Apply multiple renames in a
single pass, case-insensitively, using variable IDs rather than row order.

Invalid/duplicate symbols or invalid dependent expressions reject the edit
without altering the original saved rule. Preserve save/load, preview, repeated
native edits and existing frozen-input/dependency boundaries.
