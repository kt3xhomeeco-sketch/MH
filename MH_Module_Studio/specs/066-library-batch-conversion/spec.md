# Batch DC conversion in Library

Provide Chuyển đổi DC hàng loạt inside the Library tab. The user selects source
and destination folders, starts conversion, sees progress/counts/per-file errors,
can stop before the next file and can open the destination as the Library.
Recurse source subfolders and retain relative SKP paths and filename-based names.
Use the fresh-read ATT compiler including custom numeric inputs (065). Unsupported
formulas must produce explicit per-file failures, never silently export geometry
fallbacks as equivalent parametric modules. Leave source SKPs and the live model,
selection and definitions untouched after each file's temporary operations.

Default behavior retains existing files. Cập nhật bản đã chuyển may replace only
an output whose known conversion-report signature still matches the target;
create and verify a backup first. Files edited since conversion remain intact.
Keep provenance through skip/retry/failure reports. Reject overlapping source and
destination trees. Persist full reports under destination/.conversion. A cancelled
folder picker or error must return usable controls. Do not start a full user-library
write automatically as part of installing/showing the feature.
