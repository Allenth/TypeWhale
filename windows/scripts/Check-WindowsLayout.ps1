param(
    [string]$ProjectDir = (Join-Path $PSScriptRoot "..\TypeWhale.Windows")
)

$ErrorActionPreference = "Stop"
$ProjectDir = (Resolve-Path $ProjectDir).Path

$requiredFiles = @(
    "Models\sensevoice-native\model.onnx",
    "Models\sensevoice-native\tokens.txt",
    "Models\vad\silero_vad.onnx",
    "runtimes\win-x64\native\TypeSpeakerNativeASR.dll",
    "runtimes\win-x64\native\sherpa-onnx-c-api.dll",
    "runtimes\win-x64\native\onnxruntime.dll",
    "runtimes\win-x64\native\onnxruntime_providers_shared.dll"
)

$missing = @()
foreach ($file in $requiredFiles) {
    $path = Join-Path $ProjectDir $file
    if (-not (Test-Path $path)) {
        $missing += $file
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Missing Windows runtime files:" -ForegroundColor Yellow
    foreach ($file in $missing) {
        Write-Host "  - $file"
    }
    exit 1
}

Write-Host "Windows project layout looks ready." -ForegroundColor Green
