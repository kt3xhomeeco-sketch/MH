# MH SketchUp Plugins

Private monorepo containing MH SketchUp extensions and their top-level Ruby loaders. The Electron desktop companion lives in the separate `MH_Thongke_Desktop` repository. `MH_shared` holds code shared by the extensions.

For an issue, start with the root `AGENTS.md`, then inspect only the plugin folder named by the report and follow direct dependencies such as `MH_shared`. Each plugin's loader is at the repository root and usually has the same name as its folder.

Large generated libraries, build outputs, runtime caches and customer project snapshots are excluded. Add a targeted, sanitized context export when a CAD or SketchUp drawing is needed to reproduce an issue.
