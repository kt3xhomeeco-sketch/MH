> Read this file only for assigned implementation, refactoring, feature design or
> development-tooling work. Read-only bug investigations start in [AGENTS.md](AGENTS.md)
> and do not load Spec Kit, skills or build instructions by default.
>
> The original development instructions are preserved below. User instructions
> and the scope of the assigned task take precedence.

# MH Module Studio development

Scope changes to this directory and its sibling loader `../MH_Module_Studio.rb`.
Other extensions and the parent `.rubocop.yml` belong to separate projects.

Spec Kit is initialized here, even though Git's repository root is Plugins/.
Run its scripts from this directory; use `tools/specify.ps1` for the pinned CLI.
Read `.specify/memory/constitution.md` before feature work. The installed Codex
workflows are in `.agents/skills/speckit-*`. User instructions take precedence.
Do not create branches or publish issues merely to run a specification workflow.

For implementation, review and refactoring, read and apply
`.agents/skills/karpathy-guidelines/SKILL.md`. State material assumptions, choose
the simplest implementation that meets the request, keep edits scoped, and
define observable acceptance checks before changing behavior. Spec Kit records
requirements and tasks; these guidelines guide coding decisions; RuboCop and
relevant tests verify the result.

Apply the guidelines proportionately. User instructions and this project's
constitution take precedence. Clarify material unknowns while continuing
independent authorized work; do not add approval steps or stop for routine
implementation choices. Add meaningful regression tests for behavior changes,
not tests that merely repeat low-impact edits. The pinned source and update
procedure are documented in TOOLING.md.

Use `bundle exec ruby tools/check.rb` for the scoped RuboCop and Ruby test gate.
It stages the Ruby files declared in `runtime_manifest.json` in `outputs/lint-source` to validate package
structure without scanning the other extensions. Never edit those staged copies;
fix the original sources and rerun the command. Update the shared explicit runtime
manifest when adding production files. Read ARCHITECTURE.md for component ownership;
portable calculation files must not load host adapters or reopen numeric Program
to add feature-specific methods. Preserve boundary and cross-feature tests.

Keep developer tooling out of RBZ packages. Native SketchUp checks (geometry,
copy independence, Undo, reload) require actual SketchUp execution. Portable tests
and UI smoke checks alone do not establish that native checks passed.

VBO reuses its top-level Ruby eval binding. Define persistent dialog callbacks in
methods with method-local arguments; never capture top-level eval variables that
later probes can reassign. Replace old developer callback relays when reloading UI.

## Flow map maintenance

`FLOW_MAP.md` is the structural map of source paths, Ruby modules/classes, key
functions and their responsibilities/call flow. Read it before tracing an issue
to locate the owning files, then verify current code. Do not turn it into a
symptom-to-diagnostic checklist or duplicate full specifications. **After every
code change, update `FLOW_MAP.md` in the same task** when paths, module ownership,
key functions, responsibilities or call flow change; otherwise add a dated note
that the structure was reviewed and unchanged.
