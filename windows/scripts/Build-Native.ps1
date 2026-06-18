param(
    [Parameter(Mandatory = $true)]
    [string]$SherpaOnnxRoot,

    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$WindowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NativeRoot = Join-Path $WindowsRoot "native"
$BuildDir = Join-Path $NativeRoot "build"
$RuntimeDir = Join-Path $WindowsRoot "TypeWhale.Windows\runtimes\win-x64\native"

if (-not (Test-Path $SherpaOnnxRoot)) {
    throw "SHERPA_ONNX_ROOT does not exist: $SherpaOnnxRoot"
}

cmake -S $NativeRoot -B $BuildDir -A x64 -DSHERPA_ONNX_ROOT="$SherpaOnnxRoot"
cmake --build $BuildDir --config $Configuration

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

$bridge = Join-Path $BuildDir "$Configuration\TypeSpeakerNativeASR.dll"
if (-not (Test-Path $bridge)) {
    $bridge = Get-ChildItem $BuildDir -Recurse -Filter TypeSpeakerNativeASR.dll | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $bridge) {
    throw "Could not find TypeSpeakerNativeASR.dll under $BuildDir"
}
Copy-Item $bridge $RuntimeDir -Force

$candidateDllDirs = @(
    (Join-Path $SherpaOnnxRoot "bin"),
    (Join-Path $SherpaOnnxRoot "lib")
) | Where-Object { Test-Path $_ }

$dependencyNames = @("sherpa-onnx-c-api.dll", "onnxruntime.dll", "onnxruntime_providers_shared.dll")
foreach ($name in $dependencyNames) {
    $source = $null
    foreach ($dir in $candidateDllDirs) {
        $match = Get-ChildItem $dir -Recurse -Filter $name | Select-Object -First 1
        if ($match) {
            $source = $match.FullName
            break
        }
    }
    if (-not $source) {
        throw "Could not find dependency DLL: $name"
    }
    Copy-Item $source $RuntimeDir -Force
}

Write-Host "Native runtime copied to $RuntimeDir" -ForegroundColor Green
