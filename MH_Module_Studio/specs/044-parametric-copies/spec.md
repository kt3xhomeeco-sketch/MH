# Parametric Copies

Reported: a Copies variable in Parametric cannot be used even when its display
checkbox is enabled. The checkbox remains visibility-only, as explicitly agreed
in the product requirements. It must not silently grant edit permission or
activate duplication on an arbitrary object.

Confirmed current behavior: custom Copies accepts non-negative integer data,
but no part/module target is attached and runtime has no create/delete-copy
operation. Imported inputs that change DC COPIES remain structurally guarded;
noneditable ATT inputs remain locked. These are separate paths, not a checkbox
bug. In the selected kitchen, child Hậu declares COPIES from Kiểu Chia and Số
Lượng, but that does not establish the target for a user-added Copies variable.

Confirmed target: owned model `3.CC Chân bệ` (Untitled, PID 454141).
Its original ATT already declares COPIES=b6sochanphu-1 and COPY-index spacing
through b7KCchanphu. The public input means total support legs (including the
original), while DC COPIES means additional instances. Reuse that explicit
binding, never infer a new duplication target from the checkbox or label.

Acceptance:
- Attach a count variable explicitly to the chosen part/subtree or module.
- Define count semantics (additional copies versus total instances), placement,
  and copy-index expressions in the UI and own rule data.
- Changing count adds/removes actual owned geometry and retains the template;
  changing thickness/Scale still recomputes every surviving copy.
- Preserve source DC/SKP, stable anchors, materials, independent instances,
  saved rule data and atomic Undo/Redo.
- Keep calculation and native topology mutation in separate owners; retain
  unsupported rotation/topology guards until the corresponding path is verified.
- Portable, UI, native geometry and scoped RuboCop checks before completion.

Initial scope: verified leaf part families with consecutive original COPY
indices and identical expression sets under one parent. Existing unambiguous
families upgrade in memory using their retained ATT. Dynamic topology is isolated
in DCCopies and CopyRuntime. The previous geometry path remains active when the
part topology matches the captured template. Unsupported subtree copying,
rotation changes and mixed custom geometric overrides remain explicit errors.
