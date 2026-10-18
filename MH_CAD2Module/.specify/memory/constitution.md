# MH CAD2Module Constitution
Version 1.0.0, ratified 2026-10-18.

1. SketchUp is the working surface; geometry writes use named undoable operations.
2. Dimensions come from CAD coordinates, never DIM text or AI estimates. Missing evidence is an explicit error. User-authorised plan-only previews use an explicitly provisional 1600 mm height, never report it as measured CAD height, and cannot train full-height layouts.
3. For DWG-path builds, centre products on label world X, front Y=0, floor Z=0; retain assembly offsets. Per the user's direct-scan update, SketchUp-scanned products instead use the scanned plan's world coordinates and plane offset, without requiring a label.
4. Source snapshots, jobs and history initially live in the app's library/ directory per the user's 2026-10-18 update. Relocation copies history without deleting old files or silently changing its meaning.
5. Corrections are immutable before/after events. Ordinary edits are not training.
6. Recognisers and examples explain evidence and scope; ambiguity cannot invent depth.
7. RuboCop, Ruby checks, pytest and native SketchUp verification are release gates.
