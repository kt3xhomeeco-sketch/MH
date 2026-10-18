# Plan

- LibraryCatalog validates persisted hud_image_zoom; Library accepts the setting.
- Existing thumbnail renderer shrinks its triangle fan for values below100 and
  reduces its centered UV window for values above100. Border/hit layout unchanged.
- HUD Settings labels circle size clearly and adds the percent slider. No new
  files or per-module camera changes in the thumbnail cache.
- Verify normalizer/persistence, browser events and native renderer geometry;
  refresh live Settings preserving folder drafts and package runtime.
