# Plan

Extract the existing developer converter into the production DCLibraryConversion
adapter with configurable folders, per-file native transactions, current compiler,
bounded folder scan, progress/cancel and verified-update backups. Keep the old
developer class as a compatibility wrapper so normalization has one owner.
LibraryConversionUI owns settings/actions and compact progress publication;
Library includes it. The Library inline panel owns its own control state and shows
the last 100 rows, with full reports on disk. Convert one file per UI timer tick;
do not execute native SketchUp API on background threads.

Verify controller lifecycle/cancel/disjoint roots in Ruby; real-file conversion,
custom parameters, malformed-file continuation, provenance across skipped runs,
backup updates, edited-file protection and unchanged live-model state via VBO.
Chromium verifies controls, progress/cancel/retry, escaped file diagnostics and
responsive layout, plus 065's actual Xuong row/cell. Run existing Library browser
checks, scoped Ruby/RuboCop, show the live Library panel and package the RBZ.
