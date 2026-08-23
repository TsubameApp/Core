# miniz

Tsubame vendors the miniz 3.1.2 amalgamated ZIP implementation for portable,
dependency-free dictionary archive reading on macOS, Linux, and Windows.

- Upstream: https://github.com/richgel999/miniz
- Release: https://github.com/richgel999/miniz/releases/tag/3.1.2
- Release archive SHA-256: `f0446d863f9c19926ad9483c523fdc42e42b8d4a6a431d27e09d49c79a140d9a`
- Vendored upstream files: `Sources/ThirdParty/CMiniz/miniz.c`,
  `Sources/ThirdParty/CMiniz/include/miniz.h`
- License: MIT; see `miniz-LICENSE.txt`

Tsubame's interoperability layer is a separate `CTsubameZIP` target under
`Sources/Interop`; it is not part of the vendored miniz source.
