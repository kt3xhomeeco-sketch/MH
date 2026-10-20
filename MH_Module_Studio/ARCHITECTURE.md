# Calculation and host boundaries

`core.rb` is the portable entry point. Requiring it must load only the
`calculation` files declared in `runtime_manifest.json`, without SketchUp, UI,
Geom, ABF, DCFunctionsV1, file-reader processes or host observers. Runtime and
build tooling share this explicit manifest; adding a component must update it.

## Ownership

| Component | Responsibility |
|---|---|
| `assembly_inference.rb` | Portable envelope contact/coplanar/parallel discovery, signed current gaps, selected-envelope obstruction, duplicate and dependency policy for inferred contacts |
| `assembly_presentation.rb` | Portable module-first HUD hierarchy: separate module rows, all scoped assembly members and clickable relationship labels; no geometry or native access |
| `assembly_auto_links.rb` | Explicit selection capture of six oriented envelope planes per module, selected legacy inferred-panel replacement and batch creation through Assembly; no panel traversal or geometry redraw |
| `domain.rb` | Data normalization, dimensions, observation learning, validation, public Core dispatch |
| `formula_math.rb` | Shared numeric operations, whitelisted math, arity metadata |
| `formula_parser.rb` | Restricted expression parsing into data |
| `formula_aliases.rb` | Verify serialized alias data/templates; no runtime discovery |
| `formulas.rb` / `DCFormulas::Program` | Numeric ATT evaluation and axis frame reconstruction |
| `symbolic_program.rb` / `SymbolicProgram` | Affine algebra and symbolic positions |
| `parametric_program.rb` / `ParametricProgram` | Attribute rows and editable cell expressions |
| `parameters.rb`, `attribute_rules.rb` | Parameter learning, formula plans and geometry checks |
| `plane_solver.rb`, `rule_system.rb`, `position_rules.rb` | Solve and describe own constraints |
| `parametric.rb` | Own variables, expression evaluation, source module titles separated from observation labels, display-name metadata, safe filenames and current-value export |
| `parametric_model.rb` | Native rename transactions and assembly presentation without flattening member programs |
| `assembly_file.rb` | Verified assembly SKP payload, stable member/panel references, independent rules/values, temporary export/import and backups |
| `parameter_rename.rb` | Migrate own symbol references by variable identity when applying a rename |
| `thickness_symbols.rb` | Identify thickness drivers, standardize T1/T2, merge secondary bindings into one variable and preserve high envelope anchors for merged layered panels |
| `options_parameters.rb` | Portable option rows, mixed common T1/T2 values and private module sections; no native model access |
| `parametric_sheet.rb` | Build sheet data; no HtmlDialog or model writes |
| `frames.rb` | Matrices, bounds, scale decomposition and bounds-to-transform arithmetic |
| `dc_frames.rb` | Shared ATT policy: instance COPY indices, declared numeric-string length lists and captured flat-axis transforms |
| `dc_visibility.rb` | Versioned inherited visibility, structural guard policy, stable descendant/depth anchors and copied Scale seed metadata |
| `inactive_geometry.rb` | Keep inactive alternatives inside proved root output spans while retaining native Scale on free axes; preserve already-contained geometry and prefer rigid shifts before positive affine compression |
| `construction_frame.rb` | Accept cached DC construction dimensions only after every captured part matches ATT; retain that input frame separately from the mesh union and solve explicit Scale targets through the original formulas |
| `dc_dependencies.rb` | Transitive AST dependencies through all branches and bounded input/threshold probes; no inferred replacement formulas |
| `dc_custom_inputs.rb` | Fresh-read discovery of referenced numeric root constants, conservative direct-consumer mm inference and versioned display/evaluation factors; no host access or legacy rewrite |
| `dc_custom_attributes.rb` | Retain other root custom ATT as readonly own parameters, preserve original keys and evaluate supported numeric derived values through Program; upgrade older payloads in memory without changing geometry inputs or existing symbols |
| `axis_rebase.rb` | Equivalent cardinal-axis conversion of nested ATT frames, length/position references and nominal aliases in copied calculation data; non-cardinal/sheared frames remain unsupported |
| `static_geometry.rb` | Explicit zero-variable modules only for sources without geometric ATT or exposed inputs; preserves actual mesh and native Scale without inventing T |
| `dc_copies.rb` | Verify leaf COPY families, upgrade retained ATT inputs in memory, compute dynamic part additions/removals and exact positions; preserve the existing geometry path while template topology is unchanged |
| `copy_runtime.rb` | Materialize/remove owned leaf groups/components from the portable copy plan inside the existing Runtime transaction; no formula evaluation |
| `dc_options.rb` | Decode DC LIST labels/values (legacy JavaScript escape and UTF-8), convert base length values to mm, share dropdown metadata across Parametric and Module Options |
| `envelope_policy.rb` | Prove unexposed VIEW/NONE/unspecified output axes independent of their own root dimension; verify declared lengths against exact ATT union spans on each request and reconcile older policies. Numeric Program also resolves declared readonly root outputs independent of every measured root length through Parent references. |
| `geometry_motion.rb` | Validate part motion and compute finite transforms for boxes, wire-only auxiliaries, rigid non-box geometry and native-verified arc-free faceted leaf meshes |
| `scale_plan.rb` | Pure reconstruction after Scale; no observer/Undo/UI calls |
| `studio_calculation.rb` | ATT-first Studio rule building and geometry fallback policy |
| `assembly_math.rb` | Portable inter-module plane offsets, centering, angle, clear-gap arrays, dependency ordering, allowed motion and weighted aggregate-envelope correction |
| `placement_math.rb` | Portable empty compartment bounds and source-to-target affine fitting |
| `import_recovery.rb` | Import-only absolute plans from consistent saved formulas/snapshots; stable identity/topology/visibility checks and existing GeometryMotion policy; ordinary edit/export validation stays strict |
| `library_placement.rb` | Native compartment picking, thickness-preserving import and atomic envelope-only replacement without target ATT/geometry validation; detached targets bypass assembly solvers, linked targets retain remapping while skipping discarded-target redraw; independent of MH_Superimp |
| `library_thumbnails.rb` | Per-SKP presentation views and PNG cache in the library folder; unique temporary definition camera rendering in an aborted operation; no source SKP or calculation writes |
| `library_monitor.rb` | Incremental metadata catalog observations with a 4 ms Ruby work budget per timer tick, stable-change debounce and no SKP content/native model access; Library owns visible-surface lifecycle and UI reconciliation |
| `dc_library_conversion.rb`, `library_conversion.rb` | Native batch file conversion and separate Library action/progress controller; verified ATT compilation/canonical T/Scale probes, static root-scale baking, aborted temporary model work, per-file failures, signature-based updates/backups and UI-timer cancellation |
| `library_import.rb` | Bounded display-only import preview and16-item/8MiB private validated-payload cache; one portable worker prepares the selected payload, synchronized with placement; native geometry and source freshness are still verified on the UI thread |
| `hud_thumbnail.rb` | HUD-only picture fit/zoom, grayscale ink strengthening, margin trim and versioned temporary prepared-PNG cache; source pixels/files and model geometry retained |
| `assembly.rb`, `assembly_tool.rb` | Model-scoped assembly persistence, stable panel anchors, transactions/observers and native viewport HUD; owned fit delegates internal reconstruction to ScaleRedraw |
| `assembly_face_picker.rb` | Tool-only real-face and six-sided oriented envelope picking, pointer tolerance, modifier priority and level labels; no model writes or global input hooks |
| `assembly_external.rb` | Model-space adapter for intact whole-assembly links, parent/local conversions, containment dependency checks and internal reconstruction when a whole assembly fits |
| `assembly_containers.rb` | Managed parent Components, component-local rule persistence, root/panel remapping, explicit connected assembly grouping and copied-wrapper independence; Save Link never groups; no internal ATT calculation |
| `assembly_contacts.rb` | Contact translation and opposing-face size fitting; predicts eligible owned leaf/root face responses through ScalePlan, retains native probing fallback, delegates linear corrections to AssemblyMath and verifies applied geometry |
| `assembly_envelope.rb` | Native aggregate-box verification and correction after parent Scale or member parameter edits; measures free dimension responses, excludes derived thickness axes, delegates arithmetic to AssemblyMath and reconstruction to existing assembly/Scale owners |
| `assembly_hud.rb`, `assembly_tree.rb` | Persistent Overlay session, expandable native viewport tree and model highlights; survives native Tool changes, closes on model switch |
| `assembly_hud_input.rb`, `native/assembly_input_v2.dll` | UI-thread mouse events limited to the visible tree rectangle; never captures keyboard; timer dispatch outside Overlay callbacks |
| `assembly_inspector.rb`, `ui/assembly.*` | Compact utility-window controls anchored beside the viewport; picking and constrained drag explicitly reactivate the model Tool |
| `module_file.rb` | Explicit verified SKP writes, file signatures/backups and payload restoration; temporary native work aborts before file replacement |
| `reader.rb`, `dc_function_capture.rb` | Native/SDK inputs and installed DC function discovery |
| `runtime.rb`, `scale_redraw.rb` | Apply validated plans, own model transactions and Scale observers |
| `main.rb`, `module_options.rb`, `library*.rb`, `hud_input.rb`, `ui/` | Controllers, dialogs, persistence, library, HUD, rendering and input |

