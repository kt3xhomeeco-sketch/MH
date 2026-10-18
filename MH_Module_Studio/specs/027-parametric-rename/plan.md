1. Extract pure reference-aware rename migration owned by Parametric editing.
2. Apply it before variable/detail validation so custom symbol dependencies do
   not become dangling references. Keep generated cells using existing aliases.
3. Test dependent/manual/generated cells, scope/token boundaries, ID identity,
   simultaneous renames, failure isolation and serialized rules.
4. Run scoped gate, actual Parametric save/preview/native private-copy edits;
   reload through VBO and rebuild the explicit package.
