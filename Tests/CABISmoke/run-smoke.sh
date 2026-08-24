#!/usr/bin/env bash
set -euo pipefail

core_path="${1:-Core}"
smoke_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tsubame-c-abi-smoke.XXXXXX")"
source_path="$core_path/Tests/CABISmoke/tsubame_abi_smoke.c"
include_path="$core_path/Sources/Interop/CTsubameABI/include"
swift_command="${TSUBAME_SWIFT_EXECUTABLE:-swift}"
swiftc_command="${TSUBAME_SWIFTC_EXECUTABLE:-swiftc}"
swift_flags=()
c_platform_flags=()
swift_link_flags=()
if [[ "${TSUBAME_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  swift_flags+=(--disable-sandbox)
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  target="$(uname -m)-apple-macosx13.0"
  c_platform_flags+=( -isysroot "$sdk_path" -target "$target" )
  swift_link_flags+=( -sdk "$sdk_path" -target "$target" )
fi

"$swift_command" build --package-path "$core_path" --product TsubameCoreABI "${swift_flags[@]}"
"$swift_command" run --package-path "$core_path" "${swift_flags[@]}" TsubameCLI import \
  "$core_path/Tests/TsubameCLIPlatformTests/Resources/CLIYomitanDictionary" \
  --data-root "$smoke_root"

bin_path="$("$swift_command" build --package-path "$core_path" --show-bin-path "${swift_flags[@]}")"
database_path="$(find "$smoke_root/Dictionaries" -type f -name dictionary.sqlite -print -quit)"
test -n "$database_path"

clang -std=c11 -Wall -Wextra -Werror \
  "${c_platform_flags[@]}" \
  -I "$include_path" \
  -c "$source_path" \
  -o "$smoke_root/tsubame_abi_smoke.o"

clang++ -std=c++17 -Wall -Wextra -Werror \
  "${c_platform_flags[@]}" \
  -I "$include_path" \
  -x c++ -fsyntax-only "$source_path"

"$swiftc_command" "$smoke_root/tsubame_abi_smoke.o" \
  "${swift_link_flags[@]}" \
  -L "$bin_path" \
  -lTsubameCoreABI \
  -Xlinker -rpath \
  -Xlinker "$bin_path" \
  -o "$smoke_root/tsubame_abi_smoke"

case "$(uname -s)" in
  Darwin)
    nm -gU "$bin_path/libTsubameCoreABI.dylib" | grep -Fq _tsubame_engine_execute
    ;;
  Linux)
    nm -D --defined-only "$bin_path/libTsubameCoreABI.so" | grep -Fq tsubame_engine_execute
    ;;
  *)
    echo "Unsupported Unix platform for the C ABI smoke test." >&2
    exit 1
    ;;
esac

"$smoke_root/tsubame_abi_smoke" "$database_path"
