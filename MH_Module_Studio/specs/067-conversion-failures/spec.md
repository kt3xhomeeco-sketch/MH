# Repair failed DC conversion

Work through the 96 failures of the 227-file conversion. Prioritize direct root
mesh and missing thickness recognition, then supported transforms and parser /
formula mismatches. Curved DCs and unknown DADX behavior remain excluded at the
user's request. Inspect source ATT/geometry on private aborted copies and record
actual blockers before changing evaluator semantics. Preserve exact thickness,
fixed dimensions, controls, copies and dependency references; do not silently
accept an unverified geometry fallback as successful ATT conversion.

Keep source SKPs unchanged. Retry into a separate verified output staging folder;
retain successful files already in the user's library. Report the actual number
fixed and remaining reasons, including any unsupported cases. Cover meaningful
portable regressions and native parameter/Scale/SKP roundtrips, then reload/package.
