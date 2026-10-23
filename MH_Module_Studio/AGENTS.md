# MH Module Studio — focused investigation

Scope: this project directory and `../MH_Module_Studio.rb`. Other extensions
and the parent `.rubocop.yml` are separate projects. User instructions prevail.

## Reading order

Start with the reported symptom, expected result and reproduction steps.
1. [FEATURE_MAP.md](FEATURE_MAP.md): find the behavior and its owning file(s).
2. [FLOW_MAP.md](FLOW_MAP.md): read only the relevant call path.
3. [ARCHITECTURE.md](ARCHITECTURE.md): only relevant **Ownership** rows when
   responsibility is unclear; boundary rules only when that boundary is implicated.
4. [BUG_REPORT.md](BUG_REPORT.md): use the template for missing evidence;
   do not demand a completed template when the supplied report is sufficient.

Do not preload CHANGELOG.md, full README/specs, development skills, Spec Kit or
build/branch workflows for a read-only investigation. Open history only for an
explicit regression/migration question and only the implicated feature entry.

## Scope and evidence

- Before attributing a live bug to this checkout, confirm the path/version of
  the code SketchUp actually loaded. Use the implicated method's `source_location`
  or equivalent runtime evidence; do not assume the current folder is loaded.
  If unavailable, report the running-copy check as unverified.
- Codex owns triage and chooses the initial file list and reading size from the
  symptom, stack trace and maps. Five relevant source files / about 12,000
  characters of excerpts is the default initial ceiling, not a required quota.
  Read fewer when the direct path is clear. Search exact errors, commands,
  callbacks or symbols with `rg`; maps locate code, but verify claims against
  current source.
- If tracing shows that another specific file is on the direct call/data path,
  Codex may extend the file/character ceiling for this task without asking the
  user each time. Record briefly why that file is needed, inspect only that
  evidence, and keep following direct dependencies; never scan the whole project.
- Work order for an assigned fix: Codex scopes the symptom and chooses the
  relevant files; DeepSeek reviews that scope and reports cause, file/line
  evidence and a proposed fix. Every claim about the cause or proposed fix must
  point to observed evidence in the current source, runtime, reproduction or a
  test; do not present guesses or plausible explanations as findings. Separate
  confirmed facts from hypotheses, and do not authorize implementation based
  only on an unverified hypothesis. If evidence is insufficient, Codex names the
  exact unresolved question and the smallest additional file, runtime fact or
  reproduction detail needed, then sends a focused follow-up review within the
  same task. Repeat this evidence-gathering loop until Codex has enough verified
  evidence to establish the cause, edit scope and acceptance checks; do not
  guess or broaden into unrelated files. Codex supplies the implementation plan,
  scope and explicit pass/fail criteria. DeepSeek implements, runs relevant tests
  and checks the reported behavior in the existing SketchUp/VBO session, then
  reports actual results and evidence against each criterion. Codex reviews the
  diff and evidence and sends missing or contradictory evidence back to DeepSeek
  as a focused continuation within the authorized budget. Codex does not take over
  implementation or routine verification merely because a worker failed or its
  report is incomplete. Additional independent checks are appropriate when the
  supplied evidence needs validation; any direct takeover requires user direction.
  Do not claim a test passed unless it was actually run and its result checked.
  If SketchUp or another required environment is unavailable, say which behavior
  remains unverified; never substitute reasoning or a code read for a runtime
  test. Give the user one final report; do not pause for
  approval between diagnosis, follow-up investigation, plan, implementation and
  verification. A request to fix an issue authorizes this full cycle within the
  described scope.
- Keep review-only requests read-only. For a fix request, use judgment on routine
  implementation choices without asking. Ask only when a material ambiguity
  blocks a safe decision or required evidence/action is available only from the
  user; continue independent work while waiting when possible.
- Incomplete evidence is a follow-up task, not a passing result. Continue with
  DeepSeek while authorized calls remain. If a task has ended, resume or start a
  narrowly scoped continuation only when the user has authorized continuation;
  carry forward verified results and exact blockers instead of repeating triage.
  Call caps remain hard: do not raise them, switch models or launch replacement
  workers automatically at the cap. Obtain an explicit additional budget when
  needed and never interpret a bounded extension as unlimited authorization.
  For execution, permission or tool failures, identify and resolve the execution
  blocker before spending more model calls; extra calls alone are not a fix.
- Read-only investigation changes no source, files or model state. Implement only
  when assigned; existing authorization to fix is sufficient, with no extra approval.
- Skip generated output, dependencies, backups, caches, unrelated logs and sibling
  projects unless the specific symptom points there. Compare copies only as needed
  to resolve the running-copy question; never bulk-read packaged/staged code.
- Never send raw SKP/DWG or full geometry dumps to a model. Request a targeted
  collector export with IDs, units, frame, transforms and expected/actual placement.
- Delegated DeepSeek tasks default to `deepseek-flash`, `effort=none`, hard caps
  **4 model calls for review / 8 for coding or execution-based verification**.
  A user-approved extension applies only to the stated task and budget; it does
  not change these defaults. Reserve a final model call for a concise handoff
  before the cap, with partial evidence if necessary. At the cap or auth/credit
  failure, report the exact blocker and completed checks; do not silently take
  over, exceed the cap or restart. Never include keys in reports or prompts.
- Every verification handoff must include commands actually run, exit codes and
  test counts, requested versus measured native dimensions with units and frame,
  runtime source/version evidence, per-criterion pass/fail/unverified status,
  artifacts or relevant output, files read/changed and remaining uncertainty.
  A successful process exit or worker summary alone does not establish a pass.
  Use independent copies for native QA, preserve the real model, selection,
  camera and preferences, and verify cleanup. Do not open SketchUp or files
  automatically. Distinguish deterministic native geometry/adapter tests from
  actual mouse interaction and visual highlight verification.
- Report conclusion, verified file:line and test/runtime evidence, proposed change,
  files read/changed, actual checks and their outcomes, uncertainty and reached
  scope/call caps. Portable checks do not
  establish SketchUp-native geometry, Undo, reload or UI behavior.

## Assigned implementation only

Read [DEVELOPMENT.md](DEVELOPMENT.md) for development rules, relevant skills,
checks and map maintenance. Read only task-relevant specs/constitution sections.
This file is the short project entrypoint; DEVELOPMENT.md holds the detailed rules.
