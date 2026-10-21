# DC function coverage

Continue conversion of the authorized MH library by implementing missing DC
expression semantics in the portable engine. Read ATT first; never infer the
meaning of a random function name or execute opaque imported code.

The previous native report contains 37 converted / 227 source files. Preserve
those exports and original SKPs. SDK compilation success is a separate result
from native conversion and real parameter-edit verification.

Acceptance:
- Audit all 227 captured sources against current SHA-256, recording per-file
  compiler results and actual missing functions before and after changes.
- Support implicit original COPY=0 and explicit instance COPY indices while
  rejecting changes to copy count; never invent new instances.
- Resolve explicit names in the current/ancestor scope before global lookup;
  duplicate names outside the current scope remain errors.
- Accept numerical expressions whose ATT formula units are STRING only for
  non-length attributes; retain numerical output validation.
- Extend safe standard math functions with documented units, arities, domain
  checks, and shared evaluation in the editable parametric table.
- Preserve strict geometry/envelope checks, source identity, and the refusal of
  unknown ABF functions. Report unavailable native validation honestly.
- With the installed ABF loader available, intercept generated definitions as
  data before evaluation. Recognize complete nominal-parent reader templates,
  retain their verified mappings in the module, restore the original entry point
  on every exit, and never register/call imported Ruby or change permissions.
- Known unused readers with no attribute binding may be skipped only after
  matching their complete template. They never become supported functions.
- Convert and test newly supported files in native SketchUp when a VBO session
  is available, without changing source files or existing user geometry.
