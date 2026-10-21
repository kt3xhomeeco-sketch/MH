1. Keep linear contact corrections in AssemblyMath and measured native fitting in
   AssemblyContacts; reuse Assembly.resize and ScaleRedraw for owned interiors.
2. Attempt translation first. If inconsistent, identify opposite target surfaces
   along module axes, measure their response to size, solve translation plus size,
   apply and verify. Preserve transaction/Undo and dependency ordering.
3. Draw translucent triangles for reference/target faces before their outlines.
4. Add portable and native regressions; run RuboCop, Ruby tests, browser smoke,
   rebuild RBZ and reload through the existing VBO session.
