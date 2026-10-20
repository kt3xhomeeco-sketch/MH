# Repair legacy imported front references

Observed in model 2: host 534817, drawer 542370. The saved inside-import front
contact requests 100 mm from part:0006 (Len Nóc Trước). That residual part face
is 0.614041353 mm behind the host front envelope, so the actual front clearance
is 100.614041353 mm. This is a wrong persisted datum, not rounding tolerance.

Feature 077 already uses the host-front datum for new placements. Bring legacy
inside-import front contacts into that same policy on the next Assembly edit or
Redraw, keeping their displayed numeric clearance and converting signed normals.
Only the annotated import front slot qualifies. Manual, outside, other slots and
measurement-bound contacts remain unchanged. Do not add an offset correction.

Repair inside the existing transaction before solving, preserve other contacts,
exact T, atomic rollback and Undo. Verify the real selected geometry on independent
copies first; then repair its saved front reference with one undoable operation.
Do not write source SKP files. Check repeated gap changes and scaled/rotated frames.
