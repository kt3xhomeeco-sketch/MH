# Per-module Library and ring icon views

Choose a thumbnail camera independently for each SKP: saved SKP image, 3D,
front, top, left, right, back or bottom. Library's selected-module sidebar has
Góc ảnh and Cập nhật icon. Per-icon camera editing is located only in Library;
HUD Settings retains size, position, Edit ordering and folder shortcuts. The ring
uses the image updated in Library. This supersedes the initial Settings editor.

Persist choices and custom PNGs in the library folder, surviving a restart.
Do not modify source SKP bytes, geometry, rules or placement fingerprints.
Changing one icon must leave other choices unchanged. An explicit Update also
regenerates the same view. Rendering/write errors preserve the last saved view
and restore controls for retry. Async thumbnail responses cannot restore stale
images or discard a view selection awaiting Update.

Views use the SKP definition's local axes: front looks from -Y, top from +Z,
left from -X and right from +X. No arbitrary camera editor is required here.

Acceptance: actual native PNGs differ by camera; settings survive reloading the
sidecar; GPU textures refresh; original objects/selection/camera/files remain
unchanged; Library/HUD controls, paging, errors and compact layout work in Chromium.