New/Open notifications explicitly invalidate Studio's native capture/read session
and rebind Scale/Assembly/Options observers: Windows may reuse the same Ruby
Model object for a new file. The option window has a separate session token so a
reused root PID cannot retain a queued edit from the previous file. Operational
assembly records filter deleted module references without changing stored data;
Undo can restore the module and make its saved links visible again.

Numeric Program has a single owner. SymbolicProgram derives from it, and
ParametricProgram derives from SymbolicProgram. Feature files must not reopen
Program to install sheet or symbolic methods. This keeps a sheet change from
replacing numeric evaluator methods. Parametric calls the stateless shared math
module directly; it does not allocate an uninitialized numeric Program.

SketchUp/ABF discovery belongs only in DCFunctionCapture. It can return verified
alias data to the portable core. It must not execute imported functions. Reader
retains delegating methods for its existing adapter API. ScaleRedraw.plan and
Parametric.sheet/describe also remain compatibility facades; calculation belongs
to ScalePlan and ParametricSheet respectively. Existing single-module payloads
remain readable; feature 047 adds a separate versioned assembly SKP payload.

## Data ownership

Snapshots, rules and plans are nested data, not live SketchUp entities. Learning,
rule building, public planning, numeric program instances and sheet facades own
copies before normalization or editing. Output rows/alias maps do not expose
mutable constant strings. Changing a draft sheet or one learned rule must not
rewrite its source snapshot, another rule or later evaluations.

