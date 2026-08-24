#!/usr/bin/env bash
set -euo pipefail

core_path="${1:-Core}"
smoke_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tsubame-c-abi-smoke.XXXXXX")"
source_path="$core_path/Tests/CABISmoke/tsubame_abi_smoke.c"
include_path="$core_path/Sources/Interop/CTsubameABI/include"
swift_command="${TSUBAME_SWIFT_EXECUTABLE:-swift}"
swiftc_command="${TSUBAME_SWIFTC_EXECUTABLE:-swiftc}"

run_swift_package() {
  local subcommand="$1"
  shift
  if [[ "${TSUBAME_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    "$swift_command" "$subcommand" --package-path "$core_path" --disable-sandbox "$@"
  else
    "$swift_command" "$subcommand" --package-path "$core_path" "$@"
  fi
}

run_swift_package build --product TsubameCoreABI
run_swift_package run TsubameCLI import \
  "$core_path/Tests/TsubameCLIPlatformTests/Resources/CLIYomitanDictionary" \
  --data-root "$smoke_root"

bin_path="$(run_swift_package build --show-bin-path)"
database_path="$(find "$smoke_root/Dictionaries" -type f -name dictionary.sqlite -print -quit)"
test -n "$database_path"

if [[ "$(uname -s)" == "Darwin" ]]; then
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  target="$(uname -m)-apple-macosx13.0"

  clang -std=c11 -Wall -Wextra -Werror \
    -isysroot "$sdk_path" -target "$target" \
    -I "$include_path" \
    -c "$source_path" \
    -o "$smoke_root/tsubame_abi_smoke.o"

  clang++ -std=c++17 -Wall -Wextra -Werror \
    -isysroot "$sdk_path" -target "$target" \
    -I "$include_path" \
    -x c++ -fsyntax-only "$source_path"

  "$swiftc_command" "$smoke_root/tsubame_abi_smoke.o" \
    -sdk "$sdk_path" -target "$target" \
    -L "$bin_path" \
    -lTsubameCoreABI \
    -Xlinker -rpath \
    -Xlinker "$bin_path" \
    -o "$smoke_root/tsubame_abi_smoke"
else
  clang -std=c11 -Wall -Wextra -Werror \
    -I "$include_path" \
    -c "$source_path" \
    -o "$smoke_root/tsubame_abi_smoke.o"

  clang++ -std=c++17 -Wall -Wextra -Werror \
    -I "$include_path" \
    -x c++ -fsyntax-only "$source_path"

  "$swiftc_command" "$smoke_root/tsubame_abi_smoke.o" \
    -L "$bin_path" \
    -lTsubameCoreABI \
    -Xlinker -rpath \
    -Xlinker "$bin_path" \
    -o "$smoke_root/tsubame_abi_smoke"
fi

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
