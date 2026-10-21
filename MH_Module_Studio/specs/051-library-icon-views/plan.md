# Implementation plan

- LibraryThumbnails owns per-library .mh-thumbnails/index.json and generated
  PNGs. Cache identity includes source fingerprint, chosen view and revision.
  Uncustomized icons retain existing temporary saved-SKP thumbnail behavior.
- Generate camera thumbnails on a unique temporary ComponentDefinition inside
  an aborted SketchUp operation. Set its thumbnail camera without moving the
  viewport camera. Validate source freshness before/after rendering; replace the
  sidecar only after successful rendering. Geometry/formula solvers are unchanged.
- Library publishes view metadata/cache keys and handles the explicit request.
  LibraryHUD releases stale textures; Settings does not carry per-icon editing data.
- Library UI retains draft view selections across image acknowledgements;
  stale image responses are rejected by key. Pending buttons recover on errors.
- Verify portable persistence/failure cases, browser interaction and actual
  SketchUp rendering through pinned VBO; run scoped RuboCop/tests and package.
