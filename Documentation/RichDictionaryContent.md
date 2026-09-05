# Rich dictionary content (P0)

## Data path

The macOS client opens `SQLiteDictionaryStore(contentPolicy: .primary)`.
Primary lookup/scan preserves identity, order, matches and plain definitions,
but substitutes the JSON literal `null` for heavy `contentJSON` payloads.
Call `loadEntryDetails(entryID:)` on a store confined to its own executor for
the typed glossary and entry metadata. The default `.complete` policy is
unchanged for existing Swift/CLI/C ABI consumers. The existing typed C ABI is
not replaced with FlatBuffers, and the bundle schema is unchanged.

`loadTermMetadata(expression:reading:)` also works with metadata-only bundles.
macOS queries enabled sources in dictionary priority order, labels each source,
filters reading-specific metadata and does not compare frequency numbers from
unrelated corpora or reorder primary results after details arrive.

## Native presentation

- Text, adjacent inline spans, semantic bold/italic/underline/strike, limited
  colors/alignment, line breaks, blocks, ordered/unordered lists.
- Ruby, expandable details, basic tables with column spans.
- Local images with dimensions, px/em sizing, alt/description, collapsed state,
  pixelated rendering and monochrome appearance. Aspect ratio is preserved.
- Tags with notes, frequency values/display labels, mora-based pitch patterns
  including the following particle, devoicing and nasal markers.
- Unknown elements retain their children. Links remain inert text. No WebView,
  JavaScript, network image loading or arbitrary dictionary CSS is used.
- Anki receives the loaded plain-text projection, not image media. Mining is
  disabled while a structured definition is still loading.

## Safety and lifecycle

Installation validates image references against the resource inventory before
publishing the bundle. Resolution checks local inventoried paths, image MIME,
size, regular files, containment and symlink components. Bundles are assumed
immutable after installation; this is not a defense against a process actively
rewriting files between validation and reading.

Glossary decoding is limited to 4 MiB per definition, JSON nesting 64, node
depth 32 and 16,384 nodes. Details limit aggregate JSON to 8 MiB/512 definitions.
Details, raw payloads and metadata use independent count-and-cost-bounded LRU
caches. Image loading runs on a separate actor, supports cancellation, and uses
a 24 MiB/64-entry decoded-image NSCache. Cache keys include the bundle, and
dictionary reconfiguration clears caches.

Images are limited to 32 MiB. ImageIO raster decoding rejects images above
40 million pixels and downsamples to 1600 pixels. Animated formats display the
first frame. SVG is limited to 2 MiB/10,000 elements/4096-point dimensions and
an inert element subset. Safe presentation styles are sanitized and retained;
external references, scripts, entities and active CSS are rejected. Invalid
images display a diagnostic placeholder without hiding glossary text.

The popup conservatively combines records from the same dictionary, source
range, expression and rule set only when their complete ordered stored glossary
payloads are byte-identical. Readings and source IDs remain as variants, with an
explicit reading choice for metadata and Anki. Sequence alone never causes a
merge. Small em-sized images participate in native inline flow layout.

## Verification and limitations

Core tests cover installed resources, missing paths, symlinks, traversal,
structured fallback, bounds, frequency variants, mora/pitch and primary payload
compatibility. macOS tests cover decoding/cache isolation/cancellation, corrupt
images, metadata-only dictionaries and native glossary rendering. The Debug
UI fixture tests image appearance and expanding details.

`primaryLookupRetainsIdentityAndOmitsHeavyPayload` prints a small 100-lookup
fixture timing and compares payload bytes; it is not a real-dictionary latency
benchmark. Instruments intervals `EntryDetailsLoad` and `ImageDecode` allow
profiling separately from primary lookup. Large real dictionaries and fast
repeated popup navigation still need representative manual profiling.

Not implemented: full CSS/HTML parity, table row-span layout, active links,
arbitrary SVG styles/filters, animated images, image zoom, network media, audio,
OCR, Anki image export, or a unified cross-dictionary frequency rank.

### Local verification on 2026-09-04

Core: 118 tests passed. macOS: 48 unit/integration tests passed. The fixture
benchmark measured 100 primary lookups in approximately 22 ms and 8 versus
84 glossary payload bytes on this tiny fixture (not a general speed claim).
The UI smoke-test was compiled but could not execute: its runner was killed
before establishing an XCTest connection, both unsigned and ad-hoc signed.
Interactive disclosure/image behavior still needs a successful UI-test run.
