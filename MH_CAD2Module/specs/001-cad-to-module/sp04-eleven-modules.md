# SP04 module membership correction — 2026-10-18

The user explicitly counts both long lower units and the central wall as modules. This supersedes the earlier eight-module classification. Keep M01–M08 unchanged; add M09 below M01/M02, M10 below M03/M04, and M11 for the central wall assembly.

M09 and M10 each measure 1698 × 360 × 250 mm at [42,0,0] and [3424,0,0]. These use the existing measured common-base reference bounds. They become solid replacement proxies and are no longer duplicated as wire base parts.

M11 contains all 23 existing wall panels/trims with local coordinates, including the main 18 mm slabs. Its complete assembly envelope is 1600 × 48 × 2500 mm at [1782,312,0]; 48 mm includes front trim, slab and rear trim. The actual 18 mm slab geometry must remain unchanged. Grouping does not create a filled 48 mm slab. A replacement template acts on this complete module and its nested parts.

Runtime builds structured modules from nested panel parts and captures actual child geometry in correction snapshots. Experience replay validates nested dimensions and restores the complete eleven-module layout only for matching signature/parser 0.2.3. Original model placement, label centre X=25000, original eight module entities and all wall piece geometry must remain unchanged. Source DWG and previous history remain immutable.

Validation: portable CAD regression verifies eleven modules, base ownership, local wall coordinates and no module overlap. Native temporary build verifies eleven modules with 23 nested wall parts and correction round-trip, then restores original roots. Actual targeted repair reuses existing wall definitions/materials, archives before/after JSON and SKP, and checks all wall world bounds and original module state. Final release gates include pytest, Ruby tests, scoped RuboCop, native UI module count and exact-signature replay.

Results: 40 pytest cases passed, 5 Ruby cases / 16 assertions passed, all 12 scoped runtime files passed RuboCop. Native build/correction round-trip passed, and the live repair preserved original module state and all wall piece world bounds. Exact-signature parser 0.2.3 replay restored all eleven modules with 23 nested wall parts. Headless UI rendered eleven module rows and counted the wall once, without script errors. After the product was observed exploded into loose modules, final read-only verification confirmed all eleven world bounds and the 23 nested wall parts; the loose arrangement was preserved. Package: outputs/MH_CAD2Module-0.2.3.rbz.
