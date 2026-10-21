# Feature Specification: Learn separate DC thickness parameters

**Created**: 2026-10-14
**Status**: Implemented; portable/UI gates and native read-only preview verified
**Input**: The user changed the back from 8 to 11 mm after changing carcass
thickness from 18.6 to 17.6 mm. The app incorrectly reports nonlinear top-panel
movement. The user also requires fixed settings such as an 18 mm back setback.

## User Scenarios & Testing

### User Story 1 - Read and select DC thickness parameters (Priority: P1)

The user sees separate carcass and back thickness values from the supplied DC,
selects which one to learn, and keeps all captured states.

**Why this priority**: A single default thickness cannot describe these samples.
**Independent Test**: Read the three supplied states and inspect both values.

**Acceptance Scenarios**:
1. Given states (18.6, 8), (17.6, 8), (17.6, 11), when read, both thicknesses
   are shown accurately, separately, in millimeters.
2. When only the back thickness changes in the latest state, automatic mode
   proposes the back as the parameter to learn; the user can choose the carcass.

### User Story 2 - Learn one parameter while holding others fixed (Priority: P1)

The user learns back thickness from states 2 and 3, or carcass thickness from
states 1 and 2. The app identifies which states were used and why others were
excluded. Fixed settings include back setback, groove engagement and placement.

**Why this priority**: Mixing independent changes produces a misleading error.
**Independent Test**: Analyze each parameter using the three supplied states.

**Acceptance Scenarios**:
1. Selecting the back uses 8 and 11 mm with carcass thickness held at 17.6 mm.
2. Selecting the carcass uses 18.6 and 17.6 mm with the back held at 8 mm.
3. If there is no pair where other settings stay fixed, the app reports which
   evidence is missing rather than claiming a valid independent rule.

### User Story 3 - Preview with the captured fixed settings (Priority: P2)

The user sees fixed settings such as back setback 18 mm. Changing a fixed
setting on a source DC invalidates that rule until new samples establish it.

**Independent Test**: Preview the back rule, then change the setback.
**Acceptance Scenarios**:
1. A back-thickness preview changes related panel depths and preserves the
   current outer dimensions and carcass thickness.
2. A different back setback on a source DC produces an explicit context error.

### Edge Cases

- Missing or opaque DC parameters fall back to existing geometry/manual mode.
- Mixed parameter changes without controlled pairs cannot prove independent rules.
- Unknown units or ambiguous thickness mapping are not silently converted.
- Hidden parts are not evidence for mapping a thickness parameter.
- Plain trials retain their captured rules; erased DC settings cannot be checked
  against live DC attributes, so existing geometric checks still apply.

## Requirements

### Functional Requirements

- **FR-001**: Read separate labeled thickness settings and validate values against
  the observed panel thicknesses before presenting converted values.
- **FR-002**: Allow parameter selection and show values for every captured state.
- **FR-003**: Learn using states where all other editable DC settings are fixed.
- **FR-004**: Show the selected parameter, used states and excluded states.
- **FR-005**: Display fixed settings, including back setback, and reject preview
  when an available source DC setting disagrees with the learned conditions.
- **FR-006**: Preserve captured states, original DC geometry and existing plain
  geometry workflows. Do not execute proprietary DC formulas.

### Key Entities

- Parameter: readable DC name, values, matched panels and observed units.
- Controlled sample group: states with matching other editable settings.
- Rule context: fixed settings and evidence used to learn one parameter.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Both supplied thickness settings display within 0.02 mm of the
  observed values in all three samples.
- **SC-002**: Each parameter learns from the expected two supplied states without
  the false nonlinear-top error.
- **SC-003**: Back preview preserves current outer dimensions within 0.15 mm and
  keeps the carcass thickness unchanged.
- **SC-004**: Changed fixed settings are rejected whenever source DC settings
  remain available; all captured states remain available after selection/reload.

## Assumptions

- This iteration learns one parameter at a time from controlled states; it does
  not infer arbitrary interacting formulas from three observations.
- The supplied DC exposes labels for its thickness settings. Units are accepted
  only when consistent with the observed geometry across captured states.
- Two thickness levels remain provisional; a third independent level validates
  behavior within the sampled range.
