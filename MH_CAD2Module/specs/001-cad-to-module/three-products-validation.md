# 0.3.1 — real SP28/SP29/SP30 failures

The failed user jobs stopped at measured geometry validation, not an ODA or SketchUp crash. SP28/SP29 omitted carcasses when visible/hidden cap pieces and differently extended side panels did not form one input rectangle. Drawer components could also look like two full-height dividing walls. SP30 had two measured 18 × 50 mm strips outside the recognised frontage which only the older 24 mm turned-trim rule could classify.

The repair retains measured side seams when recovering rectangles, joins complete stock-thickness cap rows, includes external lids, and requires every boundary wall's tier coverage. Repeated tiers can share a section only when depth, bottom seam and top plane agree; each front seam and the section's uncut-panel check remain mandatory. Closed framed-door contours contribute their measured footprint. Exact plan footprints classify stock-width perimeter and inter-bay parts. Auxiliary bounds now also update module floor/front and carcass origins. Recognizer cache revision 2 avoids replaying old failed analyses without changing extraction version 0.2.3 or accepted experience history. No product code or stored module dimensions enter recognition rules.

## Verification
- Full pre-existing plus real regression suite: 60 pytest checks passed. The subsequently added stale-cache regression passed separately (61 total).
- Ruby: 5 tests / 16 assertions; RuboCop/rubocop-sketchup: 12 runtime files, no offenses.
- Both management and learning browser checks passed.
- Actual archived DWG re-analysis: all three ready; accepted-example mode remains unmatched and measured construction recognition supplies these results.
- Native SketchUp 2025 PID 31044 temporary aborted operation passed: 13 solid modules and 6 auxiliary references, exact dimensions/coordinates within 0.01 mm, centre X on each real label, front/floor zero, original root geometry unchanged. Receipt: outputs/three-native-result.json.
- Actual app Build retry job 7607b101-0c10-c743-159c-b6777a2fe024 completed 3/3 with zero errors. Product IDs SP28=962583, SP29=962819, SP30=963001. Post-build native sizes, placements, label centres and original geometry all passed. Receipt: outputs/three-retry-result.json. The three new products remain in the live model, with normal Undo; no user model save or training acceptance was performed.
- Packaged outputs/MH_CAD2Module-0.3.1.rbz; active local worker uses the repaired recognition immediately.

| Code | Modules | Main widths (mm) | Depth (mm) | Lower / upper height (mm) | Auxiliary references |
|---|---:|---|---:|---|---:|
| SP28 | 4 | 860 / 1422 | 550 | 2150 / 400 | 1 |
| SP29 | 5 | 1100 / 1300 / 1134 | 550 | 2150; centre 700 / 400 | 3 |
| SP30 | 4 | 1044.5 / 1044.5 | 550 | 2150 / 400 | 2 |

Module bases retain the measured 50 mm plinth; upper modules start at Z=2200 mm. Overall bounds include recognised auxiliary references, height 2680 mm. This stage supplies replacement module proxies and measured auxiliary references, not a complete panel manufacturing model. Automated geometric verification does not constitute user acceptance or create a training example.
