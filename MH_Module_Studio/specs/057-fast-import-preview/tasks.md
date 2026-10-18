# Tasks

- [x] Profile real cabinet icon preparation and locate repeated Copies migration.
- [x] Add bounded display-only preview and import-specific private payload cache.
- [x] Keep full source/geometry validation at actual creation and existing prepare.
- [x] Portable tests: display bounds/format rejection, assembly preview, private
  content-keyed cache, item/byte eviction, uncached failures, HUD preview dispatch
  and unchanged legacy dynamic Copies planning after cache serialization.
- [x] Scoped gate:154 Ruby files clean;307 tests /3836 assertions passed.
  Browser Library/HUD workflows remain passing.
- [x] Native cabinet files: preview27–31ms, first real build0.98–1.03s,
  cached build0.38–0.40s. Actual HUD choose method29ms. Before: icon preflight
  alone0.76–0.87s. Evidence: native-057.json and live-057.json.
- [x] Native geometry validation ran on all builds; cached rules rejected an SKP
  with modified actual geometry, and stale file preview was rejected. Independent
  definitions, original source bytes, user roots and selection retained.
- [x] Ruby reloaded in the live VBO session without replacing the user's active
  Tool/pending import. Runtime RBZ rebuilt and manifest/archive verified.

First actual placement of an uncached legacy payload still pays full validation;
no claim that all first-time model creation is29ms. Timings above distinguish
icon preview from real instance creation.
