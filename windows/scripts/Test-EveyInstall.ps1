param(
    [string]$InstallDirectory = (Join-Path $HOME "evey-stack"),
    [ValidateSet("base", "services", "full")]
    [string]$Tier = "base",
    [string]$EvidenceDirectory,
    [switch]$FailOnError
)

. "$PSScriptRoot/EveyCommon.ps1"

function New-InstallCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail = ""
    )
    return [ordered]@{ name = $Name; status = $Status; detail = $Detail }
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$logDir = Get-EveyLogDirectory -RunId $runId
$logFile = Join-Path $logDir "verify.log"
if (-not $EvidenceDirectory) {
    $EvidenceDirectory = Join-Path (Join-Path (Get-Location).Path "test-results/windows") $runId
}
New-EveyDirectory -Path $EvidenceDirectory

$checks = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory "docker-compose.yml"))) {
    $checks.Add((New-InstallCheck -Name "docker-compose.yml" -Status "fail" -Detail "docker-compose.yml is missing."))
} else {
    $checks.Add((New-InstallCheck -Name "docker-compose.yml" -Status "pass" -Detail "docker-compose.yml exists."))
}

$envPath = Join-Path $InstallDirectory ".env"
if (Test-Path -LiteralPath $envPath) {
    $checks.Add((New-InstallCheck -Name ".env" -Status "pass" -Detail ".env exists."))
} else {
    $checks.Add((New-InstallCheck -Name ".env" -Status "fail" -Detail ".env is missing."))
}

if (Test-EveyCommand "docker") {
    $version = Invoke-EveyNative -FilePath "docker" -Arguments @("--version") -LogFile $logFile
    $checks.Add((New-InstallCheck -Name "docker version" -Status ($(if ($version.ExitCode -eq 0) { "pass" } else { "fail" })) -Detail $version.Stdout.Trim()))

    $composeVersion = Invoke-EveyNative -FilePath "docker" -Arguments @("compose", "version") -LogFile $logFile
    $checks.Add((New-InstallCheck -Name "docker compose version" -Status ($(if ($composeVersion.ExitCode -eq 0) { "pass" } else { "fail" })) -Detail $composeVersion.Stdout.Trim()))

    $ps = Invoke-EveyNative -FilePath "docker" -Arguments @("compose", "ps") -WorkingDirectory $InstallDirectory -LogFile $logFile
    $psPath = Join-Path $EvidenceDirectory "docker-compose-ps.txt"
    Set-Content -LiteralPath $psPath -Value (ConvertTo-EveyMaskedText -Text ($ps.Stdout + $ps.Stderr)) -Encoding UTF8
    $checks.Add((New-InstallCheck -Name "docker compose ps" -Status ($(if ($ps.ExitCode -eq 0) { "pass" } else { "fail" })) -Detail "Saved to $psPath."))
} else {
    $checks.Add((New-InstallCheck -Name "docker" -Status "fail" -Detail "docker command was not found."))
}

$healthTargets = @(
    @{ name = "LiteLLM"; url = "http://localhost:4000/health/liveliness" },
    @{ name = "Hermes Agent"; url = "http://localhost:8642/health" }
)
if ($Tier -in @("services", "full")) {
    $healthTargets += @{ name = "SearXNG"; url = "http://localhost:8888" }
}
if ($Tier -eq "full") {
    $healthTargets += @{ name = "n8n"; url = "http://localhost:5678/healthz" }
    $healthTargets += @{ name = "Langfuse"; url = "http://localhost:3100" }
    $healthTargets += @{ name = "Uptime Kuma"; url = "http://localhost:3001" }
}

foreach ($target in $healthTargets) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $target.url -TimeoutSec 10
        $status = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) { "pass" } else { "fail" }
        $checks.Add((New-InstallCheck -Name $target.name -Status $status -Detail "$($target.url) returned $($response.StatusCode)."))
    } catch {
        $checks.Add((New-InstallCheck -Name $target.name -Status "fail" -Detail "$($target.url) failed: $($_.Exception.Message)"))
    }
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    installDirectory = $InstallDirectory
    tier = $Tier
    evidenceDirectory = $EvidenceDirectory
    checks = $checks
    passed = (-not [bool]($checks | Where-Object { $_.status -eq "fail" }))
    requiredWindowsEvidence = "test-results/windows/<UTC date>/<case-id>/ including win11-ready-base before release"
}

$reportPath = Join-Path $EvidenceDirectory "install-verification.json"
Write-EveyJson -InputObject $report -Path $reportPath | Out-Null
Write-EveyLog -Message "Verification report written to $reportPath" -LogFile $logFile

if ($FailOnError -and -not $report.passed) {
    exit 30
}

$report
