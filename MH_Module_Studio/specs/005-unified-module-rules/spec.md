# Feature Specification: Unified module rules and in-view browser

**Feature**: 005-unified-module-rules (existing checkout, no new branch)
**Created**: 2026-10-14
**Status**: Accepted for implementation
**Input**: Build the approved Fusion-inspired mockup, infer contacts from ordinary SketchUp groups, edit/add rules, and convert groups with ATT into the same rule system. Use Spec Kit and RuboCop.

## User Scenarios & Testing

### User Story 1 — Ordinary cabinet (Priority: P1)
Read one ordinary cabinet, infer face contacts and thickness parameters, and change thickness while preserving its envelope.
**Independent Test**: A box cabinet's side thickness changes 18 to 20 mm; dependent horizontal panels shorten by 4 mm and remain touching.
**Acceptance Scenarios**:
1. Given touching opposite faces with overlapping area, reading produces a directed contact with geometry provenance.
2. Given separated or edge-only faces, reading does not invent contact.
3. Given a conflicting rule, preview reports the conflict and leaves geometry untouched.

### User Story 2 — ATT cabinet (Priority: P1)
Readable ATT formulas become rules in the same browser, retaining safe formula evaluation and source provenance.
**Independent Test**: Read the nested DC fixture; its five inputs and supported formulas remain effective after save/load and trial updates.
**Acceptance Scenarios**:
1. ATT takes precedence; inferred contacts are references until explicitly enabled.
2. Unsupported formulas stay visible; they are not executed or silently labelled supported.

### User Story 3 — Direct rule editing (Priority: P2)
Expand parts, parameters and rules inside the viewport; select a rule, edit face references, direction or gap, and add/remove it.
**Independent Test**: Click a visible face, assign it to a rule, save, and preview the resulting panel change.
**Acceptance Scenarios**:
1. Browser floats inside the continuous viewport and collapses independently.
2. Context palette distinguishes ATT, geometry inference and manual rules.
3. Export/editable parameter selection persists with a trial.

### Edge Cases
Conflicting cycles, missing parts, stretched parents, unsupported shapes, hidden panels, duplicate names, cancelling file dialogs, copied trials and legacy project files.

## Requirements
- FR-001: One versioned own rule system accepts geometry and ATT provenance.
- FR-002: Identify faces by part key, axis and side; names are display labels.
- FR-003: Infer area contact only within 0.15 mm; preserve the current envelope.
- FR-004: Support thickness anchors, fixed faces, contact/offset/alignment, between and centre rules for verified axis-aligned box panels.
- FR-005: Let users add/edit/delete constraints and inspect imported formulas without arbitrary code execution.
- FR-006: Reject conflicts, nonpositive dimensions and new intersections before model edits.
- FR-007: Reading and trials leave source geometry/attributes unchanged.
- FR-008: Keep six-face view cube and depth-tested rendering; distinguish both selected participants.
- FR-009: Preserve existing projects and cancel acknowledgement.

## Key Entities
Rule system, parameter, semantic face reference, directed constraint, formula engine, source snapshot, independent trial instance.

## Success Criteria
- SC-001: Single ordinary cabinet and readable DC both preview/apply thickness changes with unchanged envelope.
- SC-002: Floating browser branches and contextual editor work at 1000×650 and larger without horizontal overflow.
- SC-003: Scoped RuboCop, portable scenario tests and Electron UI/pixel checks pass.
- SC-004: Native VBO validates source isolation and reload; Undo is reported separately if unverified.

## Assumptions
This increment targets certified rectangular panels aligned to module axes. Arbitrary CAD solids, joint dynamics, generic sketch constraints and exploded-module recovery are outside this increment.
