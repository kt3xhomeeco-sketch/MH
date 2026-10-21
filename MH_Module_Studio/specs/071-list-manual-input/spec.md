# Referenced LIST manual input

DC LIST choices such as `Chiều Sâu Tự Nhập = hsxpei34m2` must switch from a
fixed preset to an editable referenced input. Recognize only direct root numeric
TEXTBOX references with the same unit; unknown expressions stay disabled.

Store the connection as an ordinary own Parametric variable formula. Renaming
symbols, SKP round trips, hidden input checkboxes and assembly member ownership
must retain it. Picking a numeric preset detaches the formula while retaining
the last manual input. Parametric exposes the referenced row; compact Options
shows an inline number beside/below the selected mode even if that input is not
separately ticked. Numeric edits still pass existing full geometry validation.

Acceptance: actual drawer fixture at a non-list depth, repeated preset/manual
switches, independent members, serialization/rename, malicious/missing/cyclic
references rejected, browser and native SketchUp round trip, full scoped gate.
