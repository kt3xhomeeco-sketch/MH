# Tasks

- [x] T001 Record approved mockup and renderer behavior.
- [x] T002 Implement depth-correct viewer and camera controls.
- [x] T003 Rebuild layout and compact/collapsible information panels.
- [x] T004 Validate rendering pixels, responsive UI and existing workflows.
- [x] T005 Reload through VBO, verify native UI and refresh RBZ.

Validation: 80 Ruby tests / 455 assertions, scoped RuboCop without offenses,
68 UI checks and pixel-level depth tests on WebGL and software fallback passed.
Pixel tests cover draw-order independence in seven camera views, hidden rear edges,
opaque teal highlights and explicit X-ray. Native PID8120 reported a 1512 x 726
viewport, 24-bit depth buffer, six displayed parts, three parameter columns,
collapsed detail panels, no overflow and no GL error. UI reload preserved drafts;
no geometry changes were required. Runtime RBZ contains 13 entries including the
local viewer, no developer dependencies.

User correction: the orientation cube now has all six projected faces, renders
visible faces according to the model camera and updates while orbiting. Named
views include front/back/left/right/top/bottom. Cube click, keyboard activation
and real pointer-capture drag are tested; dragging reveals hidden faces and
rotates the main model. Reload preserves camera, scene, accordions and drafts.
