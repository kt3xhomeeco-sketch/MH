# Complete pictures, fixed thin circle and double image ink

Supersedes feature052's circular texture crop. The user needs complete module
pictures, with all corners visible, independently resized inside the original
thin icon circle. Keep the ring/hit layout and one-pixel outline unchanged.

Fit the entire rectangular texture into the circle, retaining aspect ratio and
all UVs0–1. Image percent25–100 scales only this rectangle;100 is the largest
complete image that fits. Normalize older values above100 to100, avoiding crop.

Strengthen module picture ink by2x: double grayscale line contrast and expand a
thin stroke by one pixel, once, from the original image. Preserve flat material
fills, colored pixels, alpha, padding and source PNG/SKP bytes. Apply on GPU
texture preparation only, never in frame-by-frame drawing or thumbnail files.

Check full-image aspect/corners, pixel stroke/color/alpha boundaries, native GPU
loading and actual draw vertices/UVs, live slider/persistence, existing Library
updates, scoped lint/tests, and package.
