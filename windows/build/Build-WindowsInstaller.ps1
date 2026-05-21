param(
    [string]$InnoCompiler,
    [string]$OutputDirectory = (Join-Path (Resolve-Path "$PSScriptRoot\..\..").Path "dist"),
    [switch]$RequireSigned
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$issPath = Join-Path $repoRoot "windows\install\EveySetup.iss"

if (-not $InnoCompiler) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    $InnoCompiler = ($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1)
}

if (-not $InnoCompiler -or -not (Test-Path -LiteralPath $InnoCompiler)) {
    throw "ISCC.exe was not found. Install Inno Setup 6 or pass -InnoCompiler."
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

& $InnoCompiler "/DRepoRoot=$repoRoot" "/DOutputDir=$OutputDirectory" $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compiler failed with exit code $LASTEXITCODE."
}

$installer = Get-ChildItem -LiteralPath $OutputDirectory -Filter "EveySetup-*-internal-test.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $installer) {
    throw "Installer was not produced in $OutputDirectory."
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName
$hashPath = "$($installer.FullName).sha256"
"$($hash.Hash)  $($installer.Name)" | Set-Content -LiteralPath $hashPath -Encoding ASCII

if ($RequireSigned) {
    $signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
    if ($signature.Status -ne "Valid") {
        throw "Installer is not code-signed. Public release requires code signing."
    }
}

[ordered]@{
    installer = $installer.FullName
    sha256 = $hash.Hash
    checksumFile = $hashPath
    label = "internal-test"
}
