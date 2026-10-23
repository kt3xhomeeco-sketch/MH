> Bug-investigation reading order: [ERROR_MAP.md](ERROR_MAP.md) when an error
> message or concrete symptom is available (exact message → owning file) →
> [FEATURE_MAP.md](FEATURE_MAP.md) → [FLOW_MAP.md](FLOW_MAP.md) → only the
> **Ownership** rows needed here.
> The remaining sections below contain current boundary/data/change rules.
> Feature history was moved verbatim to [CHANGELOG.md](CHANGELOG.md) on 2026-10-22;
> it is not part of default investigation context. Development workflow:
> [DEVELOPMENT.md](DEVELOPMENT.md).

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
| `assembly_hud.rb`, `assembly_tree.rb` | Persistent linking session; contact/draft display only while the linking Tool is active, empty overlay extents outside it; closes on model switch |
| `assembly_hud_input.rb`, `native/assembly_input_v2.dll` | UI-thread mouse events limited to the visible tree rectangle; never captures keyboard; timer dispatch outside Overlay callbacks |
| `assembly_inspector.rb`, `ui/assembly.*` | Compact utility-window controls anchored beside the viewport; picking and constrained drag explicitly reactivate the model Tool |
| `module_file.rb` | Explicit verified SKP writes, file signatures/backups and payload restoration; temporary native work aborts before file replacement |
| `reader.rb`, `dc_function_capture.rb` | Native/SDK inputs and installed DC function discovery |
| `runtime.rb`, `scale_redraw.rb` | Apply validated plans, own model transactions and Scale observers |
| `main.rb`, `module_options.rb`, `library*.rb`, `hud_input.rb`, `ui/` | Controllers, dialogs, persistence, library, HUD, rendering and input |
| `error_codes.rb` | Stable area prefix (`MH-UPD`/`MH-PAR`/…) for user-visible errors at the dialog boundary; pure mapping, no state, no host access |

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
