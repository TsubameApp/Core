# Tsubame C ABI v1

The public API is declared in `Sources/Interop/CTsubameABI/include/tsubame.h`.
The plain C types are in
`Sources/Interop/CTsubameABITypes/include/tsubame_types.h`.
Distribute both headers together and link the `TsubameCoreABI` dynamic library.
The headers compile as C11 or C++17.

Clients and the library are built and distributed together. Use the matching
headers and bindings; rebuild clients when signatures or layouts change.
`tsubame_abi_version()` returns `TSUBAME_ABI_VERSION` (1).

## Operations

- `tsubame_engine_create` opens one dictionary.sqlite using an absolute UTF-8 path.
- `tsubame_lookup` accepts text, byte position and entry limit.
- `tsubame_scan` accepts text, half-open byte range and group/entry limits.
- `tsubame_result_get_view` exposes the result's groups, entries and definitions.
- `tsubame_content_get` exposes a definition's typed structured content on demand.
- `tsubame_result_destroy`, `tsubame_engine_destroy` and `tsubame_error_free`
  release their respective owners.

There is no request envelope or encoding step. Text parameters are a pointer
and byte length; numeric parameters are passed directly. Positions and ranges
refer to the original UTF-8 text, on Swift Character boundaries.

One engine owns one dictionary. The client manages multiple dictionaries,
their enabled state and ordering.

## Ownership

Inputs are borrowed during the call and never retained. A NULL input pointer
is valid only with length zero; empty lookup text is an invalid request.

Each successful lookup or scan produces a separately owned `TsubameResult *`.
Its view contains immutable pointer/count arrays and pointer/length UTF-8
strings. They remain valid until that result is destroyed, including across
other lookups and engine destruction. Strings are not NUL-terminated.

For optional strings, NULL means absent. An empty but present string has a
non-NULL pointer with length zero. Empty arrays have a NULL pointer and count
zero. A lookup has one group (possibly with no entries); a scan can have zero
groups. Ordering and original source ranges are preserved.

All output pointers are required. Calls clear output slots before validation.
Output slots must not contain live owned objects: release a previous result or
error before reusing its slot. Output storage must not overlap other output
storage or inputs. A numeric failure status leaves the result/value pointer NULL.

`TsubameError` owns its code and message strings. Its status matches the returned
status. Release it with `tsubame_error_free`, which zeros the struct and accepts
NULL or an already empty error. Do not free copied errors twice, and do not use
the system allocator for any Core-owned memory.

NULL is accepted by engine/result destroy. Non-NULL owners must be destroyed
exactly once. All borrowed pointers become invalid when their owner is destroyed.

## Structured definitions

Each definition contains a borrowed `TsubameContent *` handle. Calling
`tsubame_content_get` materializes and caches an immutable `TsubameValue` tree;
repeated calls return the same pointer. A failed materialization is cached too.
The content handle and its tree belong to the result, not the engine.

The value kind selects one union field: boolean, signed 64-bit integer, double,
UTF-8 string, array or object. Null has no active payload. Object members are
sorted by key. The tree has a maximum nesting depth of 256 value levels.
Malformed or excessively nested stored content fails only when requested;
ordinary entry/definition metadata remains readable.

## Concurrency and limits

Queries on one engine are serialized internally. Results are immutable and may
be read concurrently. Lazy content materialization is synchronized per definition.
Destroy must not race with an operation or borrowed-pointer access using that owner.

- Database path: at most 65,536 UTF-8 bytes, absolute, without embedded NUL.
- Text: 1...65,536 UTF-8 bytes.
- Scan range: 1...1,024 UTF-8 bytes.
- Result groups: 1...256.
- Entries per group (or lookup limit): 1...500.

Input byte lengths are checked before reading input memory. Numeric arguments
are checked before invoking the lookup engine. The caller must still provide
valid readable pointers and valid live handles.

## Example

```c
TsubameResult *result = NULL;
TsubameError error = {0};

TsubameStatus status = tsubame_lookup(
    engine, text, text_length, position, 100, &result, &error);
if (status == TSUBAME_STATUS_OK) {
    TsubameResultView view = {0};
    tsubame_result_get_view(result, &view);
    for (size_t g = 0; g < view.group_count; ++g) {
        const TsubameGroup *group = &view.groups[g];
        for (size_t e = 0; e < group->entry_count; ++e) {
            TsubameString expression = group->entries[e].expression;
            fwrite(expression.data, 1, expression.length, stdout);
        }
    }
    tsubame_result_destroy(result);
}
tsubame_error_free(&error);
```
