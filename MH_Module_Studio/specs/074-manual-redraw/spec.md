# Manual Redraw command and bounded metadata work

Add Redraw beside Lưu SKP in compact Module Options. Hide actions when there is
no selected owned module/managed assembly; disable while parameter edits or
Redraw await acknowledgement. Send root PID and token; reject stale requests.
Add Extensions command MH Module Studio · Redraw for Preferences → Shortcuts.
Button and shortcut use one explicit native transaction, the saved rule/values
and current scaled geometry. Managed assemblies retain contacts and master T;
unrelated raw groups/DCs are not silently converted. Failed work aborts atomically.

Profiling the real open module measured about 94 ms loading/validating a rule,
313 ms calculating, 233 ms stamping metadata, versus sub-ms mesh application.
Optimize only the redraw metadata path: a prepared, validated plan may reuse
unchanged rule/value/instance/part metadata. New copied instances, changed values,
rules, names or binding identities take the existing full stamp path. Always
retain formula planning, copy independence and native geometry verification.

Acceptance: stale/current button routing and shortcut registration; compact UI
pending/error/selection behavior; native single/shared/linked redraw and Undo;
before/after timings, scoped RuboCop/tests, package and VBO reload.