Methods explicitly ending in `!` normalize/edit their owned arguments. Callers
should not pass a shared draft into these methods when they need to preserve it.
Host bindings (entity handles) remain in Runtime/Reader; they never enter core
snapshots or saved rules. Runtime applies the pure Frames matrix using the native
Geom API and performs native result verification in the transaction boundary.
GeometryMotion handles flat bounds without dividing by zero. Numeric, symbolic
and editable-cell frame owners share DCFrames; host-specific geometry access
remains in Reader/Runtime. Their regression fixtures cover the same drawer data.

## Change policy and verification

- Start changes in the owning component. Preserve the public data contract.
- Keep dependencies directed from adapters toward calculations. Do not require
  Reader, Runtime, dialogs, library/HUD or installed DC classes from the core.
- Shared math intentionally affects all consumers. Test the affected consumers;
  isolation reduces accidental coupling and cannot guarantee zero regressions.
- Run `bundle exec ruby tools/check.rb`. Boundary tests cold-load the core in a
  separate process, check declared dependencies and method owners, and exercise
  frozen/shared input and cross-feature behavior. Existing geometry/formula,
  sheet, dialog, HUD and Scale tests remain required.
- Native geometry/Undo/reload still require actual SketchUp validation. Portable
  tests cannot establish native behavior.
- Build with `python tools/package.py`; the explicit manifest excludes developer
  tools, tests, source libraries and captures.

Feature 036 extends drawer conversion to flat wire auxiliaries and relative
formulas under scaled containers, verified against captured geometry. Non-box
solids may translate rigidly; deformation remains limited to verified boxes and
wire geometry. It does not implement DADX or change the fixed-envelope rule.
Feature 037 fixes scalar FLOAT/STRING formulas with length references: their
reference scale comes from declared authoring units, while their result remains
scalar. All three formula consumers inherit this policy from Program.formula_unit;
native scratch probes and the actual plinth fixture verify the unit conversion.
The current library conversion report contains 110 exports out of 227 MH sources,
including 25 newly converted drawers and the plinth. Unsupported sources retain their
diagnostics; no conversion is accepted solely because attributes can be read.
Feature 039 adds 14 verified MH exports and two separate sources from DC/Dat;
the latter are not included in the denominator 227. User-customized older exports
are preserved, so this report is not a count of every SKP now in the Library.

