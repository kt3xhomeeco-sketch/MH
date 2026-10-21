# Editable part cells

User correction: preserve the ATT-style numeric cell and ƒ indicator. Double
click reveals an inline formula editor; Enter saves and recalculates, Esc cancels.
The six part fields are editable, including measured fields without formulas.
Keep variable rows and the continuous table unchanged.

Own module-frame formulas use mm, variable symbols/original bindings,
Module.LenX/LenY/LenZ (also Module!/Parent! references) and local LenX/LenY/LenZ,
X/Y/Z. Reuse the safe parser/functions; detect cycles, missing variables and
invalid geometry. Store overrides in the own rule, never modify imported ATT.
Blank input restores the imported/measured rule. Unsupported original scoped
ATT remains inspectable, but must not be misrepresented as an executable own
formula; the editor explains the fallback and accepts a replacement.

Commit is atomic: validate the rule and calculate a safe preview before accepting
the edit. Retain failed input, reject stale module/revision and block while the
variable draft is unsaved. Preview/trial/update must apply the saved formula,
preserve the current envelope, own constraints, source and copy independence.

Acceptance: numeric + ƒ idle, double-click/formula/Enter/Esc/error recovery;
formula edits change geometry and survive JSON/trial reload; input changes
reevaluate expressions; invalid/cyclic/outside/conflicting formulas fail safely.
