# Parametric name editing and saving

The module title and detail names must be editable in the Parametric window.
Detail renaming must not replace the parent title with a canonical ATT name such
as CotTrai. Renaming is a display-metadata edit of the same document, not a new
snapshot/module selection. Pending variable drafts must remain available.

Support a file-only draft with no live captured root. Save its renamed file from
the original SKP geometry, verifying the original signature and keeping the old
file. Never rewrite canonical ATT name references to implement display naming.

One click on Save while a name input is active must commit the name first and
then save exactly once after acknowledgement. Rename failure must leave the
editors and Save usable, preserve the rejected text for correction and cancel
the queued save. Show a visible input border to make both name editors clear.

Check actual SketchUp controller rename/save/reopen/import/parameter editing,
browser blur/Enter/Save ordering and dirty-variable preservation, invalid-name
recovery, source isolation, scoped RuboCop/tests, live dialog reload and package.
