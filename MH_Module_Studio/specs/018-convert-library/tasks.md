# Conversion tasks

- [x] Inventory 227 current source SKPs and destination
- [x] Pilot native conversion, preserving source/user model and exact geometry
- [x] Process all source SKPs; validate exported payloads/geometry
- [x] Native parameter round trips on every candidate; exclude unsupported outputs
- [x] Fix submillimeter envelope drift, regression test and reload/package
- [x] Verify source hashes, final reports and Library folder; independent native copies

Result: 37 usable modules, 190 files not converted by the current engine. All
source hashes unchanged. Twelve initially compiled single-part exports cannot
change internal geometry under the fixed-envelope requirement; their generated
copies are retained in .conversion/needs-review and excluded from Library.
