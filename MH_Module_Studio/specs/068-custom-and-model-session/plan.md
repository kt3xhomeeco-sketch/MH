# Implementation

- Keep the custom attribute inventory separate from geometry control discovery.
  Existing verified inputs retain their behavior. Other custom strings, hidden
  data and derived attributes become readonly parameters with original keys and
  original formula evidence. Evaluate supported numeric derived fields through
  the existing numeric Program; do not execute imported behavior/string code.
- Preserve original keys on new fallback rows; leave existing saved symbols and
  renames intact. Supplement old formula payloads in memory when reading,
  importing or displaying them, and persist through the existing explicit save.
- Support independent, unexposed declared parent dimensions even when Access
  metadata is absent, using the same transitive dependency proof as NONE/VIEW.
  Explicit TEXTBOX dimensions remain inputs.
- Filter missing module roots at the assembly record adapter. Do not mistake a
  locked object or missing panel face for deletion, and do not modify stored
  records while drawing or reading. The filtered view also serves solve/export.
- New/Open must force a context reset despite equal Model objects. Cancel old
  read timers, invalidate callback generations and native handles, rebind model
  observers and clear option queues by session as well as root PID.

Validate the actual drawer front, older payload upgrade and same-symbol module
isolation, deletion/Undo, obsolete async responses and deleted Model handles.
Use Chromium for readonly formula display/checkbox serialization and option
queue cancellation, the full Ruby/RuboCop gate, and native File New/import/edit
checks. Keep source files and the user's geometry unchanged.
