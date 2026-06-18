param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [switch]$Publish,

    [switch]$CheckRuntime
)

$ErrorActionPreference = "Stop"
$WindowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Solution = Join-Path $WindowsRoot "TypeWhale.Windows.sln"

if ($Publish -or $CheckRuntime) {
    & (Join-Path $PSScriptRoot "Check-WindowsLayout.ps1")
}

dotnet restore $Solution

if ($Publish) {
    $PublishDir = Join-Path $WindowsRoot "publish\$Configuration"
    dotnet publish $Solution -c $Configuration -r win-x64 --self-contained false -p:Platform=x64 -o $PublishDir
    Write-Host "Published to $PublishDir" -ForegroundColor Green
} else {
    dotnet build $Solution -c $Configuration -p:Platform=x64
}
