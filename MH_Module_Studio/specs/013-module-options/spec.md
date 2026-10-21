# Floating module options

Standalone native modeless HtmlDialog, compact thumbnail/name and dense parameter
rows. No Studio viewport, Apply button, envelope or permanent status/footer.
Create model opens it; context/Extensions menus reopen it directly. Selection
changes and Undo/Redo follow the selected owned root, without an open Studio.

Tick is visibility only. Retain legacy serialized exported/exposed keys for
compatibility, but remove their edit/calculation permission effect. Unticked
inputs remain editable in authoring and participate in all computations; all
rules/values are stored with the root. Only ticked rows show in the small window.

Valid field changes auto apply after a short idle, Enter or blur. Guard selected
root PID, active model and rule/value revision against queued stale callbacks.
Reject invalid/formula-derived inputs; keep failed text to repair. Preserve
envelope, own formulas, source/copy independence, safe parser and transactions.
Custom scalar inputs recompute dependent geometric inputs. Expose errors only
when needed. Preserve selection across definition uniqueness. Repeated/copy
edits and own rule recapture must work. Scalar legacy rules get a clear diagnostic.
