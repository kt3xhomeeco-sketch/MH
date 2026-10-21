# 090 — Free Library icons follow the circular HUD

## Behavior

- An icon saved as a free position follows the circular HUD when its center
  moves up, down, left, or right.
- `snap_x` and `snap_y` remain tied to their selected ring positions as the
  HUD moves or its radius changes.
- The ring and its relative free icons are clamped to the viewport as one
  cluster. A screen edge may translate the whole cluster; it must not clip one
  icon independently and change that icon's offset.
- If the cluster is wider or taller than the available viewport, place it
  deterministically while preserving every relative offset.
- Existing normalized positions migrate from their current on-screen location
  to a relative offset on first HUD layout. Ring slots, dock positions,
  shortcuts, and configuration version remain intact.

## Verification

Portable tests cover movement in all four directions, snap axes, viewport
edges, an oversized cluster, and legacy migration/config round trips. The
native HUD check runs the same edge movement in the active SketchUp viewport
with private in-memory settings and verifies the real saved preferences,
model geometry, and selection remain unchanged.
