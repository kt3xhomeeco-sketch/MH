# Stable assembly construction target

Selected assembly 463750 has three members and eight contacts. T17.6 gives depth
600, T20 gives 602.4, T200 gives 782.4. Feature 047 followed door output immediately
instead of using the cabinet's free depth. Feature 048's independent single-module
construction inputs must remain intact.

Priority: exact physical T / fixed ATT dimensions / saved contacts, then try free
member dimensions to retain the requested aggregate. Only measured no-freedom or
nonpositive-size correction permits fallback on proven output axes. Retain the
independent target through fallback growth/shrink and SKP save/import. Do not
convert a geometry/formula failure into successful fallback. Parent Scale defines
a new mandatory target; explicit contact/layout edits establish their new bounds.

The user explicitly identifies depth 600 for the existing drifted assembly.
Repair that selected instance to 600 while retaining its current T, all other
dimensions and local back endpoint. Do not change source library files.

Acceptance: private exact-source copy through T17.6/200/17.6/20 and further edits,
physical thickness of every driver, eight contacts, safe failed update rollback,
SKP roundtrip, native Scale660 followed by T edits, derived-only fallback, source
isolation, scoped lint/tests and RBZ. Report native and portable evidence separately.
