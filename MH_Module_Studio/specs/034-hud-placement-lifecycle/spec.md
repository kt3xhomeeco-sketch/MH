# HUD placement lifecycle

User update supersedes the former return-to-icons-after-placement behavior.
After successful placement or Ctrl replacement, exit the Library HUD and restore
SketchUp shortcuts. Do not open Module Options automatically.

While a module is still being previewed, Esc cancels only that pending import
and returns to the same Library folder/filter/page so another model can be chosen.
No committed geometry is created or removed by canceling this preview. Esc while
browsing exits HUD. Space exits in either state. Held Esc must not cancel and then
immediately exit through keyboard autorepeat. Native Tool.onCancel follows the same
pending-cancel behavior.

Implementation: LibraryHUD owns cancel/reset and exit dispatch. Successful library
place calls finish; the importer/math/assembly calculation remains unchanged.
Remove only the automatic options popup, preserving explicitly opened dialogs.

Checks: portable Esc/reset/context/autorepeat/Space regressions, scoped RuboCop
and test gate, native pending cancel/choose again, normal import and Ctrl replace,
hook restoration, no options popup, original-model cleanup. Package and hot reload
through the existing VBO session after validation.
