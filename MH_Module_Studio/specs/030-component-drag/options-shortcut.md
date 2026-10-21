# Module Options shortcut

Request: expose Thông số module as a SketchUp command for user-assigned shortcuts.

Cause: registration checked Sketchup.add_context_menu_handler, but that API belongs
to UI. The condition skipped both the Extensions entry and the contextual entry.

Change: register a retained UI::Command with the existing intended menu name,
tooltip and shortcut instructions. Use UI.add_context_menu_handler. Preserve the
registration guard to avoid duplicate entries on reload. No default key assigned.

Acceptance: native command/menu registration succeeds, command opens the existing
compact ModuleOptions dialog, reload retains the same command, model unchanged.
Run scoped RuboCop/Ruby gate and rebuild RBZ.

Verified: 80 Ruby files clean; 189 tests / 2320 assertions passed. Existing
SketchUp PID 19224 reloaded through VBO. The registered command callback opened
ModuleOptions; reloading again retained the same command without duplicate
registration. Original entities, transforms, definitions, selection and modified
flag were retained. RBZ rebuilt. Physical key binding remains user-configurable;
no key was assigned or existing shortcut overwritten.
