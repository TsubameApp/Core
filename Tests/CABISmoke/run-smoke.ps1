param(
    [string]$CorePath = "Core"
)

$ErrorActionPreference = "Stop"
$smokeRoot = Join-Path $env:RUNNER_TEMP "tsubame-c-abi-smoke-$([Guid]::NewGuid())"
$sourcePath = Join-Path $CorePath "Tests/CABISmoke/tsubame_abi_smoke.c"
$includePath = Join-Path $CorePath "Sources/Interop/CTsubameABI/include"
New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
$swiftFlags = @()
if ($env:TSUBAME_DISABLE_SWIFTPM_SANDBOX -eq "1") {
    $swiftFlags += "--disable-sandbox"
}

& swift build --package-path $CorePath --product TsubameCoreABI @swiftFlags
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& swift run --package-path $CorePath @swiftFlags TsubameCLI import `
    "$CorePath/Tests/TsubameCLIPlatformTests/Resources/CLIYomitanDictionary" `
    --data-root $smokeRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$binPath = (& swift build --package-path $CorePath --show-bin-path @swiftFlags).Trim()
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$databasePath = Get-ChildItem -Path "$smokeRoot/Dictionaries" -Recurse -File `
    -Filter "dictionary.sqlite" | Select-Object -First 1 -ExpandProperty FullName
if (-not $databasePath) { throw "C ABI smoke dictionary was not created." }

$objectPath = Join-Path $smokeRoot "tsubame_abi_smoke.obj"
$executablePath = Join-Path $smokeRoot "tsubame_abi_smoke.exe"

& clang -std=c11 -Wall -Wextra -Werror `
    "-I$includePath" -c $sourcePath -o $objectPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& clang++ -std=c++17 -Wall -Wextra -Werror `
    "-I$includePath" -x c++ -fsyntax-only $sourcePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# This executable is pure C. Using swiftc here adds swiftrt.obj on Windows even
# though the client has no Swift code, which leaves swiftCore unresolved.
& clang $objectPath "-L$binPath" -lTsubameCoreABI -o $executablePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exports = & llvm-readobj --coff-exports "$binPath/TsubameCoreABI.dll"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not ($exports -match "Name: tsubame_engine_execute")) {
    throw "TsubameCoreABI.dll does not export tsubame_engine_execute."
}

$env:Path = "$binPath;$env:Path"
& $executablePath $databasePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
