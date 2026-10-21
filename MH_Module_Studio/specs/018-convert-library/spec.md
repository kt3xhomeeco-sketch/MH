# Convert the authorized DC library

User requests converting D:/Cong viec/Sketchup/DC/MH to the app-owned SKP library
at D:/Cong viec/Sketchup/DC/Modul_studio. Preserve source bytes, names, relative
folders, geometry/materials/visibility, and readable ATT dependencies. Embed the
app's full rule/current values/public flags. Parent is a component; inner objects
are groups. Do not label uncompiled DCs as converted parametric modules.

Implementation uses the existing safe interpreter and SketchUp's native geometry
reader. Every temporary model edit is aborted. Normalize components to groups on
private copies, retain ATT until compilation, assign stable per-part keys to
disambiguate repeated names, then remove DC metadata on the owned export. Reject
baseline mismatches and verify the saved SKP by loading its embedded payload.

Do not overwrite unrelated existing destination files. Write progress and a final
JSON/CSV/Markdown report in the hidden .conversion folder. Hash all source SKPs
before and after. Point Library to the requested output once conversion completes.

Acceptance: source hashes unchanged; user model/selection/definitions retained;
converted files load with rules and original geometry, independent instances can
be edited; rejected files have exact diagnostics. Physical keyboard is unrelated
to this batch job. No branch or packaging changes needed for a developer utility.
