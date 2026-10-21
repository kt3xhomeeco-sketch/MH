# Plan

1. Capture 227 SKP files through the installed SDK bridge; inventory expressions,
   metadata and existing failure reasons, plus hash every source before/after.
2. Inspect only metadata/loaded function structure; define the smallest verified
   translation whitelist and standard function support needed by this library.
3. Keep the native capture adapter separate from safe portable evaluation. Save
   mappings and translation provenance with rules and expose precise diagnostics.
4. Run library coverage and regression tests, native trials, VBO reload and RBZ.
