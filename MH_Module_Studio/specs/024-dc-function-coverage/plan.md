# Plan

1. Read prior conversion diagnostics and SDK captures. Audit source hashes and
   function inventory, including model attributes, into separate before/after
   reports. Do not overwrite the established conversion results with SDK counts.
2. Correct COPY and scoped references in both numerical and symbolic paths.
   Add strictly validated math functions to the shared expression evaluator.
   Capture the installed ABF loader's generated text synchronously before its
   abf_eval boundary using a unique catch/throw tag, never eval/registration.
   Recognize complete templates rather than names or cached results. SDK file
   reads enrich mappings on the UI timer after the background reader finishes.
3. Add regression cases for original/copies, ambiguous names, serialization,
   changed topology refusal, numerical STRING metadata, and math domain errors.
4. Run Spec Kit prerequisites, RuboCop and portable tests; compare full-library
   coverage. If VBO connects, reload and run conversion/native round trips on
   newly supported candidates. Keep unknown encrypted implementations explicit.

References: SketchUp supported functions and predefined attributes:
https://help.sketchup.com/en/sketchup/dynamic-component-supported-functions
https://help.sketchup.com/en/sketchup/dynamic-component-predefined-attributes

No new runtime files or package manifest changes are planned. Native helpers and
the HUD are outside this feature's scope.
