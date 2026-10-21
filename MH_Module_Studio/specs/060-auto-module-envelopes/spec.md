# Automatic links use module envelopes only

The user restricts automatic linking to module bounding envelopes. Capture exactly
six oriented planes for each selected module, with `level=module`, empty path and
no panel/part identity. A selected managed assembly expands to its member modules.
Use current definition bounds and instance/owner transforms, matching Shift+Click.
Do not walk nested groups, infer panel contacts, or ray-test physical faces.
Retain contact/coplanar discovery, measured gaps, editable B-following-A semantics,
duplicate suppression and no-motion batch creation. A third selected module's
envelope can obstruct a gap; the pure blocker test must use envelope planes only.
Manual Click/Shift/Ctrl face selection is unchanged.

Additional user steering: include parallel, noncoplanar envelope planes within
the existing search range, retaining their signed measured offset. Prefer opposed
contact, then coplanar alignment, then parallel alignment; do not infer penetrating
opposed faces. Label these saved relationships Song song.

Fix Parametric title provenance: Trạng thái N is an observation label, not a
module name. Capture native instance/definition/DC source identity separately;
new generated rules carry that name. Recover legacy placeholder titles from
available source identity in the draft without changing source SKPs on read.
Explicit user renames are tagged and remain authoritative, including when a
user deliberately chooses a Trạng thái N name. Preserve variable/formula edits.

When explicitly rerunning inference, replace only old inferred panel links whose
every endpoint is in the selection. Never remove manual links or unselected links.
Replacement and addition share one Undo transaction, including selected scoped
shared assemblies and the case where no new envelope link is eligible. Preserve
other assembly copies, source files, geometry and physical thickness.

Validate hollow modules (no real mesh on a virtual envelope face), internal near
contacts that must not generate links, rotation/reflection, grouped members,
legacy migration/manual retention, save/restore and Undo/Redo. Run portable tests,
UI workflow, RuboCop, real SketchUp checks, live reload and package.

This supersedes physical-face auto discovery in feature045/059. Their manual-face
picking remains supported; historical native physical-inference fixtures are not
acceptance checks for the new envelope-only policy.
