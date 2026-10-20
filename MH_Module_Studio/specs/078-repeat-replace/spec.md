# Continuous and selection Replace

Continue replacing after a successful Ctrl placement without reopening HUD.
Esc cancels replacement back to Library; another Esc exits. Ordinary and Shift
placements keep their approved single-placement behavior. Preserve click-time
modifier routing, source rules/T/fixed dimensions and actual target envelope.

Confirmed: selecting a Library sample immediately replaces all preselected
groups/components, in both the tab and HUD. No Ctrl needed for that workflow.
Validate selection/model freshness and locked objects. Batch replacement uses a
single transaction: all requested replacements succeed or all roll back; one Undo
restores the batch. Preserve independent instances and links where they map.

Investigate external Replace inheritance and measure native replacement costs
before optimizing. Reuse validated work where inputs are identical, but do not
remove geometry, ATT/T, link or stale-file checks. Native performance claims need
actual SketchUp measurements. Do not modify other plugins or source SKP files.

Confirmed external command: SketchUp Replace Component. Owned definitions carry
a reusable rule/value seed without live root identity. A separate observer adopts
native-created instances or changed definitions after the native transaction,
copies privately and redraws source rules/T at the requested dimensions. Undo
includes adoption. Ordinary imports without a recognized seed/payload stay ordinary.
