# Window request contract

Shared JSON request callback on both HtmlDialogs, max 1 MB. Both receive published
state/errors; no cross-window mutable JavaScript globals.

- ready: surface=parametric acknowledges child loading and applies queued focus.
- open_parametric: optional parameter_key opens/reuses child and focuses input.
- save_variables: rule_id, snapshot_id, revision, variables; validate a copy,
  publish only on success, increment revision, discard stale plan.
- preview/trial/update: parametric=true, rule_id, snapshot_id; resolve committed
  own variables into existing editable/exposed targets. Runtime guardrails apply.
- save: existing atomic project write; cancellation publishes unchanged state.

Rejected edits leave committed rule intact and preserve the child draft. Switching
the source module replaces drafts. Closing/reopening preserves committed rules;
unapplied drafts are browser state only. Preview requires applying the draft first.
