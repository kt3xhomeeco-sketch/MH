# MH Superimp development

Scope changes to this app only. `FLOW_MAP.md` is the structural map of source
paths, modules/classes, key functions and their responsibilities/call flow. Read
it before investigating a reported issue to find the owning code, then inspect
only the relevant path. Do not turn it into a symptom-to-diagnostic checklist.
Do not inspect
`src/import_list.xlsx` as code or send its contents to a model; it is application
data. Preserve SketchUp model geometry and user settings. Verify Ruby syntax and
focused behavior; native import/placement behavior must be checked in SketchUp.

## Flow map maintenance

**After every code change, update `FLOW_MAP.md` in the same task** when paths,
module ownership, key functions, responsibilities or call flow change; otherwise
add a dated note that the structure was reviewed and unchanged. Keep the map
concise; put detailed requirements in a separate spec/plan.
