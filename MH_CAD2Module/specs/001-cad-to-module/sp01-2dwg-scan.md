# Scan 2.dwg / SP01

User requested E:/MAC/OneDrive/Desktop/2.dwg, SP01. Archived SHA256 c48b8576c7f1e7e8b029c1ea103b935a8efa71bb499efb3d3be8eae2c336f3f2. Two KHUNG XH frames identify CHI TIẾT TỦ ÁO; the source contains 51 product codes overall.

Observed failure: parser 0.1.3 chooses a 681×546 drawer enclosure plus two contained 287.5×400 drawer components instead of the full cabinet. It wrongly reports ready and 681×259×564 bounds. Nested candidates inflate the assembly score. The actual front also includes mixed 24/18 mm panels, cladding and alternative overlapping wall outlines; correct complete product segmentation has not been established. Do not build the drawer interpretation as SP01.

Scoped immediate fix: reject overlapping module outputs in the worker and again before any native geometry mutation. Preserve candidate boxes/handles as review evidence. Re-scan with invalidated caches; focus SP01 and save a diagnostic history event. This is a detection guard, not a claim that full SP01 recognition is solved.

Validation: overlap rejection including contained drawers, contact-only boundaries remain allowed; actual Drawing1 and native checks must remain valid; native SP01 review must leave the original label/model entities intact.
