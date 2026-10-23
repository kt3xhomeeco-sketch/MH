# MH AI Context Exporter

Two small collectors create a focused context package from the area or objects you choose. They do not modify the SketchUp model or CAD drawing and do not send files to an AI service.

## SketchUp 2025

The extension is installed in the current SketchUp Plugins folder. Restart SketchUp, select up to 50 objects related to the issue, then run **Extensions → MH · Xuất ngữ cảnh lỗi cho AI…**. Enter the error, expected result, actual result and related DWG/DXF name if known. Choose the JSON output path.

The exporter writes a `.json`, a human-readable `.md`, and a PNG of the current viewport beside the selected JSON path. It records only the current selection and active edit path, object identifiers/names/tags, parent-context bounds, instance transforms, selected edge/face details, units and camera. It does not move the camera or traverse the whole model. Face vertex data is capped at 64 vertices; selections over 50 objects are rejected so the report stays focused.

## AutoCAD and ZWCAD

Load `MH_AI_ContextExporter_CAD.lsp` with `APPLOAD`, then run `MHCTX`. Specify two opposite corners around the region you want AI to understand. The collector includes every entity crossing or inside that rectangle, up to 200 entities. You can describe what AI should inspect and add expected/uncertain details; these prompts are optional. Choose the JSON output path. The LISP command writes a `.json` and `.md` beside that path. It records entity handles, types, layers, owner handles, filtered DXF geometry fields, drawing units/UCS and WCS bounds when the host exposes them through COM. A per-entity geometry limit marks truncated records explicitly.

Block references are reported with their insertion data and bounds; block definition geometry and external-reference contents are not expanded in this first version. If the region contains blocks or xrefs whose internal contents matter, that information will be incomplete until a block-aware collector is added. The report states this limitation.

To make the command available after restarting CAD, add the LSP file to the host's Startup Suite (or the equivalent trusted startup mechanism). It is intentionally not auto-loaded or written into CAD startup settings by this package.

The same AutoLISP source is intended for both AutoCAD and ZWCAD. COM bounding boxes depend on the host and entity type; when unavailable, the report leaves bounds as `null` while preserving the selected entity's DXF data. The current implementation has not yet been loaded in either CAD host, so verify the command in a drawing copy before relying on it for a diagnosis.

## Shared package

Both collectors use schema `mh-ai-error-context/v1`. For CAD, draw the rectangle tightly around the region of interest; for SketchUp, select relevant objects and nearby reference geometry. Attach the JSON, Markdown summary and PNG if generated. Check the files for sensitive drawing/model names before sharing them.
