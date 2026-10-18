1. Audit all own-library SKPs and locate true thickness inputs and duplicates.
2. Add portable ThicknessSymbols and OptionsParameters; update runtime manifest.
3. Keep the single-module transaction wrapper and extract its native update body
   for atomic multi-member updates inside Assembly.transact.
4. Extend ModuleOptions selection, row grouping and protected member bindings;
   add compact section separators and mixed-value placeholders.
5. Verify portable math, single/group UI and native geometry/copy/Undo/stale cases.
6. Back up and migrate own-library SKPs and live owned roots, package and reload
   in the existing VBO session. Record any unresolved duplicate-input decisions.