Feature 038 separates visibility from structural topology. Newly read native
snapshots contain own hidden/tag flags and `visibility_version: 1`. Existing-part
activation reconstructs formula geometry before native visibility changes; tags
remain masks. Runtime resolves node changes by a descendant part key plus ancestor
depth. Generated flat models persist a flattening flag and apply effective leaf
visibility, retaining the same calculation semantics without fabricating parents.
Scale plans compare actual native flags, update only copied calculation seeds and
preserve single Undo/Redo behavior. Programs lacking split visibility metadata
retain legacy activation guards; reread the original in SketchUp to upgrade.

Input recognition follows transitive formula references across inactive branches.
At most eight candidate values supply activation evidence. Conditional inputs
without a verified activation remain identified with a diagnostic, including
selectors needing another positive dimension first. Numeric ATT is always
reevaluated for actual requests; probes/slopes never replace its formulas.
Copies generation, rotation changes and Piecewise Affine remain separate work.

Feature 039 adds deterministic occurrence keys for repeated labels. New native
reads set `formula_frame_version: 2`: explicit ordinary formulas use captured
authoring-frame multipliers; implicit dimensions inherit resized parent frames.
Nominal physical aliases retain direction-only multipliers. Numeric, symbolic and
editable-cell owners share this policy. Earlier saved programs keep their frame
semantics. STRING display attributes with explicit length formula units remain
physical lengths, including hidden intermediate attributes and non-LIST controls.

Reader verifies axis-aligned surface meshes as `affine_verified`. Positive finite
diagonal maps preserve their mesh topology without extruding/collapsing flat axes.
Runtime transforms only direct mesh entities; descendant parts have independent
absolute plans. Native glue is removed only on private owned copies to avoid
implicit child motion when shell faces change. Other non-box geometry remains
rigid-only; no opaque functions or curved-panel deformation engine is added.

The fixed-envelope rule permits proved readonly outputs: a source root VIEW axis,
or a NONE axis with an explicit supported root length formula. The complete
geometry/visibility dependency graph and explicit declaration must exclude that
root dimension. EnvelopePolicy predicts exact formula-union endpoints and checks
explicit declarations against their spans on every target. Missing/older subset
policies migrate through the same proof; malformed or excessive axes are rejected.
Own cell overrides still must meet that prediction. Nóc 2 Thân therefore
keeps 400x350 while its Z span follows 2*T. Scale, saved payloads, own cells and
native verification carry the same target envelope. Hộp Treo keeps all axes fixed.

Feature 040 lets a single-panel door's readonly thickness follow shared T1 inside
an assembly. Parent Scale captures its requested local box before normalization;
after member redraw and contact solving, AssemblyEnvelope distributes residual
span errors over measured free dimensions and restores the requested anchor.
Stored gaps and explicit B-follows-A direction remain unchanged. All work belongs
to the existing atomic repair transaction. Impossible spans abort. Repeat layouts
retain their existing source/copy pipeline and skip this additional envelope fit.

Feature 041 captures the pre-edit box for scopes receiving parameter updates, so
shared/private thickness edits resize free internal dimensions without growing
the aggregate. Scale targets take precedence when both operations are present.
Contact response probes on eligible leaf/root anchors use copied scaled snapshots
and the same validated ScalePlan, including reflected frames. Other anchors retain
native probing. Aggregate probes keep their measured step and correct from the
result, avoiding an unnecessary restore/redraw. Every final native result and
contact is still checked. Parameter-set validation constructs one Program per
bundle, checking every scalar rule against it; no global validation cache exists.

ScaleRedraw acknowledges each verified root's current signature before its caller
commits. This prevents duplicate observer reconstruction without acknowledging an
unrelated pending Scale. Abort/Undo rebuild observer state through existing events.
ModuleOptions cancels obsolete scheduled refreshes after a direct response and
skips unchanged inputs. Its JavaScript queue still accepts returning to the prior
value while a different value for that row remains in flight.

HUD native helpers are versioned v2 so hot reload can load new binaries without
restarting SketchUp. When UI.scale_factor disagrees with the native viewport,
helpers match a proportional viewport and report the measured pixel factor.
Assembly regions, mouse coordinates and Library drag coordinates use that factor;
keyboard filtering and its model-window scope do not change.

