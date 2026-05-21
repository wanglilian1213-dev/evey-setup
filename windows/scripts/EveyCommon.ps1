Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EveyProgramData {
    if ($env:ProgramData) {
        return (Join-Path $env:ProgramData "EveySetup")
    }
    return (Join-Path $HOME ".evey-setup")
}

function Get-EveyStatePath {
    return (Join-Path (Get-EveyProgramData) "install-state.json")
}

function Test-EveyIsWindows {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function ConvertTo-EveyHashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [hashtable]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-EveyHashtable -InputObject $InputObject[$key]
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-EveyHashtable -InputObject $_ })
    }
    if ($InputObject.PSObject.Properties.Count -gt 0 -and $InputObject -isnot [string]) {
        $hash = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-EveyHashtable -InputObject $property.Value
        }
        return $hash
    }
    return $InputObject
}

function New-EveyDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-EveyLogDirectory {
    param([string]$RunId)

    if (-not $RunId) {
        $RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    }
    $path = Join-Path (Get-EveyProgramData) "logs"
    $path = Join-Path $path $RunId
    New-EveyDirectory -Path $path
    return $path
}

function Read-EveyState {
    $path = Get-EveyStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{}
    }
    $raw = Get-Content -LiteralPath $path -Raw
    if (-not $raw.Trim()) {
        return [ordered]@{}
    }
    return (ConvertTo-EveyHashtable -InputObject ($raw | ConvertFrom-Json))
}

function Save-EveyState {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)

    Assert-EveyStateHasNoSecrets -State $State
    $root = Get-EveyProgramData
    New-EveyDirectory -Path $root
    $path = Get-EveyStatePath
    $State.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    ($State | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Assert-EveyStateHasNoSecrets {
    param([Parameter(Mandatory)]$State)

    $json = ($State | ConvertTo-Json -Depth 12)
    $secretPatterns = @(
        'OPENROUTER_API_KEY',
        'TELEGRAM_BOT_TOKEN',
        'DISCORD_BOT_TOKEN',
        'LITELLM_MASTER_KEY',
        'API_SERVER_KEY',
        'sk-[A-Za-z0-9_\-]{8,}',
        'bot[0-9]{6,}:[A-Za-z0-9_\-]{20,}'
    )
    foreach ($pattern in $secretPatterns) {
        if ($json -match $pattern) {
            throw "Secret-like value found in installer state. Refusing to write install-state.json."
        }
    }
}

function Mask-EveyValue {
    param([AllowNull()][string]$Value)

    if (-not $Value) {
        return ""
    }
    if ($Value.Length -le 8) {
        return "****"
    }
    return ($Value.Substring(0, [Math]::Min(3, $Value.Length)) + "...****..." + $Value.Substring($Value.Length - 4))
}

function ConvertTo-EveyMaskedText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }
    $masked = $Text
    $patterns = @(
        '(sk-[A-Za-z0-9_\-]{8,})',
        '([A-Fa-f0-9]{32,})',
        '(xox[baprs]-[A-Za-z0-9\-]{10,})',
        '(bot[0-9]{6,}:[A-Za-z0-9_\-]{20,})'
    )
    foreach ($pattern in $patterns) {
        $masked = [regex]::Replace($masked, $pattern, {
            param($m)
            Mask-EveyValue -Value $m.Value
        })
    }
    return $masked
}

function Write-EveyLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date).ToUniversalTime().ToString("o"), $Level, (ConvertTo-EveyMaskedText -Text $Message)
    Write-Host $line
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
}

function Protect-EveyFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-EveyIsWindows)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $resolved /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "icacls.exe failed while disabling inherited permissions for $Path."
    }
    & icacls.exe $resolved /grant:r "*${userSid}:F" "*S-1-5-32-544:F" "*S-1-5-18:F" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "icacls.exe failed while restricting permissions for $Path."
    }
}

function New-EveyToken {
    param([int]$ByteCount = 16)

    $bytes = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Test-EveyCommand {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-EveyNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = (Get-Location).Path,
        [string]$LogFile
    )

    $previous = (Get-Location).Path
    Set-Location -LiteralPath $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $global:LASTEXITCODE = 0
    } finally {
        Set-Location -LiteralPath $previous
    }
    $stdout = ($output | Out-String)
    $stderr = ""

    if ($LogFile) {
        if ($stdout) { Add-Content -LiteralPath $LogFile -Value (ConvertTo-EveyMaskedText -Text $stdout) -Encoding UTF8 }
        if ($stderr) { Add-Content -LiteralPath $LogFile -Value (ConvertTo-EveyMaskedText -Text $stderr) -Encoding UTF8 }
    }

    return [ordered]@{
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Test-EveyPortFree {
    param([Parameter(Mandatory)][int]$Port)

    if (-not (Test-EveyIsWindows)) {
        return $true
    }
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return -not [bool]($listeners | Where-Object { $_.Port -eq $Port })
}

function Write-EveyJson {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-EveyDirectory -Path $parent
    }
    ($InputObject | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}
