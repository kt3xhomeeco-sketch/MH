# Link-tool face picking

Only inside MH Link Modules: Click picks actual panel/group faces; Shift+Click
picks one of six oriented module-envelope faces; Ctrl+Click picks one of six
managed assembly-envelope faces. Ctrl wins if both modifiers are held. Preview
updates under the pointer and on modifier press/release, including empty openings
and near-edge tolerance. Filled preview, thin outlines and explicit level labels.
Other native tools, Library Ctrl-replace and keyboard shortcuts are unchanged.

Preserve existing saved panel anchors and B-follows-A behavior. Module-envelope
anchors survive ordinary grouping/copy remapping. Whole-assembly relationships
must keep the assemblies intact, with their internal rules and links, rather than
flatten or detach children. Cross-scope assembly relationships use model space
and existing transaction/geometry checks. Reject self-containing dependencies.
This does not implement the proposed new resize/add/remove interaction mockups.

Verify local/rotated/reflected bounds, actual versus virtual faces, modifier
updates, openings, saved relationships and private copies with portable and live
SketchUp checks on independent test entities. Preserve user geometry/selection;
run scoped RuboCop/tests, package and reload only the already-open model 1.
