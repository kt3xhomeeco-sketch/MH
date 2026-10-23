# MH CAD2Module development
Scope all changes to this directory and ../MH_CAD2Module.rb. Apply Spec Kit and .agents/skills/karpathy-guidelines/SKILL.md. Read .specify/memory/constitution.md. Run scoped RuboCop/rubocop-sketchup, Ruby tests, pytest and native SketchUp verification. Preserve other plugins and user geometry. Runtime code must never launch AutoCAD. Library defaults to this app's library/ per user update; relocation must preserve history. Do not commit or switch branches merely for Spec Kit.

## Flow map maintenance
`FLOW_MAP.md` is the structural map of source paths, Ruby/Python modules/classes,
key functions and their responsibilities/call flow. Read it before tracing an
issue to locate the owning files, then verify current code. Do not turn it into a
symptom-to-diagnostic checklist or duplicate full specifications. **After every
code change, update `FLOW_MAP.md` in the same task** when paths, module ownership,
key functions, responsibilities or call flow change; otherwise add a dated note
that the structure was reviewed and unchanged. Keep feature requirements in
Spec Kit documents.
