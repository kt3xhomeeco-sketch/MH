# 0.4.0 build stages validation

- Full Python suite: 69 passed, including standalone selected plans without elevations, real SP28/SP29/SP30 footprints, stage/cache isolation, no-stage errors, provisional-learning exclusion and previous full-mode regressions.
- Ruby: 6 tests / 21 assertions passed, including preference/model persistence of both booleans.
- RuboCop/rubocop-sketchup: 12 runtime Ruby files, no offenses.
- Browser: stages, existing management and learning UI checks passed. Stage checks cover default values, checkbox dependencies, immediate save payloads, busy controls and plan-only explanation. Preview: outputs/stages-settings-preview.png.
- Real DWG analysis: SP28=2 plan bays (860/1422 mm), SP29=3 (1100/1300/1134), SP30=2 (1044.5/1044.5); all depth 550 mm and provisional height 1600 mm.
- Native SketchUp PID 31044: temporary boxes matched footprints and label centres within 0.01 mm; every module/auxiliary reference had height 1600 and Z=0. Aborted operation left original geometry unchanged. Receipt: outputs/stages-native-result.json.
- Live Settings loaded, persisted build_plan=true/build_elevation=false; actual app analysis job 735b7fb6-32f0-d7b0-26d5-07fce5fc4430 received both flags and returned plan_only products. Native HtmlDialog confirmed checkbox values and the 1600 mm explanation: outputs/stages-live-ui.json. Existing real products were retained; no replacement or user-model save performed.
- Packaged outputs/MH_CAD2Module-0.4.0.rbz. The old full-stage algorithm remains available only when Mặt đứng is enabled; no claim of universal CAD recognition is made.
