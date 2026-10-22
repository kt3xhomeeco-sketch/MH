# Validation

- Passed: `bundle exec ruby test/hud_free_test.rb` (12 tests, 80 assertions).
- Passed: `bundle exec ruby tools/check.rb` (462 tests, 4,878 assertions;
  RuboCop inspected 252 files with no offenses).
- Browser smoke check passed for grouped options, mixed input, automatic apply,
  queued edits, and selection switching.
- Passed in the running SketchUp session: `NativeHUDFreeCheck.run` (18 checks),
  including four viewport-edge positions. Its report confirms model geometry,
  selection, and saved preferences were retained.
