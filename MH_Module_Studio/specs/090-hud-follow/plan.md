# Plan

1. Calculate relative free-icon offsets from the ring center, including ring
   snap axes.
2. Compute ring and free-icon extents, then clamp or center the common HUD
   translation within dock insets.
3. Leave legacy viewport positions independently placed until the existing
   migration converts them to relative coordinates.
4. Cover edge behavior with portable tests and the private native HUD check.