Feature 042 keeps Click as actual panel-face picking, Shift+Click as module box
faces and Ctrl+Click as managed assembly box faces. Ctrl wins over Shift. The
picker intersects the pointer ray in each owner's local frame, with five-pixel
edge tolerance. Actual-face hover uses the native face mesh. Virtual hover fills
the chosen plane and names its level; it does not require a physical face behind
an opening. Modifier transitions update the current pointer preview immediately.

Ordinary module anchors retain existing grouping/remapping. Links involving a
whole assembly use `external: true` model-level records and retain the original
component wrappers/internal links. Related cross-scope additions also retain
those wrappers. AssemblyExternal supplies world planes, projections, translations
and rotations to the existing contact/fit calculations. Internal scopes solve
before external relationships; a moved child scope is solved again before final
verification. Containment-collapsed external dependency ordering rejects self
links and cycles. Whole-assembly resize delegates to the normal component Scale
normalization, owned redraw, internal contact solve and aggregate-envelope check.
This does not add a higher nesting/component layer or whole-assembly repetition.

Feature 045 filters pointer candidates only during reference picking. B is
excluded from A/C/measurement picks and vice versa, including whole-assembly
parent/child references. A/C may share their surrounding module. When native
best-face picking is blocked by an excluded module, read-only intersections of
eligible real faces recover deeper targets without hiding objects. Envelope
candidates are filtered before distance ranking.

Automatic contacts operate only on the explicit selected modules/managed assembly
members, with an editable maximum gap. Real rectangular box faces, opposing
normals, convex projected overlap and unobstructed rays establish candidates.
Nearest faces per module pair/direction suppress farther surfaces. Existing
links/copy control and dependency direction take precedence. Assembly stores one
editable batch without solve/redraw/grouping, with scoped shared-definition
isolation and observer acknowledgment. This is assembly-level inference; it
does not replace internal ATT formulas or write library SKPs.

Feature 046's strict aggregate-depth behavior is superseded by feature 047 and
constitution 1.7. Parameter edits follow proven output-axis union endpoints in
both directions after solving contacts. Fixed ATT dimensions and physical T take
priority over retaining previous bounds. Explicit Scale remains a fixed request.
Non-driving fit probes are restored rather than leaving internal parts stretched.

Feature 047 keeps Options input nodes and caret alive on value-only responses,
queues drafts during native work and applies one batch transaction per flush.
Thumbnails are cached per selected instance, not regenerated for each redraw.
Module/part names are display metadata; canonical ATT node names and references
remain untouched. Current parameter values accompany every exported rule.
Assembly SKPs use a separate versioned payload with member-local identities,
transforms, programs and internal links. Export/reopen verification runs on private
copies and aborts temporary model work before replacing a file. External links
must be detached before saving a standalone assembly. Assembly Parametric lists
member names; member formulas retain their independent owners.

Feature 048 separates `formula_envelope` construction inputs from the actual
part union when physical thickness passes an unexposed, undeclared parent edge.
EnvelopePolicy permits that overflow only for established thickness-driver parts
on the same axis. It does not exempt unrelated groove/position or manual edits.
Runtime persists the construction frame as normalized component-local bounds
after geometry verification; Reader reapplies the current frame when reading.
Numeric ATT, Copies, own cell references, Parametric and SKP adapters share these
inputs. Native Scale replaces them with its requested box and still rejects an
axis that cannot contain physical T. Reducing T restores the original construction
edge instead of feeding an earlier oversized union back into Parent.Len references.

Feature 049 refines 047's eager assembly-output following. AssemblyEnvelope keeps
`assembly_envelope_target_v1` separate from the measured union. It tries the saved
construction target first and restores probe sizes on typed NoEnvelopeFreedom
failures. Only those failures can use actual geometry on proven changing output
axes, without overwriting the saved target. Geometry/ATT failures abort normally.
Parent Scale replaces the target; contact/layout edits reset affected scopes.
AssemblyFile retains `construction_envelope` as optional version-1 payload data,
so older files remain readable and oversized results do not drift after import.
Native validation covers 600 mm through T17.6/200/17.6/20, eight contacts, physical
panel thickness, SKP roundtrip and subsequent 660 mm parent Scale.

Feature 050 keeps display rename within the same snapshot identity. Panel handles
file-only drafts without a native root and preserves the parent title on a detail
rename. ModuleFile can use an independently signature-checked original SKP as the
geometry source for a renamed destination. Parametric preserves dirty variable
drafts across rename revisions and defers a single Save until acknowledgement;
failed rename cancels that deferred action and leaves its editor available.

