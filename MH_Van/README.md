# MH Van 1.3.5

## Thickness

Nesting and All group/component share one geometry-based thickness calculation.
Local face directions and projected spans are cached per component definition.
Rotation and translation do not alter thickness. The complete instance/ancestor
transform applies nonuniform scale, mirrored axes and shear to plane distances.
Affine axes come from the 16-element transformation matrix, including its
homogeneous weight. SketchUp's axis accessors normalize vectors and discard scale;
using those accessors caused scaled boards to show their definition thickness.
Flat faces remain excluded even when their world bounding box has three nonzero
dimensions. Containers without direct board faces use their local bounds as an
assembly-size fallback; an assembly does not have a unique board normal.

Definition observers invalidate edited geometry. Undo/Redo discard geometry and
visibility caches. Model changes detach the previous model's observers and caches.

Thickness labels, grouping keys and edit signatures use the same precision of
0.001 mm, with trailing zeros omitted. Thus 17.6 and 17.64 mm occupy separate rows
when thickness grouping is enabled, while transformation floating-point noise
does not create duplicate rows. The precision applies to initial scans, partial
updates, material-code regrouping and ABF count matching.

## Visibility

Bulk hide/show uses one SketchUp operation with UI updates disabled. Temporary
Tag mappings are kept in RAM and serialized at most once, before commit. Repeated
toggles reuse the row's Tag without reassigning every entity. Only the changed eye
buttons are patched in the dialog. Original Tags are restored when fast mode is
disabled; failures abort the operation and discard the runtime mapping.

Refresh uses a coalesced, one-shot timer after observer events. There is no periodic
scan of selected geometry while idle. Tag/folder visibility events update the
table without measuring board geometry. MH Isolate owns selection and zoom when
the shared isolation path is used.

New temporary Tag keys use a digest to avoid collisions between material codes.
Previously saved temporary Tag keys remain readable. Native and Ruby grouping
both report mixed thickness/color consistently.

## Coexistence with ABF and other readers

Closing the dialog detaches MH Van's entity, definition, model, materials,
layers and application observers, stops its refresh timer, and releases model
caches. Other extensions' observers and the model's material/visibility state
are preserved. Reopening performs a fresh scan and attaches current observers.
Structural refreshes discard observers on the previous nesting/label graph,
preventing deleted objects from accumulating across repeated ABF runs. Once a
full refresh is queued, further events skip individual-record work; the refresh
clears geometry profiles so intervening edits are still measured correctly.

MH Van no longer constructs ABF's private `SheetTypesTool` or calls `scan_types`.
Quantities come from its existing measured inventory; ABF bottom-face counts are
still read from model attributes. Material edits continue to change the shared
SketchUp material assignments, so other extensions see those changes. The shared
MH model hub is invalidated explicitly only when its revision shows that the
commit notification was missed; the HUD still receives its targeted edit token.

On the reported live model, the old closed dialog retained observers on 2,023
entities and 4,077 Entities collections. This confirms unwanted background
tracking, but does not by itself establish every cause of slow ABF nesting or
labeling. The fix is verified by regression tests; ABF workflow timings after
installing this version still need to be compared in SketchUp.

## Verification

From the SketchUp Plugins directory:

```powershell
ruby MH_Van/test/standalone_test.rb
node MH_Van/test/ui_test.js
```

These tests run outside SketchUp with API/DOM doubles. They cover rotation inside
and outside definitions, nested transforms, scale/mirror/shear, planar geometry,
geometry edits, native grouping parity, transactional cache writes and rollback,
original/manual Tags, idle behavior, isolation, partial visibility updates and tab
scope. Precision regressions cover separating 17.6 from 17.64 mm in both scopes,
material-code regrouping, native/Ruby grouping parity, and partial updates after a
0.04 mm edit. Timing output is a standalone measurement, not a SketchUp viewport benchmark.
Coexistence tests cover repeated close/reopen, preservation of foreign observers
and hidden Tags, late callbacks after closing, a 1,000-event structural burst,
20 cycles replacing nesting objects, zero private ABF tool constructions, and
shared-hub notification deduplication with a missed-event fallback.
The transformation double uses normalized axis accessors, matching SketchUp. The
regression fixture includes the reported 14.142857 mm definition scaled to 11 mm,
as well as uniform scaling represented by the homogeneous matrix weight.

For a read-only check using the real SketchUp API, select a board and run in its
Ruby Console:

```ruby
load File.join(Sketchup.find_support_file('Plugins'), 'MH_Van', 'test', 'sketchup_geometry_test.rb')
MH::Van::GeometryRegression.run(Sketchup.active_model.selection.first)
```

This compares cached thickness with independently transformed face vertices for
the current transform, rotation, nonuniform scale, reflection, uniform scale and
shear. It does not create or change model geometry. The 1.3.3 fix was also checked
against all 552 cached parts in the reported open model, including the 11 mm back
panel; every result agreed with the direct face measurement within 0.001 mm.

Restart SketchUp to load the new extension and remove any timer from the previous
version. In a real model, check rotated 18 mm boards in both tabs, repeated bulk
hide/show, Undo/Redo, toggling fast mode off, and alternating with MH Isolate.
