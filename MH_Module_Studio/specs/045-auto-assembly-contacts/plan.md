# Plan

Keep eligibility in AssemblyTool and read-only native face intersection in
AssemblyFacePicker. Filtering is active only while selecting a reference.
Native PickHelper retains ordinary best-face behavior; when the best available
face is excluded, ray intersections recover real allowed faces behind it.

AssemblyInference owns portable convex overlap, candidate measurements, duplicate
and dependency checks. AssemblyAutoLinks captures a bounded explicit selection,
checks real face geometry and obstructed rays, then delegates batch persistence
to Assembly.store_contacts. Do not call the geometry repair transaction when
capturing the existing state. Remap relevant shared scope identities atomically.
The inspector exposes the action and editable saved links through existing APIs.

Limits: box-boundary rectangular faces only, at most 40 modules/2400 eligible
faces/200 total links. Arbitrary curved/holed faces and empty envelopes do not
prove automatic contact. Explicit picking remains available for supported
manual anchors.
