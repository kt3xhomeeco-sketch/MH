# Fast icon click and repeated import

Measured cabinet files spend20–30ms in SKP load,670–760ms validating/upgrading
embedded rules and80–90ms checking geometry on every icon selection. A legacy
Copies upgrade accounts for most rule time. Do not change its shared algorithm.

HUD icon click and Library placement launch read only the bounded display
snapshot, showing the drag preview without creating temporary geometry or
running Copies/rule migration. Preserve the full prepare API for developer
preflight callers. Assembly preview uses its outer box.

Before actual instance creation, fully validate the current embedded payload
and actual geometry. Cache successfully validated normalized data in memory,
keyed by the exact raw payload SHA256, returning private copies. Bound to16
items/8MiB; never cache failures or entity handles. File fingerprints still guard
the preview-to-placement interval. Model contents never rely on preview trust.
Repeated imports avoid repeating the same expensive upgrade; first real placement
of an uncached legacy file still pays full validation. No extra timer that blocks
pointer movement and no disk cache of executable/validated rule data.

Check preview latency, invalid bounds/formats, rejected full import after a valid
preview, changed raw payload/stale files, cache eviction/ownership, real native
placement geometry and independent copies, existing Copies/Scale behavior, live
reload, scoped gate and package.