Feature 064 keeps HUD layout identity separate from relative-path UI IDs.
LibraryCatalog reuses filesystem stat identifiers; Library persists a Base64
catalog binding snapshot beside library settings. HUDConfig validates/remaps
versioned layout JSON, including cross-folder slots and letter shortcuts.
Explicit config import/export alone computes SKP content hashes for uniquely
matching renamed copies; normal monitoring/drawing remains metadata only.
File dialog cancellation/error always acknowledges the settings controls.
The Parametric shortcut reuses Panel and its existing drafts.

Feature 065 promotes custom numeric root constants on explicit new reads, without
requiring TEXTBOX/LIST access. Discovery follows only supported AST references
from geometry/guards and excludes measured root dimensions, reserved metadata,
unused constants and derived formulas. Numeric strings remain scalars unless all
direct length consumers agree on one physical authoring factor. Versioned
`custom_numeric_inputs` retains original ATT values while numeric, symbolic and
cell-text evaluation share their mm-to-original-scalar conversion. Thus Xuong=5
can appear as 50 mm without changing the source DC. Existing saved programs with
no descriptor keep their original independent inputs until reread.

Feature 066 promotes the developer converter into DCLibraryConversion; the old
tool class delegates to it. Native file conversion uses fresh StudioCalculation
and rejects geometry fallback when ATT cannot compile. Source-relative filenames
also define module titles. Each file restores the current model/definitions/
selection before publishing its verified SKP. LibraryConversionUI publishes
separate progress states and retains source/destination choices during the session.
Existing outputs are skipped unless explicitly updating a report-signature-matched
conversion; verified backups precede atomic replacement. Skip/failed-update rows
retain output provenance so a later retry can still upgrade an untouched file.
Reports live under .conversion, which ordinary Library scanning ignores.

Feature 070 keeps source normalization in `StudioCalculation.prepare`. Cached
construction spans are accepted only when all source parts agree, and persist as
versioned `construction_inputs`; measured union spans never replace them after
an overhang changes. Explicit Scale solves and verifies its requested union box.
Signed non-thickness parameters retain their negative baseline domain where the
source uses a front overhang. LIST selectors with contradictory length/string
metadata may become scalar IDs only after the corrected interpretation verifies
the complete source geometry; ordinary length lists retain their units.

Reader records `linear_mesh_verified` only for native leaf meshes without arcs,
allowing the same positive diagonal affine deformation as native component Scale.
Root-only geometry uses `virtual_root_mesh` to inherit existing root ATT lengths;
it does not invent a thickness variable. Canonical root-mesh corrections compare
against current geometry, while legacy parts keep their established delta basis.
Whole-root wire guides follow independently proved output spans of the actual
solid union and do not constrain physical T. Mirrored direct-child edge anchors
are shared by numeric, symbolic and Parametric evaluation. Inactive geometry
cannot override exact root thickness; all motions still pass GeometryMotion.

The 070 audit repaired 19 of 29 blocked active sources: 13 newly converted
sources were published without overwriting existing SKPs, and six previously
converted sources passed new edit/Scale checks without restoring deleted or
renamed library paths. The active scope is 149/159; ten sources retain explicit
diagnostics. Unsupported parent context, inconsistent saved geometry, CAM profile
semantics and non-cardinal frames remain rejected. Manual-input LIST modes are
not introduced by the selector-unit repair.

Feature 071 adds direct-reference LIST modes through DCOptions. Only numeric
root TEXTBOX attributes with matching units and no derived ATT formula qualify.
The selected LIST variable stores an ordinary own Parametric formula referencing
that input's symbol; selecting a preset removes the connection without erasing
the last manual value. Symbol rename and SKP persistence use existing variable
identity/formula mechanisms. No extra geometry evaluator or source DC mutation
is involved, and unsupported expressions remain disabled.

A referenced inactive input can be edited as own variable data even when its
original ATT has no active geometry dependency. It is not promoted to an engine
override: the evaluated LIST number alone reaches the verified ATT plan. Options
shows a nested numeric input for the active manual mode when that source is not
separately exported. Member-prefixed IDs and explicit targets preserve assembly
ownership; a separately visible source row suppresses the duplicate inline field.

