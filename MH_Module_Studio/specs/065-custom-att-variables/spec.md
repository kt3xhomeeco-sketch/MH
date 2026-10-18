# Custom ATT constants in Parametric

On an explicit new DC read, include referenced numeric custom ATT constants in
Biến module even without TEXTBOX/LIST access. Do not expose metadata, unused
attributes, root dimensions or derived formulas as independent inputs.
For the selected Nẹp Bù Phải 50 #4, Xuong="5" is used directly by a cm length
formula. Show Xuong=50 mm and a Xuong reference in the backing LenY cell. Default
Scale retains 50 mm; editing Xuong intentionally changes that fixed dimension.
Renaming its symbol, compact-options visibility and saved SKP must retain binding.

Infer mm for scalar numeric strings only when direct length consumers give one
consistent authoring factor. Mixed/count/arithmetic uses retain scalar units;
never infer physical units from a parameter's name. Existing saved programs keep
their semantics until explicitly read again. Source DCs/SKPs are not modified.
