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

    for label in [
        "OpenAI API key (optional):",
        "Kimi / Moonshot API key (optional):",
        "Qwen / DashScope API key (optional):",
        "GLM / Z.AI API key (optional):",
        "OpenRouter API key (optional):",
    ]:
        assert f"SecretPage.Add('{label}', True)" in iss
    assert "SecretPage.Add('Telegram bot token (optional):', True)" in iss
    assert "SecretPage.Add('Discord bot token (optional):', True)" in iss
    for env_name in [
        "OPENAI_API_KEY",
        "MOONSHOT_API_KEY",
        "DASHSCOPE_API_KEY",
        "ZAI_API_KEY",
        "OPENROUTER_API_KEY",
        "TELEGRAM_BOT_TOKEN",
        "DISCORD_BOT_TOKEN",
    ]:
        assert env_name in iss
    assert "icacls" in iss.lower() or "Protect-EveyFile" in deploy
    assert "DefaultDirName={localappdata}\\EveyStack" in iss
    assert "ResultCode <> 0" in iss
    assert "RaiseException('Could not restrict .env file permissions.')" in iss
    assert "[Run]" not in iss
    assert "RunInstallFlow" in iss
    assert "Evey setup did not finish successfully" in iss
    assert "ShouldSkipPage" in iss
    assert "ExistingInstallerEnvAvailable" in iss
    assert "ProtectInstallerEnv" in iss
    assert "WizardSilent" in iss
    assert "DockerNoticeAcceptedByParam" in iss
    assert "AcceptDockerNotice|}" in iss
    assert "CustomSetupExitCode: Integer" in iss
    assert "function GetCustomSetupExitCode" in iss
    assert "CustomSetupExitCode := ResultCode" in iss
    assert "At least one AI provider API key is required." not in iss
    assert "At least one AI provider API key is required." not in install
    assert "At least one AI provider API key is required." not in deploy
    assert "OpenRouter API key is required." not in iss
    assert "OpenRouter API key is required." not in install
    assert "Test-EveyHasModelProviderKey" not in install
    assert "Test-EveyHasModelProviderKey" not in deploy
    assert "function HasModelProviderKey" not in iss
    assert "ProviderUrlPage" in iss
    for label in [
        "OpenAI API URL:",
        "Kimi / Moonshot API URL:",
        "Qwen / DashScope API URL:",
        "GLM / Z.AI API URL:",
        "OpenRouter API URL:",
    ]:
        assert f"ProviderUrlPage.Add('{label}', False)" in iss

    forbidden_params = [
        "OpenRouterKey",
        "OpenAiKey",
        "MoonshotKey",
        "DashscopeKey",
        "ZaiKey",
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
    for env_name in [
        "OPENAI_API_KEY",
        "MOONSHOT_API_KEY",
        "DASHSCOPE_API_KEY",
        "ZAI_API_KEY",
        "OPENROUTER_API_KEY",
    ]:
        assert env_name not in common.split("function Assert-EveyStateHasNoSecrets", 1)[0]


def test_model_provider_support_is_not_openrouter_only():
    litellm = read("templates/litellm.yaml")
    base = read("templates/docker-compose.base.yml")
    services = read("templates/docker-compose.services.yml")
    full = read("templates/docker-compose.full.yml")
    setup = read("setup.sh")
    env_template = read("templates/.env.template")
    docs = read("docs/windows-install.md")
    readme = read("README.md")
    workflow = read(".github/workflows/windows-installer-validation.yml")

    required_routes = {
        "openai-main": ("openai/", "OPENAI_API_KEY", "OPENAI_API_BASE"),
        "kimi-main": ("moonshot/", "MOONSHOT_API_KEY", "MOONSHOT_API_BASE"),
        "qwen-main": ("dashscope/", "DASHSCOPE_API_KEY", "DASHSCOPE_API_BASE"),
        "glm-main": ("zai/", "ZAI_API_KEY", "ZAI_API_BASE"),
        "openrouter-main": ("openrouter/", "OPENROUTER_API_KEY", "OPENROUTER_API_BASE"),
    }
    for route, (prefix, env_name, base_env_name) in required_routes.items():
        assert f"model_name: {route}" in litellm
        assert f"model: {prefix}" in litellm
        assert f"api_key: os.environ/{env_name}" in litellm
        assert f"api_base: os.environ/{base_env_name}" in litellm
    assert "api_base: os.environ/OPENAI_API_BASE" in litellm

    for compose in [base, services, full]:
        for env_name in [
            "OPENAI_API_KEY",
            "OPENAI_API_BASE",
            "MOONSHOT_API_KEY",
            "MOONSHOT_API_BASE",
            "DASHSCOPE_API_KEY",
            "DASHSCOPE_API_BASE",
            "ZAI_API_KEY",
            "ZAI_API_BASE",
            "OPENROUTER_API_KEY",
            "OPENROUTER_API_BASE",
        ]:
            assert f"{env_name}: ${{{env_name}}}" in compose

    assert "OpenRouter key" not in docs
    assert "OpenRouter API key is required" not in docs
    assert "At least one of OpenAI, Kimi, Qwen, GLM, or OpenRouter" not in docs
    assert "can deploy without model provider keys" in docs
    assert "OpenRouter API key**" not in readme
    assert "OPENAI_API_KEY=" in workflow
    assert "OPENAI_API_KEY=sk-ci-placeholder-value" not in workflow
    assert "OPENAI_API_BASE=https://api.openai.com/v1" in workflow
    assert "MOONSHOT_API_KEY=" in workflow
    assert "MOONSHOT_API_BASE=https://api.moonshot.ai/v1" in workflow
    assert "DASHSCOPE_API_KEY=" in workflow
    assert "DASHSCOPE_API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1" in workflow
    assert "ZAI_API_KEY=" in workflow
    assert "ZAI_API_BASE=https://api.z.ai/api/paas/v4" in workflow
    assert "OPENROUTER_API_BASE=https://openrouter.ai/api/v1" in workflow
    smoke_step = workflow.split("- name: Smoke-test generated installer on hosted Windows", 1)[1]
    smoke_step = smoke_step.split("- name: Upload validation artifacts", 1)[0]
    assert 'Set-Content -LiteralPath (Join-Path $setupDir ".env")' not in smoke_step
    assert "Generated installer did not create .env without preseeded provider keys." in smoke_step
    assert "env.generated" in smoke_step

    for source in [setup, env_template]:
        for env_name in [
            "OPENAI_API_KEY",
            "OPENAI_API_BASE",
            "MOONSHOT_API_KEY",
            "MOONSHOT_API_BASE",
            "DASHSCOPE_API_KEY",
            "DASHSCOPE_API_BASE",
            "ZAI_API_KEY",
            "ZAI_API_BASE",
            "OPENROUTER_API_KEY",
            "OPENROUTER_API_BASE",
        ]:
            assert env_name in source
        assert "fill at least one" not in source
    assert "OpenRouter key — brain model will not work" not in setup
    assert "At least one AI provider API key is required." not in setup
    assert "cp \"$SCRIPT_DIR/templates/litellm.yaml\"" in setup


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
    assert "InputObject -is [pscustomobject]" in common
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
