# Named product plan selection and CAD reference (0.12.0)

User scope: entering a product code must bring that product's measured plan into SketchUp alongside independent module Groups. Distinguish product from walls/stairs, horizontal from vertical sections using elevation/cut callouts and geometry. A section number alone never decides orientation.

## Required behaviour

- Scope source geometry/annotations to the product's frame regions; remove dimensions/leaders/callout blocks. Retain layer, nested block context and actual geometry as evidence.
- Use closed stock strips/common-depth bays as positive furniture evidence. Wall names/layers alone cannot erase a valid wood panel. Thick wall strips and repeated stair treads with supporting context/diagonal evidence are background candidates, not cabinets.
- Separate titled spatial slots and connected groups. Restrict prospective plans to the stock/attached curve/trim envelope, reporting excluded background.
- Link section identifiers only to markers located on an elevation of the same product. Determine marker axis from the actual cut LINE, not text/block bounding box. Cross-check measured plan width/panel positions with that linked elevation; record vertical section height agreement/mismatch.
- Untitled views may use distinct measured elevation/plan stock evidence. A standalone single plan remains supported. Conflicting/multiple non-identical horizontal cuts require explicit view confirmation; never pick the widest by default.
- Show each candidate, dimensions, reasons, cut links and an isolated preview in Management. Confirmation re-reads the original source and validates source hash, view ID/signature and eligibility. Save the confirmed choice per immutable source hash/product code. A changed source cannot inherit it.
- Import the chosen plan as a separate root edge-only Group, on XOY, using exactly the modules' initial transform/label placement. Preserve measured arcs as native ArcCurves. The reference is not an Assembly member, selected box, solid module or training sample. Its separate product/tag/source metadata makes it independently hideable and leaves it visible during correction.
- Setting `import_plan_reference` defaults true and persists through existing settings save. It controls new named-source builds, not direct scans already drawn in SketchUp. No AI/AutoCAD launch. Ordinary correction/history/source preservation contracts remain.

## Verification

Synthetic cases: identical section name with horizontal/vertical/oblique markers; wrong width/foreign marker; thick wall, stair treads and wall-layer cabinet; untitled views; ambiguous cuts and stale confirmation; nested block inheritance; arc transport and corrected source origin. Worker/DXF round trip must isolate the plan, keep diagnostics, preserve cache/source-specific choice and avoid archived plan/AI code.

Native aborted checks: label-centred transform, Z=0, source dimensions, independent solid modules, edge-only reference Group/tag, true ArcCurves, setting off, isolated Select/correction, shared undo and untouched user model/settings/history. UI checks include candidate preview/confirm payload, safe text, busy state and remembered toggle. Run scoped pytest, Ruby/RuboCop, existing browser suites and package/live reload.
