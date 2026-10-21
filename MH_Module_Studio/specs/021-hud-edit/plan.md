# Plan

Keep radial drawing and placement in the existing Tool. Windows SketchUp routes
assigned shortcuts ahead of Tool.onKeyDown (SketchUp API issue 607). Add a small
x64 C helper using WH_GETMESSAGE on the current UI thread, filtering only the
model-window's owned keys. Queue events entirely in C, poll from a Ruby UI timer;
never call Ruby from native callbacks. Unhook on every exit/error. No global
hook, preference rewrite or injection into another process. Windows 2025 target.

The helper also reports physical pointer position/button state relative to the
viewport. Convert by UI.scale_factor. Use that to anchor cursor-mode HUD and to
complete a Library HtmlDialog drag across the native viewport. Use pointer
capture rather than native HTML5/OLE drag, which can switch SketchUp's Tool.
HTML sends only a module identifier, never an SKP path/URL/file drop. Session checks, the
catalog boundary check and a radial hit are required for a drop. Normal HTML
drag cancellation or an out-of-HUD release makes no changes.

Portable LibraryCatalog normalizes settings/order and calculates bounded layout.
Library owns persistence and stale-file checks; HUD owns transient drag state.
Add Edit in native Settings plus a Library shortcut to begin editing. Native
mouse drags reorder slots; Library drag inserts then shifts later icons. Search
does not rewrite order. Keep placement disabled in Edit. While editing, remember
the target HUD folder separately from Library browsing so cross-folder drags
do not change their destination; finishing Edit returns to that HUD folder.

References: https://github.com/SketchUp/api-issue-tracker/issues/607
https://learn.microsoft.com/en-us/windows/win32/winmsg/getmsgproc
https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw
