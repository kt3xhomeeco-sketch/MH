# Implementation plan

Use the actual 96-failure report in `Modul_studio/New folder/.conversion`, not
the older parent report. Exclude the 32 curved/DADX sources the user deferred.
Audit the other 64 sources on private model copies, abort each operation, retain
all source files and keep the original 131 verified exports.

Portable responsibilities:
- AxisRebase converts cardinally rotated ATT trees to equivalent calculation
  axes. It never edits native geometry and refuses non-cardinal/sheared frames.
- Program owns numeric units and flat-frame evaluation. Fresh programs opt into
  authoring units for untyped intermediate formulas; older payloads retain their
  existing interpretation. Symbolic and cell programs use the same policy.
- Parser accepts Unicode/spaced/digit group qualifiers without changing math or
  comparison precedence. Malformed source formulas remain errors.
- StaticGeometry explicitly identifies sources without geometric ATT or inputs;
  it does not fabricate T or discard an unsupported program.
- ThicknessSymbols retains its source equations on derived output axes instead
  of adding an old-envelope anchor during canonical T merging.

Native conversion reads direct root mesh, retains parent Components, bakes only
static root scale before definition export, applies the verified canonical T
plan, verifies saved SKP geometry after reload and publishes only verified files.
No source redraw or user-model edit is part of conversion.

Verification: regression fixtures from the actual failed vách and pano sources,
scope/parser/legacy/unit/flat/static tests, full RuboCop/Ruby gate, native repeated
parameter edits and Scale, actual SKP reload and source/model hash checks. Update
the destination only with verified staged outputs and produce a fresh remaining
failure report with actual counts, including deferred sources.
