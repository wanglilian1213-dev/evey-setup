param(
    [string]$InstallDirectory = (Join-Path $HOME "evey-stack"),
    [string]$JsonPath,
    [switch]$AcceptDockerNotice,
    [switch]$FailOnError
)

. "$PSScriptRoot/EveyCommon.ps1"

function New-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail = "",
        [string]$NextAction = "",
        [bool]$Required = $true
    )

    return [ordered]@{
        name = $Name
        status = $Status
        required = $Required
        detail = $Detail
        nextAction = $NextAction
    }
}

function Add-Action {
    param(
        [System.Collections.Generic.List[object]]$Actions,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [bool]$RequiresAdmin = $false,
        [bool]$RequiresUserAcceptance = $true,
        [bool]$MayRequireRestart = $false
    )

    $Actions.Add([ordered]@{
        name = $Name
        command = $Command
        requiresAdmin = $RequiresAdmin
        requiresUserAcceptance = $RequiresUserAcceptance
        mayRequireRestart = $MayRequireRestart
    })
}

function Get-DockerMajorVersion {
    param([string]$Text)

    if ($Text -match 'Docker version\s+([0-9]+)\.') {
        return [int]$Matches[1]
    }
    return $null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$logDir = Get-EveyLogDirectory -RunId $runId
$logFile = Join-Path $logDir "prereq.log"
if (-not $JsonPath) {
    $JsonPath = Join-Path $logDir "prereq-report.json"
}

$checks = New-Object System.Collections.Generic.List[object]
$actions = New-Object System.Collections.Generic.List[object]
$isWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)

if (-not $isWindowsHost) {
    $checks.Add((New-Check -Name "Windows" -Status "fail" -Detail "This installer must be verified on Windows 10/11." -NextAction "Run this checker on a Windows 11 machine or VM."))
} else {
    $os = Get-CimInstance Win32_OperatingSystem
    $buildNumber = [int]$os.BuildNumber
    if ($buildNumber -ge 22631) {
        $checks.Add((New-Check -Name "Windows" -Status "pass" -Detail "$($os.Caption) build $($os.BuildNumber)"))
    } else {
        $checks.Add((New-Check -Name "Windows" -Status "fail" -Detail "$($os.Caption) build $($os.BuildNumber)." -NextAction "Use Windows 11 23H2 or newer for this installer build."))
    }

    $computer = Get-CimInstance Win32_ComputerSystem
    $ramGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    if ($ramGb -lt 8) {
        $checks.Add((New-Check -Name "RAM" -Status "warn" -Detail "$ramGb GB detected; 8 GB is recommended." -Required $false))
    } else {
        $checks.Add((New-Check -Name "RAM" -Status "pass" -Detail "$ramGb GB detected."))
    }

    $installRoot = [System.IO.Path]::GetPathRoot($InstallDirectory)
    if (-not $installRoot) {
        $installRoot = "$env:SystemDrive\"
    }
    $drive = Get-PSDrive -Name $installRoot.Substring(0, 1) -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGb -lt 10) {
            $checks.Add((New-Check -Name "Disk" -Status "fail" -Detail "$freeGb GB free." -NextAction "Free at least 10 GB before installing."))
        } else {
            $checks.Add((New-Check -Name "Disk" -Status "pass" -Detail "$freeGb GB free."))
        }
    }

    $virtualization = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
    if ($virtualization) {
        $checks.Add((New-Check -Name "Virtualization" -Status "pass" -Detail "Virtualization is enabled."))
    } else {
        $checks.Add((New-Check -Name "Virtualization" -Status "fail" -Detail "Virtualization appears disabled." -NextAction "Enable virtualization in BIOS/UEFI or choose a VM with nested virtualization."))
    }
}

