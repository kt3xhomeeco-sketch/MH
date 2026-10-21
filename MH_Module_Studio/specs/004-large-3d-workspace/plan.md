# Plan

Keep the Ruby calculation core unchanged. Replace the multi-column UI with a
single viewport and one scrolling sidebar. Retain action/input IDs and keep
expanded accordion state across publications. A separate local JS viewer uses
WebGL depth testing, opaque face colors, depth-tested edge lines and independent
X-ray blending. Software depth rasterization is the fallback when WebGL is
unavailable. No CDN or network runtime dependencies. Dispose resources on removed
snapshot views; use a single persistent main viewer.

Validate actual overlapping surfaces with pixel comparisons, arbitrary camera
views and hidden edges. Verify UI controls at normal and minimum window sizes,
source/result display and drafts. Run existing scoped Ruby/UI regression gates,
reload the correct SketchUp process through VBO preserving state, then refresh RBZ.
