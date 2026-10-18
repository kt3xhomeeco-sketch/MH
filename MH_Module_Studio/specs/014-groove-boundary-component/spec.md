# Groove boundary and generated module structure

An ATT-driven panel may temporarily touch the module envelope. That contact must
not become a permanent geometric constraint which overrides its next ATT value.
Repeated groove edits must leave geometry consistent with saved parameters.
Reject plans changing the envelope before touching geometry or saved values.

Generated modules have a component parent and group panel children. Existing
owned modules remain editable. Repair the reported generated module only after
backing it up and proving the mismatch came from the accidental exterior lock;
preserve its placement, parameter values, rules and panel identities.

Acceptance: groove 8 → 20 → 0 → 8 with board thickness 20, followed by another
parameter edit; excessive groove rejection leaves a subsequent valid edit usable;
ordinary contact/manual constraints remain enforced; native component/group
structure, copy independence and rollback; scoped RuboCop and portable tests.
