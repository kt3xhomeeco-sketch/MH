# Import contact templates

An own module can save a six-slot contact template (five enabled by the cavity
preset). Each source envelope face has a clearance. No host configuration is
required. During import, capture actual host boundary faces and highlight only
matched host faces, filled with thin outlines; never highlight the moving source
as a linked surface. One, two or any subset of slots is valid. Missing faces
remain unbound. Opposed placement uses outside host faces, inset placement uses
inside faces. Numeric preview and committed contacts must use the same match set.

Persist contacts using existing Assembly face anchors. Real panel anchors follow
ATT redraw; raw host panel paths acquire stable panel keys when grouped. Paired
opposite contacts may resize the imported module, preserving its ATT/T. Unpaired
directions retain their original dimensions. Old templates without the feature
retain current import/replace behavior, including Ctrl replace and Esc routing.

On explicit grouping, the host/A member is the master. Confirmed physical
thickness parameters with the same case-insensitive own symbol follow its value.
Use stable member identity, retain that master when regrouping, and synchronize
future grouped edits before solving contacts. Unrelated parameters stay private.

Door templates reserve the door's actual thickness plus 1 mm from an opposed
host's construction depth along the mounting normal; preserve the far boundary
and original combined extent. Recompute from an independent target, never
subtract cumulatively. Adjacent doors on one plane use one maximum reservation.
Inset doors do not reserve host depth. Changes, grouping and source parameter
updates remain one atomic transaction and use normal ATT/Scale validation.

Acceptance: pure partial/inside/outside fitting and synchronization tests; actual
native hover/placement/contact/T/door/group/regroup/Undo/SKP checks; browser
configuration round trip; full RuboCop/tests, explicit manifest/package and VBO.
