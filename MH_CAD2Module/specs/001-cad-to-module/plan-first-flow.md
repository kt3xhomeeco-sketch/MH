# Plan-first module recognition

User direction: remove leaders and section-callout blocks from recognition; use plan/horizontal section to divide vertical bays first, then open-door elevation and vertical sections to divide horizontal tiers. The closed-door elevation is check-only. Actual section construction geometry must remain available.

Design: keep view-title metadata (never DIM values), classify anonymous section symbols by their paired callout attributes, keep marker axis/numbers separately and remove symbol geometry. Group drawing regions by title rows and centres; associate horizontal section numbers with horizontal markers. Record roles, filtered outlines and geometry evidence. Named or anonymous furniture blocks must survive the filter.

For declared views, plan-side chains generate the vertical bay candidates first. Front-open geometry can assign tier heights to those bays but cannot invent extra vertical divisions from drawer boxes. Vertical sections confirm depth and uncut boundaries; front-check geometry never supplies primary candidates. Missing/mismatched evidence stops with diagnostics and retains the measured stage results. No file-specific coordinates, dimensions, block handles or product codes in the recogniser.

- [x] Semantic annotation filter and view classification tests.
- [x] Plan columns precede horizontal tier matching, with explicit stage provenance.
- [x] Check-only elevations cannot change primary module count/dimensions.
- [x] Re-scan SP01; the exterior 24 mm mismatch was resolved by user feedback plus a plan stock witness.
- [x] Python/Ruby/RuboCop, native SketchUp and package gates.

User clarification: the 24 mm strip beside SP01 is trim made from 18 mm board turned to face out. Common board thickness priors: 6, 8, 12, 15, 18, 25, 36 (36 can be a 2×18 laminate). Never round dimensions or classify every 24 mm frontal feature as 24 mm stock. An exterior trim classification requires adjacency, the confirmed 24/18 face/stock rule, and an actual 18 mm plan witness. Preserve the strip as a separate wire reference, with measured envelope and stock metadata; it does not enter module count/template replacement. Include it in product extent/centering and correction snapshots. Missing stock witness must still require review. A 36 mm measurement alone does not establish a module joint.

Unlabelled selected edges use spatially separated geometric view inference; missing/ambiguous plan evidence stops rather than silently reverting to the old front-first algorithm. A shaped door profile is no longer required to identify the two-leg support when plan and matched construction views already establish correspondence.

Large multi-product drawings: build requests carry target codes/names, with separate cache keys. A partial scan cannot replace a full-source product index. The current SP01 pass processed only the requested product; all original source revisions remain archived.
