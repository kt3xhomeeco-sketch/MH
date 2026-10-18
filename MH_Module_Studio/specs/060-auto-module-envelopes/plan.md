# Implementation plan

1. Capture six oriented virtual planes through the same native world-plane adapter
   used for manual module-envelope picking. Expand selected managed assemblies
   into member modules; never traverse internal panels for automatic discovery.
2. Keep inference portable: retain opposing contact and coplanar proximity, add
   signed parallel offsets within the existing search range, and use selected
   envelopes for gap obstruction. Preserve B-following-A dependency policy.
3. Migrate only selected legacy inferred panel records. Store removals and new
   envelope records in one transaction, including scoped shared assemblies and
   removal-only cases. Retain manual records and other assembly copies.
4. Separate snapshot observation labels from native module identity. Resolve
   generated and legacy draft titles from source metadata while preserving
   explicit user renames and unsaved table/formula drafts. Reading does not
   rename source objects or rewrite source SKPs.
5. Verify portable inference/title cases, browser editing behavior, native hollow
   modules, signed offset edits, SKP roundtrip, scoped copies and Undo/Redo. Run
   the scoped RuboCop/test gate, reload through VBO and build the RBZ.