if (Test-EveyCommand "wsl.exe") {
    $wsl = Invoke-EveyNative -FilePath "wsl.exe" -Arguments @("--status") -LogFile $logFile
    if ($wsl.ExitCode -eq 0) {
        $detail = ($wsl.Stdout + $wsl.Stderr).Trim()
        if ($detail -match "WSL 2|Default Version:\s*2|default version:\s*2") {
            $checks.Add((New-Check -Name "WSL 2" -Status "pass" -Detail "WSL is available."))
        } else {
            $checks.Add((New-Check -Name "WSL 2" -Status "warn" -Detail "WSL is installed but WSL 2 was not confirmed." -NextAction "Run wsl --set-default-version 2 if needed."))
        }
    } else {
        $checks.Add((New-Check -Name "WSL 2" -Status "fail" -Detail "wsl.exe exists but status failed." -NextAction "Run Microsoft's wsl --install from an administrator PowerShell, then restart if Windows asks."))
    }
} else {
    $checks.Add((New-Check -Name "WSL 2" -Status "fail" -Detail "wsl.exe was not found." -NextAction "Approve WSL setup through the installer or run wsl --install as administrator."))
    Add-Action -Actions $actions -Name "Install-EveyPrerequisite WSL 2" -Command "wsl --install" -RequiresAdmin $true -MayRequireRestart $true
}

if (Test-EveyCommand "git.exe") {
    $git = Invoke-EveyNative -FilePath "git.exe" -Arguments @("--version") -LogFile $logFile
    $checks.Add((New-Check -Name "Git" -Status "pass" -Detail $git.Stdout.Trim()))
} elseif (Test-EveyCommand "git") {
    $git = Invoke-EveyNative -FilePath "git" -Arguments @("--version") -LogFile $logFile
    $checks.Add((New-Check -Name "Git" -Status "pass" -Detail $git.Stdout.Trim()))
} else {
    $checks.Add((New-Check -Name "Git" -Status "fail" -Detail "Git was not found." -NextAction "Approve Git installation through winget or install Git for Windows manually."))
    Add-Action -Actions $actions -Name "Install-EveyPrerequisite Git" -Command "winget install --id Git.Git -e" -RequiresAdmin $true
}

