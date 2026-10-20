# MH Module Studio Constitution

## Core principles

### I. Exact thickness, fixed dimensions and explicit targets
Use current geometry after MH_stretch or Scale, not the dimensions of a sample.
Physical T, fixed ATT dimensions and saved contact distances must remain exact.
Feature 047 supersedes the strict aggregate-envelope policy of feature 046:
parameter edits may change outer dimensions when exact formulas require it.
An unexposed root dimension (VIEW, NONE or no access metadata) may follow its
formula-union geometry only after complete transitive analysis proves independence
from that measured root axis. Explicit root output declarations must match the
predicted span on every request. Editable TEXTBOX/LIST dimensions remain targets.
For example, Nẹp Bù keeps its fixed 50 mm backing and depth follows T + 50.
No shortening formula is invented to preserve its previous depth.
Feature 049 refines managed assemblies: retain an independent construction target
and try free member dimensions first, preserving physical T and saved contacts.
Only a measured no-freedom/nonpositive-size fit may fall back to actual bounds on
proven output axes; keep the construction target for later edits. Geometry or
formula failures still abort. Explicit parent Scale supplies a new mandatory
target. Editing contacts/layout supplies its new bounds. A temporary oversized
result must not become the next requested assembly size. Other axes remain fixed.
Feature 048 also permits a verified thickness driver to pass an unexposed,
undeclared construction edge. Retain construction inputs separately from measured
union bounds so reducing T can restore that edge and repeated edits remain valid.
Only thickness drivers on the overflowing axis qualify; this does not authorize
groove/position overflow, expose a new input or relax explicit Scale targets.

### II. Own rules and a portable calculation core
Keep data validation, rule learning and planning independent of the SketchUp API.
Keep model access, transactions and UI in adapters. The app uses its own versioned
rule format; conversion into SketchUp Dynamic Components is not required.
The future importer is independent of MH_Superimp.

### III. Attribute formulas first, observations second
Read DC attributes on the root, every intermediate group/component and leaves.
Translate supported expressions and their references into the app's own portable
rules first. One complete readable DC can suffice; multiple states validate those
rules. Use geometric comparison only when formulas are missing or unsupported.
Identify the source of every rule and explain unsupported expressions.
Groups with and without ATT must share one editable own rule system. For ordinary
groups, infer face contact from measured geometry; names alone never determine
constraints. Inferred contacts on ATT modules remain references until explicitly
enabled so a single observed state cannot override an imported formula. Never
execute arbitrary imported Ruby or opaque ABF functions. Geometry verifies that
formulas match the current module and its declared envelope policy; names alone do not
prove a dependency. Safe interpretation of whitelisted expressions is permitted.
Explicit automatic inter-module linking uses only the six oriented envelope
planes of each selected module (feature060). Internal panel faces remain available
for manual linking; changing auto inference must not rewrite manual links.
Feature 072 adds a separate, explicit import template: match its enabled slots
against actual host faces, highlight only those host faces, and accept partial
matches. Feature 076 permits explicitly selected open sides to reference host envelope
planes; draw these as virtual boundaries, not filled real faces. Feature 077
resizes only between two enabled opposing contacts, preserving ATT/T and inset
door thickness. One contact aligns without resizing; no template/match preserves
source dimensions. Placement-click Shift fits the detected cavity without links
(080), retaining raw placement outside a cavity; Ctrl replaces. Drawer rail variants
retain nominal length while width/height fit. The open
front datum is the host front envelope, not the back of an upper front brace.
Matrix scale supplies real-mm offsets. The host needs no template. Door behavior is saved module metadata,
independent of its filename/folder. Opposed doors reserve physical T plus their
clearance from an independent host target; inset doors do not reserve depth.
Explicit grouping makes host thickness symbols authoritative across its members.
Compatible explicit symbols in a multi-selection share one Module Options input;
edits are atomic and scoped to instance identity. Direct contact prisms and
clickable dimensions replace the automatic tree/inspector HUD. Advanced settings
open on demand; native Move/Scale retain their pointer priority.
Feature 078 keeps Replace active until cancelled. Choosing a Library sample
replaces preselected blocks immediately; the batch is one atomic Undo. With no
preselection, ordinary placement remains available. Definition seeds carry reusable
rules/values, never root instance IDs; native Replace Component adoption gets an
independent identity and validates source rules/T against the requested envelope.
Calculation reuse is bounded and keyed by complete rule/geometry/values; it never
replaces live geometry capture or result verification.

Feature 081 makes HUD boards explicit named layouts independent of Library
folders. Sparse slots persist exactly, with no folder auto-fill. Directional
selection applies only outside Edit; placement modifiers remain unchanged. Feature 082 adds viewport-edge docks and
explicit per-icon digits, preserving sparse positions and file identity across
moves/config transfer. Spacing is independent of icon/image size; no numeric
shortcut is inferred from position.

### IV. Safe model changes and identity
Reading must not modify source SKP files or selected source DCs. Trial edits use
an independent copy with unique definitions and a single Undo transaction.
Reject unsafe plans and abort failed transactions. Keep template rules separate
from instance identity; copied attribute IDs alone cannot identify an instance.
Exploded-module recovery is future work, not a supported guarantee in v0.1.

### V. Verifiable quality
Run the scoped RuboCop/SketchUp gate and meaningful tests after relevant changes.
Use scenario coverage for geometry, dependencies, envelope preservation and
shared-definition behavior. Distinguish portable tests, UI smoke tests and native
SketchUp checks. Do not claim native validation unless it actually ran.

## Technical boundaries

Current target: SketchUp 2025 / Ruby 3.2. Developer tools run outside SketchUp.
Ship only extension runtime files in the RBZ, without gems, Python or Spec Kit.
Restrict this project's changes to MH_Module_Studio and its sibling loader.
Do not alter other extensions or the shared parent RuboCop configuration.

## Development workflow

For substantial new features, write the behavior and acceptance criteria with
Spec Kit, clarify material unknowns, plan, create tasks, implement and validate.
Routine fixes may use a proportionate workflow. User instructions take priority.
Do not add approval steps for already authorized reversible work. Record deferred
features and actual validation limits instead of marking them complete.

## Governance

Update these principles when the user changes an agreed requirement; explain
material tradeoffs in the feature plan. TOOLING.md documents the installed tools
and commands. This constitution describes requirements, not proof of completion.

**Version**: 1.16.0 | **Ratified**: 2026-10-14 | **Last amended**: 2026-10-21
