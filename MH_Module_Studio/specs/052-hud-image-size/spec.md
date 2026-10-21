# Image size inside HUD circles

HUD Settings has two separate controls: Cỡ vòng HUD (existing 24–140px) and
Ảnh trong vòng (25–250%, default100%). The latter changes all module pictures
without changing circle positions, sizes or hit areas. Changes apply immediately
and persist across sessions. View selection remains in Library.

Below100%, shrink the image around its center, leaving the circle background
visible. Above100%, zoom centered UVs while clipping to the original circle.
Preserve image aspect and do not repeat/wrap texture coordinates, regenerate
source thumbnails, change files or modify model geometry.

Acceptance: slider dispatch/acknowledgement, bounds/defaults and preference
roundtrip; native triangle radius/UV checks at25/50/100/200/250%, including tall
and wide images, constant HUD layout; live settings/reload; scoped gate/package.
