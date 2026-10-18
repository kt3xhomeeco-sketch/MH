# Plan

- Keep the existing per-module numeric ATT/geometry engines unchanged.
- AssemblyMath supplies a typed fit failure. AssemblyEnvelope restores probe
  dimensions, fits the saved target first and applies only proven fallback axes.
- Assembly transactions remember a construction target per independent wrapper,
  after successful verification; retain one atomic operation and copy isolation.
  Explicit envelope requests belong only to scopes in that transaction.
- Save/load the target as optional assembly payload metadata, separate from the
  measured snapshot envelope. Reset it for explicit parent Scale and link/layout
  changes, not routine parameter edits.
- Verify with portable simulated fit/fallback/error tests and opt-in native QA
  on private source copies, then repair the still-selected reported instance.
