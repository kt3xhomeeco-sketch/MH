# Decisions

- Use a retained modeless SketchUp HtmlDialog, not window.open in the embedded
  page. Recreate callbacks after close: the native API clears them when a dialog
  closes. Source: https://ruby.sketchup.com/UI/HtmlDialog.html
- Categories follow predefined DC attributes (dimensions, coordinates, rotation,
  Hidden, Copies/Copy, information, material and onClick), alongside own scalar
  and text variables. Category coverage does not expand supported geometry
  operations. Source:
  https://help.sketchup.com/en/sketchup/dynamic-component-predefined-attributes
- Keep the current ATT engine immutable; own variable IDs and aliases bind to
  existing parameter keys. Safe own scalar formulas reuse the restricted parser
  and arithmetic. Do not evaluate imported behavior scripts.
- Six displayed part fields are bounds measured in the module frame. Original
  ATT formulas can live on containing groups; show their scope and ID rather than
  presenting their local coordinates as global module coordinates.
- Initial VBO instance (PID 8120, port 58233) was offline. A new current instance
  appeared (PID 31852, port 7891) and was verified before native execution. Native
  dialog edit/reopen checks passed. A temporary cabinet reconstructed from cached
  DC data verified own variables through trial/update/export/re-read, then all
  exact owned entities and definitions were removed. Undo remains unestablished.
- Real HtmlDialog close callbacks are asynchronous. Guard callbacks by dialog
  identity so a late callback from an old dialog cannot clear its replacement;
  isolated regression tests cover delayed main and child callbacks.
