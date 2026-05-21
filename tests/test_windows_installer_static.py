from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_windows_installer_files_exist():
    for path in [
        "windows/install/EveySetup.iss",
        "windows/scripts/EveyCommon.ps1",
        "windows/scripts/Install-Evey.ps1",
        "windows/scripts/Test-EveyPrereqs.ps1",
        "windows/scripts/Deploy-EveyStack.ps1",
        "windows/scripts/Test-EveyInstall.ps1",
        "windows/build/Build-WindowsInstaller.ps1",
        "docs/windows-install.md",
    ]:
        assert (ROOT / path).is_file(), path


def test_installer_collects_secrets_without_command_line_handoff():
    iss = read("windows/install/EveySetup.iss")
    install = read("windows/scripts/Install-Evey.ps1")
    deploy = read("windows/scripts/Deploy-EveyStack.ps1")

    assert "SecretPage.Add('OpenRouter API key:', True)" in iss
    assert "SecretPage.Add('Telegram bot token (optional):', True)" in iss
    assert "SecretPage.Add('Discord bot token (optional):', True)" in iss
    assert "OPENROUTER_API_KEY" in iss
    assert "TELEGRAM_BOT_TOKEN" in iss
    assert "DISCORD_BOT_TOKEN" in iss
    assert "icacls" in iss.lower() or "Protect-EveyFile" in deploy
    assert "DefaultDirName={localappdata}\\EveyStack" in iss
    assert "ResultCode <> 0" in iss
    assert "RaiseException('Could not restrict .env file permissions.')" in iss
    assert "[Run]" not in iss
    assert "RunInstallFlow" in iss
    assert "Evey setup did not finish successfully" in iss

    forbidden_params = [
        "OpenRouterKey",
        "TelegramBotToken",
        "DiscordBotToken",
        "LITELLM_MASTER_KEY",
    ]
    for script in [install, deploy]:
        param_block = script.split(")", 1)[0]
        for forbidden in forbidden_params:
            assert forbidden not in param_block

    assert "command-line" in deploy.lower()
    assert "Protect-EveyFile" in deploy


def test_prereq_checker_covers_windows_docker_wsl_git_and_resume_state():
    prereq = read("windows/scripts/Test-EveyPrereqs.ps1")
    install = read("windows/scripts/Install-Evey.ps1")
    common = read("windows/scripts/EveyCommon.ps1")

    required_terms = [
        "Windows",
        "WSL",
        "Docker",
        "Docker Desktop",
        "docker compose",
        "Git",
        "Virtualization",
        "4000",
        "8642",
        "11434",
        "AcceptDockerNotice",
    ]
    for term in required_terms:
        assert term in prereq

    assert "buildNumber -ge 22631" in prereq
    assert "Windows 11 23H2 or newer" in prereq
    assert "install-state.json" in install
    assert "Save-EveyState" in install
    assert "Read-EveyState" in common
    assert "OPENROUTER_API_KEY" not in common.split("function Assert-EveyStateHasNoSecrets", 1)[0]


def test_deploy_runner_reuses_existing_stack_contracts():
    deploy = read("windows/scripts/Deploy-EveyStack.ps1")

    for path in [
        "config/litellm.yaml",
        "config/mosquitto",
        "config/searxng",
        "data/hermes/plugins",
        "data/hermes/cron",
        "data/claude-bridge",
        "src/hermes-agent",
    ]:
        assert path in deploy

    for tier in ["base", "services", "full"]:
        assert f"docker-compose.{tier}.yml" in deploy

    assert "NousResearch/hermes-agent" in deploy
    assert "42-evey/hermes-plugins" in deploy
    assert "docker compose up -d --build" in deploy
    assert "nvidia-smi" in deploy
    assert "Could not clone plugin repository" in deploy
    assert "Could not update plugin repository" in deploy
    assert "Required plugin $name was not found" in deploy
    assert "Plugin helper evey_utils.py was not found" in deploy


def test_verifier_and_docs_define_real_windows_evidence_gate():
    verifier = read("windows/scripts/Test-EveyInstall.ps1")
    docs = read("docs/windows-install.md")
    build = read("windows/build/Build-WindowsInstaller.ps1")

    for term in [
        "docker compose ps",
        "http://localhost:4000/health/liveliness",
        "http://localhost:8642/health",
        "test-results/windows",
        "win11-ready-base",
        "Windows 11",
    ]:
        assert term in verifier or term in docs

    assert "ISCC" in build
    assert "internal-test" in build
    assert "code-sign" in docs.lower() or "code signing" in docs.lower()
    assert "StatusCode -lt 400" in verifier
    assert "StatusCode -lt 500" not in verifier


def test_install_flow_cannot_report_success_after_verifier_failure():
    install = read("windows/scripts/Install-Evey.ps1")
    verifier = read("windows/scripts/Test-EveyInstall.ps1")

    assert '"-FailOnError"' in install
    assert "exit 30" in verifier
    assert "installStatus = \"failed\"" in install
    assert "installStatus = \"success\"" in install
    assert "Evey setup finished" not in install
    assert "installStatus = \"skipped-deploy\"" in install
    assert "Deployment was skipped, so the installer cannot report success." in install


def test_prereq_checker_guides_actions_and_docker_backend_checks():
    prereq = read("windows/scripts/Test-EveyPrereqs.ps1")
    install = read("windows/scripts/Install-Evey.ps1")

    for term in [
        "Install-EveyPrerequisite",
        "wsl --install",
        "winget",
        "Start-EveyDockerDesktop",
        "pendingRestartReason",
        "Docker version >= 24",
        "OSType",
        "linux",
    ]:
        assert term in prereq or term in install


def test_secret_state_and_acl_failures_are_blocked():
    common = read("windows/scripts/EveyCommon.ps1")
    install = read("windows/scripts/Install-Evey.ps1")

    assert "Assert-EveyStateHasNoSecrets" in common
    assert "Secret-like value found in installer state" in common
    assert "System.Collections.IDictionary" in common
    assert "icacls.exe failed" in common
    assert "WindowsIdentity" in common
    assert "*S-1-5-18:F" in common
    assert "$LASTEXITCODE -ne 0" in common
    assert "$global:LASTEXITCODE = 0" in common
    assert '$ErrorActionPreference = "Continue"' in common
    assert "$previousErrorActionPreference" in common
    assert "Assert-EveyStateHasNoSecrets" in install
    assert "[hashtable]$State" not in common
    assert "[hashtable]$State" not in install
    assert "$IsWindows" not in common
