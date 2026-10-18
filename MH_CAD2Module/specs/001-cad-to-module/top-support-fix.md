# Top module support boundary — 2026-10-18

User correction: "khối nóc 407+25". The upper module must include both complete support legs, down 25 mm from the 407 mm door's lower edge. The previous 0.1.1 implementation mistook the door bottom for the module bottom.

Evidence: C07/C09 are front/rear legs below C08, sharing Y=5063.040359 as their support plane. C0A's actual lower vertex is Y=5088.040359. The carcass bottom is Y=5113.040359, top Y=5495.040359. Required upper module: 1720×582×432, origin [0,18,2160]. Lower modules and overall envelope stay unchanged. DIM labels are not evidence.

Plan: reproduce the error with actual section geometry; match a deck and two legs at the upper carcass bottom, then use the shared measured leg bottom as the division. Retain the door profile as section correspondence evidence. Preserve carcass, door and support boundaries separately. Changing the door length must not change the support plane; changing both legs must change it. Apply to DWG and selected SketchUp edges. Parser 0.1.2 invalidates old caches/experiences. Run Python/Ruby/RuboCop and native SketchUp measurement/Undo checks.

- [x] Regression demonstrates the old 407/2185 error.
- [x] Section support boundary and evidence implemented for both input paths.
- [x] Missing evidence and changed offset tests pass.
- [x] Native dimensions, placement and Undo pass; refreshed runtime and RBZ delivered.

## Cross-view joint validation — 0.1.3
User explains that the front division belongs at a contact between rectangles (including closed LINE loops), and a candidate cannot pass through the unbroken vertical section panel beside the door.

Implementation: validate the proposed support plane against continuous rectangle contact coverage on both sides across the upper module's width in its actual front view. In the corresponding section depth band, reject any thin vertical panel crossing the plane without a measured horizontal seam across that panel. Short recovered panels are included; a recovered outer rectangle containing an actual seam is not treated as a single unbroken panel. Preserve front/section handles and the validation outcome in joint_evidence. Conflicting evidence returns needs_review instead of constructing a guessed module. This gate is scoped to the supported upper two-leg assembly, not arbitrary furniture.

- [x] Reject the 407 mm door-bottom plane because it cuts the section leg.
- [x] Reject the carcass-bottom plane when the front lacks a continuous contact seam.
- [x] Reject a changed section support height when the front still shows the old seam.
- [x] Actual DWG and native-edge worker inputs retain 432 mm at Z=2160 with both-view evidence.