$dockerDesktopPaths = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "$env:LocalAppData\Docker\Docker Desktop.exe"
)
$dockerDesktopFound = [bool]($dockerDesktopPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
if ($dockerDesktopFound) {
    $checks.Add((New-Check -Name "Docker Desktop" -Status "pass" -Detail "Docker Desktop was found."))
} else {
    $checks.Add((New-Check -Name "Docker Desktop" -Status "fail" -Detail "Docker Desktop was not found." -NextAction "Install Docker Desktop for Windows and accept Docker's own terms."))
    Add-Action -Actions $actions -Name "Install-EveyPrerequisite Docker Desktop" -Command "Open official Docker Desktop install page" -RequiresAdmin $true
}

if (-not $AcceptDockerNotice) {
    $checks.Add((New-Check -Name "Docker Desktop license notice" -Status "fail" -Detail "The Docker Desktop notice has not been acknowledged." -NextAction "Read and acknowledge Docker Desktop licensing before any Docker installer is opened."))
} else {
    $checks.Add((New-Check -Name "Docker Desktop license notice" -Status "pass" -Detail "The user acknowledged the Docker notice."))
}

if (Test-EveyCommand "docker.exe") {
    $dockerVersion = Invoke-EveyNative -FilePath "docker.exe" -Arguments @("--version") -LogFile $logFile
    $dockerMajor = Get-DockerMajorVersion -Text $dockerVersion.Stdout
    if ($dockerVersion.ExitCode -eq 0 -and $dockerMajor -ge 24) {
        $checks.Add((New-Check -Name "Docker version >= 24" -Status "pass" -Detail $dockerVersion.Stdout.Trim()))
    } else {
        $checks.Add((New-Check -Name "Docker version >= 24" -Status "fail" -Detail $dockerVersion.Stdout.Trim() -NextAction "Update Docker Desktop to Docker 24 or newer."))
    }

    $dockerInfo = Invoke-EveyNative -FilePath "docker.exe" -Arguments @("info") -LogFile $logFile
    if ($dockerInfo.ExitCode -eq 0) {
        $checks.Add((New-Check -Name "Docker daemon" -Status "pass" -Detail "Docker daemon is running."))
        if ($dockerInfo.Stdout -match 'OSType:\s*linux') {
            $checks.Add((New-Check -Name "Docker OSType linux" -Status "pass" -Detail "Docker is using Linux containers."))
        } else {
            $checks.Add((New-Check -Name "Docker OSType linux" -Status "fail" -Detail "Docker does not appear to be using Linux containers." -NextAction "Switch Docker Desktop to Linux containers / WSL 2 backend."))
        }
        if ($dockerInfo.Stdout -match 'Operating System:.*Docker Desktop|Context:.*desktop-linux|Name:.*docker-desktop') {
            $checks.Add((New-Check -Name "Docker Desktop backend" -Status "pass" -Detail "Docker Desktop / WSL 2 backend indicators were found."))
        } else {
            $checks.Add((New-Check -Name "Docker Desktop backend" -Status "warn" -Detail "Docker is running, but Docker Desktop backend was not confirmed." -NextAction "Confirm Docker Desktop is using the WSL 2 backend." -Required $false))
        }
    } else {
        $checks.Add((New-Check -Name "Docker daemon" -Status "fail" -Detail "Docker CLI is installed but daemon is not ready." -NextAction "Start Docker Desktop, wait for it to finish starting, then retry."))
        Add-Action -Actions $actions -Name "Start-EveyDockerDesktop" -Command "Start Docker Desktop and wait for docker info"
    }

    $compose = Invoke-EveyNative -FilePath "docker.exe" -Arguments @("compose", "version") -LogFile $logFile
    if ($compose.ExitCode -eq 0) {
        $checks.Add((New-Check -Name "docker compose" -Status "pass" -Detail $compose.Stdout.Trim()))
    } else {
        $checks.Add((New-Check -Name "docker compose" -Status "fail" -Detail "Docker Compose v2 is not available." -NextAction "Update Docker Desktop."))
    }
} else {
    $checks.Add((New-Check -Name "Docker version >= 24" -Status "fail" -Detail "docker.exe was not found." -NextAction "Install and start Docker Desktop."))
    $checks.Add((New-Check -Name "Docker daemon" -Status "fail" -Detail "Docker cannot be checked without docker.exe." -NextAction "Install Docker Desktop."))
    $checks.Add((New-Check -Name "docker compose" -Status "fail" -Detail "Docker Compose cannot be checked without docker.exe." -NextAction "Install Docker Desktop."))
}

foreach ($port in @(4000, 8642, 11434, 1883, 8888, 6333, 2586, 5678, 3100, 3001)) {
    if (Test-EveyPortFree -Port $port) {
        $checks.Add((New-Check -Name "Port $port" -Status "pass" -Detail "Port $port appears available."))
    } else {
        $checks.Add((New-Check -Name "Port $port" -Status "fail" -Detail "Port $port is already in use." -NextAction "Close the app using port $port or choose a clean machine."))
    }
}

$requiredFailures = @($checks | Where-Object { $_.required -and $_.status -eq "fail" })
$report = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    installDirectory = $InstallDirectory
    logDirectory = $logDir
    acceptedDockerNotice = [bool]$AcceptDockerNotice
    passed = ($requiredFailures.Count -eq 0)
    checks = $checks
    actions = $actions
    pendingRestartReason = if ([bool]($actions | Where-Object { $_.mayRequireRestart })) { "A prerequisite action may require a Windows restart." } else { "" }
    nextActions = @($checks | Where-Object { $_.status -ne "pass" -and $_.nextAction } | ForEach-Object { $_.nextAction })
}

Write-EveyJson -InputObject $report -Path $JsonPath | Out-Null
Write-EveyLog -Message "Prerequisite report written to $JsonPath" -LogFile $logFile

if ($FailOnError -and -not $report.passed) {
    exit 20
}

$report
