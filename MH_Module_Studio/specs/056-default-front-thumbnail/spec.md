# Front-facing module icons by default

Library/HUD modules without a saved individual view use Mặt đứng (front, local
-Y). Preserve explicitly selected views, including saved-SKP/3D/top. Existing
unconfigured modules also adopt the new default; this is not a bulk rewrite of
their individual settings or source files. Default front cache keys differ from
old saved-SKP keys so stale original pictures cannot be treated as front images.

Keep feature055's fast open: cold HUD shows the inexpensive saved-SKP thumbnail
temporarily; its queued image job generates the desired front camera before
enhancing/caching the final image. Do not cache the preview as the final front
image. Warm HUD opens use the completed cache normally. Library renders the
actual desired view. Check default/explicit choices, cold preview/final cache,
native camera/source isolation, scoped gate and live reload/package.
