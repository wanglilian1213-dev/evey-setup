# Windows installer

This page explains the Windows one-click installer for Evey Setup.

The installer is designed for non-technical Windows users. A user starts
`EveySetup.exe`, chooses the stack size, optionally enters model provider keys
and URLs, and lets the installer check the PC and deploy the Docker Compose
stack.

## What the installer does

- Checks Windows version, memory, disk, virtualization, ports, WSL 2, Git,
  Docker Desktop, Docker daemon, and Docker Compose.
- Shows a Docker Desktop licensing notice before any Docker install page or
  Docker installer is opened.
- Writes `.env` without passing API keys on command lines.
- Lets the user leave model provider keys blank and configure models or account
  login after deployment.
- Saves non-secret resume state at `%ProgramData%\EveySetup\install-state.json`.
- Saves logs at `%ProgramData%\EveySetup\logs\<UTC timestamp>\`.
- Deploys the selected tier with Docker Compose.
- Runs a final verification check.

## What it does not do

- It does not silently accept Docker Desktop terms.
- It does not make payments or accept paid Docker licensing for the user.
- It does not hide a required Windows restart.
- It does not make an unsigned build public-ready.

## Requirements

- Windows 11 23H2 or newer is the required release-test target.
- This internal build blocks older Windows releases. Windows 10 can be claimed
  only after a separate tested installer path is added.
- WSL 2 must be enabled.
- Docker Desktop must be installed and running with Linux containers.
- Git for Windows must be installed.
- The installer can deploy without model provider keys. OpenAI, Kimi, Qwen,
  GLM, and OpenRouter provider fields are available if the user wants to
  configure key and URL values during install.
- At least 10 GB free disk is recommended.
- 8 GB RAM is recommended. Start with the `base` tier on small machines.

## Build

Install Inno Setup 6 on a Windows build machine, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\build\Build-WindowsInstaller.ps1
```

The output file is named like:

```text
dist\EveySetup-0.1.0-internal-test.exe
```

The `internal-test` label is intentional. Public release requires code signing.
Run the build script with `-RequireSigned` only after a signing step has been
added.

## Real Windows evidence gate

Do not say the installer works until a real Windows 11 run proves it. Static
checks from macOS or Linux are not enough.

Required evidence must be saved under:

```text
test-results/windows/<UTC date>/<case-id>/
```

Required cases:

| Case ID | Environment | Must prove |
|---|---|---|
| `win11-clean-prereq` | Windows 11 23H2 or newer clean real machine/VM, no Docker/Git/WSL | prerequisite detection, user approvals, admin prompts, Docker license notice, restart/re-run resume |
| `win11-ready-base` | Windows 11 23H2 or newer with WSL 2, Docker Desktop latest stable, Git latest stable | base-tier install succeeds end to end |
| `win11-docker-stopped` | Windows 11 23H2 or newer with Docker Desktop installed but daemon stopped | Docker start/wait/retry handling |
| `win10-ready-base-optional` | Windows 10 22H2 x64 with WSL 2, Docker Desktop, Git | only required if Windows 10 support is claimed |

Each case should include:

- installer log with API keys masked
- prerequisite JSON report
- final screen screenshot or transcript with no visible keys
- `docker version`
- `docker compose version`
- `wsl -l -v`
- `docker compose ps`
- health check output for selected tier
- proof that `.env` is permission-restricted and not copied into logs

## Manual script use

For maintainers, the main script can be run directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\scripts\Install-Evey.ps1 -InstallDirectory "$env:USERPROFILE\evey-stack" -Tier base -PluginPreset core -AcceptDockerNotice
```

Do not pass model provider, Telegram, Discord, or internal keys as command-line
arguments. The script prompts for optional values or uses the `.env` written by
the installer. Model provider values can also be configured later after Hermes
is deployed.
