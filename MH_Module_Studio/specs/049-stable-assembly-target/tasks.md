# Completion and evidence

- [x] Reproduced the exact selected cluster: T17.6 depth600, T200 depth782.4,
  T17.6 depth600, T20 depth602.4. Evidence: outputs/repro-049.json.
- [x] Try free member dimensions first; remember an independent construction
  target. Restore probe sizes on typed no-freedom failure and retain the target
  during permitted fallback. Explicit Scale remains mandatory.
- [x] Preserve target metadata across assembly save/import; legacy payloads remain
  accepted. Contact/layout changes update affected construction frames.
- [x] Portable fit/sequence/fallback/probe/error/payload tests added. Scoped gate:
  144 Ruby files lint clean; 294 tests / 3236 assertions passed.
- [x] Native exact-source private copies: 157 checks passed, including T200 and
  subsequent T17.6/T20 at600, physical thicknesses, eight contacts, rollback,
  SKP roundtrip, explicit Scale660, derived-only fallback200 and shrink after
  reimport, and all original sources/selection retained. outputs/native-049.json.
- [x] Applied the requested600 depth to still-selected root463750 in one assembly
  transaction. Retained current values, width/height and all eight contacts;
  source library files unchanged. outputs/applied-049.json.
- [x] Ruby loaded through VBO and Options refreshed. RBZ packaged and verified.

The native QA pass used private copies. The final repair of the user's reported
cluster is separate and intentional. No new native Undo/Redo test is claimed.
