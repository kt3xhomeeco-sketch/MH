# SP01 upper-left auxiliary trims — 2026-10-18

User correction: the two 24 mm faces beside the upper-left module are auxiliary trims belonging to that module. They must not enlarge its replacement box or become extra modules.

Measured evidence in 2.dwg: bay envelope 729 mm; DF65D/DF65B are the two full-height 18 mm inner sides; DF65A/DF65C close its 645 mm inner width. Actual carcass width is 681 mm. The matching vertical section DF5D6/DF5E0/DF5E1/DF5DE establishes depth 582 mm and front setback 18 mm. Height remains 443 mm, floor elevation 2200 mm.

Implementation: retain plan bay allocation, refine only a separately closed carcass of the same height, and require a unique section proof for depth/front placement. Retain two wire auxiliary references, each 24 × 18 × 443 mm, at [0,0,2200] and [705,0,2200], owned by M03. Carcass is [681,582,443] at [24,18,2200]. Retain other modules and overall width 2255 mm, centred on SP01. Stock 18 mm uses the user's existing turned-trim rule; 24 mm remains measured face width.

Verification: actual CAD regression and missing-cap/side/back negative cases; portable Ruby checks; scoped RuboCop; native SketchUp temporary build/Undo, auxiliary ownership, independent snapshots and targeted live correction. Ordinary user geometry must remain untouched. Before/after JSON and SKP archive this explicit correction; reusable experience is restricted to the exact source geometry signature and parser 0.2.1.

Results: 35 pytest cases passed; 5 Ruby cases / 16 assertions passed; all 12 runtime Ruby files passed scoped RuboCop. Native temporary construction and Undo passed, leaving original roots unchanged. Targeted repair kept entity 904853, all other module entities, external trim and labels unchanged; centre X remains 1000 mm. HtmlDialog shows four modules, zero errors, working check-view toggle and no overflow. Exact-signature replay accepted correction event 6f88ed92-6f94-e44d-51f8-72c7a457abc0 with three trim references, including two owned by M03. Package: outputs/MH_CAD2Module-0.2.1.rbz.
