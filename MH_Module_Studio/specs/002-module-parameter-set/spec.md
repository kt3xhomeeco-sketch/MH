# Feature Specification: One parameter set per module

**Created**: 2026-10-14
**Status**: Implemented; combined plans, UI, native creation/update verified. Native Undo unverified.
**Input**: All settings for carcass, back and offsets belong to one parent group
and must be aggregated instead of replacing one another as separate rules.

## User Scenarios & Testing

### User Story 1 - Analyze the whole module (Priority: P1)
Reading states and pressing Analyze creates one module containing every learned
thickness rule and all captured settings. Choosing a detail view must not erase
any rule. One saved project contains the complete set.

**Independent Test**: Analyze the supplied three states; both carcass and back
remain learned after switching the detail view and saving/reopening.

### User Story 2 - Edit parameters together (Priority: P1)
The trial view lists carcass thickness, back thickness and fixed settings in one
table. Editable settings can change together; dependent panels update once, the
parent envelope remains fixed and the action uses one Undo transaction.

**Independent Test**: Set carcass to 18 mm and back to 9 mm; expect top/bottom
width 564 mm and depth 173 mm, while the module stays 600 x 200 x 500 mm.

### User Story 3 - Explain missing evidence (Priority: P2)
Captured settings such as back setback 18 mm and engagement 8 mm remain visible.
Settings without learned geometry remain read-only and explain that more states
are required. Untested combinations and unsupported interactions remain visible.

### Edge Cases
- Reject unknown target keys and malformed aggregate projects.
- Keep legacy single-parameter projects working.
- Reject inconsistent fixed conditions or combined effects that disagree with
  captured states. Never replace failed parameters with fabricated rules.
- Plain trials retain the whole parameter set after DC metadata is removed.

## Requirements
### Functional Requirements
- **FR-001**: One parent module owns all settings and learned rules.
- **FR-002**: Analysis learns every supported parameter without erasing others.
- **FR-003**: Show one combined parameter table; unsupported settings stay visible.
- **FR-004**: Compute combined changes before touching model geometry; each panel
  changes once and a single Undo restores the complete operation.
- **FR-005**: Preserve source DC, current outer dimensions and identity behavior.
- **FR-006**: Save/open and trial metadata retain the complete module set.
- **FR-007**: A checkbox column with no visible heading selects parameters exposed
  with the module. Checked learned parameters can be edited; unchecked settings
  are read-only. Checked unlearned settings retain an explicit missing-rule state.
  Save/open, reanalysis and trial metadata retain the selection; internal dependent
  rules remain available regardless of public selection.

### Key Entities
- Module parameter set: one identity, all settings, rules and fixed conditions.
- Parameter: label, captured value, unit, learning status and optional rule.
- Combined plan: current values, targets and one final geometry change per panel.

## Success Criteria
### Measurable Outcomes
- Both supplied thickness rules remain available in the same module.
- The joint 18/9 mm scenario produces 564 x 173 mm top/bottom, with outer sizes
  unchanged within 0.15 mm and one final update per affected panel.
- Every captured editable DC setting appears in the parameter table, with
  unlearned settings explicitly read-only.
- Round-trip storage preserves every rule; no source DC is modified by reading
  or preview. Native mutation/Undo results are reported separately from preview.

## Assumptions
The current solver combines additive linear effects. Samples must support each
individual rule and the aggregate must explain observed combinations. Arbitrary
DC formulas and unobserved nonlinear interactions are not inferred automatically.