Feature 072 stores opt-in `import_template` data in the existing own module rule.
ImportTemplate owns validation, partial slot fitting and same-symbol physical T
edits without any SketchUp dependency. ImportLinks captures actual host boundary
faces/cavities, caches them per model revision and draws only matched host faces.
Its preview and commit share one match set; absent surfaces remain unbound. This
explicit import workflow is distinct from envelope-only automatic linking of an
existing selection. Native placement, contact solving and host reservations use
one Assembly transaction, including selection changes, so selection observers
cannot add a separate operation after placement.

AssemblyParameters records the explicitly grouped host as a stable master member.
Confirmed thickness variables with matching own symbols follow it before contact
solving. Regrouping and AssemblyFile preserve that identity. ImportLinks retains
independent original host depth and uses the maximum actual door T plus clearance
on each opposed mounting plane. Inset doors do not reserve depth or bind their
rear to a cabinet back. Native ATT/fixed dimension/Scale verification still applies.
Internal module evaluation remains with RuleSystem/Core; no DC redraw is invoked.

For geometry-only rules, a thickness axis may be an envelope output only when
every visible part spans that axis and all explicit thickness constraints predict
the same planes with their saved anchors. This lets a standalone panel follow T;
it neither relaxes cabinet envelopes nor overrides ATT or explicit fixed faces.

Feature 073 keeps committed Scale candidates pending until native repair has
completed. SketchUp abort_operation also reports Undo and unchanged edit-path
notifications. Those notifications re-evaluate an already pending Scale against
its last acknowledged transform instead of consuming it as a new baseline.
Restored/cancelled transforms clear the queue; completed Undo and real edit-path
changes retain their previous reset behavior. Generation checks still discard
obsolete timers, and parameter geometry evaluation remains unchanged.

Feature 074 adds an explicit Assembly.redraw adapter shared by the compact Options
button and the assignable command. Requested anchors participate in ordinary
instance independence/remapping and join normalized Scale members in one unique
rebuild set. The existing native transaction retains formula/T/contact verification,
assembly solving, Undo and failure rollback. Runtime.stamp_redraw reuses metadata
only for an already validated plan with matching root/part identity, rule, values
and display names; all other calls retain full Runtime.stamp validation. Options
reuses parsed member metadata only while serialized rule/values match in its
current model/window; names, anchors and request tokens are refreshed.

Feature 075 limits AssemblyTree to participants in live links, keyed by scope and
root PID, including repeated instances and a linked containing wrapper. Only
participating members appear within a wrapper; unrelated groups stay available
for viewport picking and selection-based inference. This read-only filter does
not rewrite saved records. The Parametric header opens the existing import-template
section directly; the existing save payload persists that template to module SKP.


Feature 076 makes ImportTemplate.match derive inside-placement bounds from the
cavity interval after enabled offsets; inset doors exclude their thickness axis.
ImportLinks appends explicit host-envelope candidates only for inside placements,
with actual inner planes preferred at every boundary. Envelope candidates persist
as ordinary module anchors and inward negative signed contact distances. They are
outlined, never presented as filled real faces. Disabled slots create no records.
The existing contact solver maintains enabled relations after placement; Fit does
not invent persistent constraints on the remaining free dimensions.

ImportLinks and the preview dimension label extract positive axis scales from
Frames.scale_frame(matrix), since SketchUp transformation axis accessors normalize
away Scale. LibraryPlacement verifies the resulting bounds and refuses ATT/T
mismatches. AssemblyPresentation.gap converts the envelope normal sign at the HUD,
Measurements and input boundaries; solver records keep their signed coordinates.
No extra fit engine or changes to internal ATT evaluation are introduced.

Feature 077 supersedes 076's whole-cavity initial Fit: ImportTemplate resizes an
axis only with two enabled opposing slots. A single slot aligns without changing
that size; disabled slots stay unbound. The inside front uses the host front datum
even when a brace trims the detected cavity. LibraryHUD recomputes placement from
click-time flags: Ctrl replaces, Shift fits without links (080), otherwise saved contacts apply.
No template or no match also inserts raw at the source dimensions.

OptionsParameters merges compatible explicit symbols for a multi-selection;
ModuleOptions retains scope/root identities, including children of copied shared
definitions, and uses one Assembly transaction for batch edits and rollback.

ContactDisplay owns portable smaller-face prism geometry and hit priority.
ContactView owns native drawing, click dimensions and on-demand settings, reusing
Assembly edits. AssemblyHUD retains only its overlay/timer by default; its legacy
tree and global mouse hook remain suspended. The active AssemblyTool handles
contact clicks; native Move/Scale own their input while that tool is inactive.

