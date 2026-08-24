# tsubame c abi v1

public api is in `Sources/Interop/CTsubameABI/include/tsubame.h`.

there is one `execute` function instead of separate c functions for lookup and
scan. main reason is we can change json to something faster later without
breaking all c signatures. for now v1 only knows
`TSUBAME_SERIALIZATION_JSON_V1`.

one engine opens one `dictionary.sqlite`. if client has few dictionaries, it
creates few engines and decides order/enabled state by itself. this logic does
not belong to core.

## requests

request is utf-8 json. all fields below are required. unknown fields are error,
because silently accepting typo here is not very nice.

all positions and ranges are byte offsets in original utf-8 text. ranges are
half-open, so `{ "start": 3, "end": 18 }` means `3..<18`.

positioned lookup:

```json
{
  "schemaVersion": 1,
  "operation": "positionedLookup",
  "request": {
    "text": "食べました",
    "position": 0,
    "resultLimit": 100
  }
}
```

range scan:

```json
{
  "schemaVersion": 1,
  "operation": "rangeScan",
  "request": {
    "text": "前食べましたｶﾞｸｾｲ後",
    "range": { "start": 3, "end": 33 },
    "resultGroupLimit": 100,
    "entriesPerGroupLimit": 100
  }
}
```

## results

positioned lookup returns one result:

```json
{
  "schemaVersion": 1,
  "operation": "positionedLookup",
  "result": {
    "sourceRange": { "start": 0, "end": 15 },
    "entries": []
  }
}
```

scan returns ordered list of results:

```json
{
  "schemaVersion": 1,
  "operation": "rangeScan",
  "results": []
}
```

entry looks like this. this is separate abi dto, not encoded swift model and we
should not make clients depend on internal codable layout.

```json
{
  "id": 1,
  "expression": "食べる",
  "reading": "たべる",
  "definitionTags": null,
  "rules": "v1",
  "score": 10,
  "sequence": 1,
  "termTags": "",
  "matches": [
    { "key": "食べる", "keyType": "expression" }
  ],
  "definitions": [
    { "position": 0, "kind": "text", "text": "to eat", "content": "to eat" }
  ]
}
```

json keys are deterministic. arrays keep core ordering. buffers are not zero
terminated, always use returned length.

## errors and memory

call returns numeric `TsubameStatus`. this number is stable and client should
branch on it. when core can create error buffer, it contains json like this:

```json
{
  "schemaVersion": 1,
  "status": 3,
  "code": "malformed_json",
  "message": "Request is not valid JSON."
}
```

`code` and `message` are mostly for logs and debugging. do not build logic from
english message.

limits in v1:

- database path: 65536 bytes
- request: 1 mib
- serialized result: 64 mib

too big or not representable lengths are rejected before core reads input
pointer. null pointer is only ok when length is zero.

caller owns all input memory. core copies input during call and does not keep the
pointer. result and error buffers are allocated by core, so they must be freed
with `tsubame_buffer_free`. do not use system `free` for them.

few threads can call execute on same engine. core serializes this calls. destroy
is different: client must be sure no execute is running when engine is destroyed.
