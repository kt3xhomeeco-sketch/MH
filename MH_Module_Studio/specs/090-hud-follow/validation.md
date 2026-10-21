# Validation

- Passed: `bundle exec ruby test/hud_free_test.rb` (12 tests, 80 assertions).
- Passed: `bundle exec ruby tools/check.rb` (462 tests, 4,878 assertions;
  RuboCop inspected 252 files with no offenses).
- Browser smoke check passed for grouped options, mixed input, automatic apply,
  queued edits, and selection switching.
- In SketchUp, run `NativeHUDFreeCheck.run` from a private in-memory board.
  Confirm free-icon offsets survive four viewport-edge positions, then confirm
  the model, selection, and saved preferences match their initial state. This
  native check was not run because SketchUp was not running during this turn.