Feature 078 keeps the LibraryHUD sample active after Replace. Its next click
replaces again; Esc returns to browsing. Library and HUD sample selection replace
an existing object selection immediately. UI gestures prevent a double-click
from performing the same batch twice. LibraryPlacement owns batch preflight and
atomic replacement, using Assembly for linked targets and a local operation for
detached targets. Replacement transfers a fully verified fresh definition and
its metadata/child identities to the surviving parent, then updates only its PID.

LibraryImport caches portable ScalePlan results by rule, actual snapshot and
values, excluding only capture ID/label/source/time. The existing bounded JSON
cache holds no live entities. Every target still captures and verifies geometry.
ComponentMetadata carries rule/value seeds on definitions without root identity.
Runtime updates that seed when stamping or verifying its own results.
LibraryAdoption independently watches external component creation/definition
changes, schedules adoption after transactions, makes a private tree and applies
the existing absolute ScalePlan. Transparent successful adoption joins native
Replace Undo. ScaleRedraw excludes pending adoption so old instance metadata
cannot redraw a newly assigned definition using the old module's rules.
Legacy identity probes cache only rule IDs and never evaluate complete ATT
programs during the cheap root scan. Native adoption currently targets individual
owned modules, not assembly-library payloads or unsupported nested edit contexts.

Feature 079 repairs the persisted pre-077 front-datum choice. Before contact
solving, ImportLinks normalizes only legacy annotated inside-import front slots
to the host front envelope and converts their signed gap, retaining the displayed
clearance. Changes persist through the existing Assembly transaction/Undo.
New imports carry an explicit front-datum policy marker, so a verified real front
face remains a real reference. Manual contacts, outside slots, other directions
and measurement-bound records are not migrated. No tolerance/offset fudge is used.

Feature 080 shares ImportLinks' actual cavity capture with Shift placement;
LibraryPlacement fits an independent instance without saving contacts. Normal
placement still resizes only between opposing selected contacts. DrawerVariants
owns the portable same-folder/filename-family standard rail chooser, preserving
slide kind, tier count and other name qualifiers. Concealed slides reserve 15 mm,
ball slides 5 mm; the longest available fitting sibling is chosen. Drawer frames
and fronts do not participate. Unlinked drawers fit width/height but keep nominal
rail depth, front aligned. Preview and actual click re-evaluate from the stable
selected seed; each batch replacement independently resolves its own depth.
Library owns bounded JSON preview reuse and SKP reads. Replacement loads a variant
inside the caller's transaction, never nesting preview start/abort operations.
The selected sample's import intent transfers to the chosen variant; fixed depth
and requested contacts remain subject to the existing ATT/T/result verification.


Feature 081 moves HUD layout ownership to portable HUDBoards: explicit named
boards, unique A–Z keys, stable IDs, sparse eight-slot pages and angular sectors.
Library folder filtering remains independent. Old explicitly stored hud_orders
migrate once; no catalog discovery creates boards or populates slots. External
drops replace the exact slot; internal moves swap slots. HUDConfig retains holes
while remapping file identity/relative path/hash and exporting/importing boards.
Library enforces Edit-only board mutations, and LibraryHUD retains native input,
placement and Replace ownership. Directional sectors apply only outside Edit,
after center/close/page and exact icon targets; blank sectors never choose items.
The outer ring has no polygon fill. HtmlDialog owns board forms, validation feedback
and navigation; native geometry is unchanged by layout/config operations.


Feature 082 migrates HUDBoards to version 2: four sparse dock arrays plus explicit
per-entry digit mappings, with no implicit numeric migration. HUDLayout owns
portable edge wrapping, corner separation, hit targets and ring/dock exclusion.
LibraryCatalog's spacing scalar is independent of size and part of HUDConfig;
file remapping preserves dock holes and mapped digit identity. Internal moves
swap across zones, external drops replace their exact zone/index. LibraryHUD
separates click-release assignment from thresholded drag and loads dock textures
alongside ring textures. Selected images receive a translucent tint above their
texture. HUD title/close/guidance disappear; modal/tooltip/settings feedback stays.
The process-local Windows message helper v3 captures 0–9 and numpad; it retains
view-thread filtering and releases the hook on exit. Developer C source/build
remain outside RBZ; the explicit manifest ships only the built v3 DLL.
