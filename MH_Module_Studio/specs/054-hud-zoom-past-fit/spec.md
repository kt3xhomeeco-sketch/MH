# HUD pictures larger than full fit

The user needs image zoom beyond100%. Extend the existing image slider25–300%,
preserving the circle diameter, thin border, hit area and2x ink enhancement.
100% still shows the complete picture. Larger values magnify the picture around
its center; only portions outside the unchanged circle are clipped. Explain this
next to the control. Do not clamp requested150/200/250/300 back to100.

Remove unused white/transparent margins from the in-memory prepared texture,
keeping three pixels of safety space; do not infer a crop for non-white corners.
Blank images remain valid. Source PNG/SKP bytes and Library view choices remain
unchanged. Triangulate the circle/rectangle intersection with UVs strictly0–1 so
the picture cannot repeat, stretch or cover the one-pixel outline.

Verify mesh bounds/full fit/magnification over narrow/wide image shapes, stable
margin crop and source isolation, preference/browser requests above100, native
GPU refresh and live slider, scoped lint/tests and package.
