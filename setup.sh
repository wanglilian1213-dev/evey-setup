#!/bin/bash
# Hermes Agent Stack Setup — Phase 1: Foundation
# Prerequisites, directory scaffold, .env generation, config files
#
# Usage: bash setup.sh [install-dir]
# Next:  bash setup-services.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ── Banner ──
echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "   Hermes Agent Stack Setup — Phase 1 of 4"
echo "          Foundation & Configuration"
echo "  ============================================"
echo -e "${NC}"

# ══════════════════════════════════════════════
# PREREQUISITES
# ══════════════════════════════════════════════

log "Checking prerequisites..."

# Docker binary
if ! command -v docker &>/dev/null; then
    err "Docker not found. Install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Docker version >= 24
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
if [ "$DOCKER_MAJOR" -lt 24 ] 2>/dev/null; then
    err "Docker version $DOCKER_VERSION is too old. Need >= 24.0."
    err "Update: https://docs.docker.com/engine/install/"
    exit 1
fi
log "  Docker $DOCKER_VERSION"

# Docker Compose v2
if docker compose version &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    log "  Docker Compose $COMPOSE_VERSION"
elif docker-compose version &>/dev/null; then
    err "docker-compose v1 detected. Need Docker Compose v2 (docker compose)."
    err "Update: https://docs.docker.com/compose/install/"
    exit 1
else
    err "Docker Compose not found. Install docker-compose-plugin."
    exit 1
fi

# Docker daemon running
if ! docker info &>/dev/null; then
    err "Docker daemon is not running. Start Docker first."
    exit 1
fi
log "  Docker daemon is running"

# Git
if ! command -v git &>/dev/null; then
    err "git not found. Install git first."
    exit 1
fi
log "  git found"

# Disk space (need >= 5GB free)
if command -v df &>/dev/null; then
    FREE_KB=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 5242880 ] 2>/dev/null; then
        FREE_GB=$(( FREE_KB / 1048576 ))
        err "Only ${FREE_GB}GB free disk space. Need at least 5GB."
        exit 1
    fi
    if [ -n "$FREE_KB" ]; then
        FREE_GB=$(( FREE_KB / 1048576 ))
        log "  ${FREE_GB}GB free disk space"
    fi
fi

echo ""

# ══════════════════════════════════════════════
# INSTALL DIRECTORY
# ══════════════════════════════════════════════

if [ -n "${1:-}" ]; then
    INSTALL_DIR="$1"
    log "Install directory: $INSTALL_DIR (from argument)"
else
    ask "Install directory" "$HOME/hermes-stack"
    INSTALL_DIR="$REPLY"
fi

# Check for existing install
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/.env" ]; then
    warn "Existing installation found at $INSTALL_DIR"
    ask "Overwrite configs? Data directories will be preserved (y/N)" "N"
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        log "Aborted. Existing install preserved."
        exit 0
    fi
fi

echo ""

# ══════════════════════════════════════════════
# API KEYS
# ══════════════════════════════════════════════

log "Optional model provider setup"
echo ""
echo "You can deploy Hermes now and configure models or account login later."
echo ""

ask "OpenAI API key (optional, Enter to skip)" ""
OPENAI_KEY="$REPLY"

ask "OpenAI API URL" "https://api.openai.com/v1"
OPENAI_BASE="$REPLY"

ask "Kimi / Moonshot API key (optional, Enter to skip)" ""
MOONSHOT_KEY="$REPLY"

ask "Kimi / Moonshot API URL" "https://api.moonshot.ai/v1"
MOONSHOT_BASE="$REPLY"

ask "Qwen / DashScope API key (optional, Enter to skip)" ""
DASHSCOPE_KEY="$REPLY"

ask "Qwen / DashScope API URL" "https://dashscope.aliyuncs.com/compatible-mode/v1"
DASHSCOPE_BASE="$REPLY"

ask "GLM / Z.AI API key (optional, Enter to skip)" ""
ZAI_KEY="$REPLY"

ask "GLM / Z.AI API URL" "https://api.z.ai/api/paas/v4"
ZAI_BASE="$REPLY"

ask "OpenRouter API key (optional, Enter to skip)" ""
OPENROUTER_KEY="$REPLY"

ask "OpenRouter API URL" "https://openrouter.ai/api/v1"
OPENROUTER_BASE="$REPLY"

echo ""
ask "Telegram bot token (from @BotFather, or Enter to skip)" ""
TELEGRAM_TOKEN="$REPLY"

ask "Discord bot token (from discord.com/developers/applications, or Enter to skip)" ""
DISCORD_TOKEN="$REPLY"

echo ""

# ══════════════════════════════════════════════
# GENERATE SECRETS
# ══════════════════════════════════════════════

log "Generating secure keys..."

LITELLM_KEY="sk-litellm-$(gen_key 16)"
API_KEY="sk-api-$(gen_key 8)"
# Pre-generate full-tier secrets (cheap, user may upgrade tier later)
N8N_DB_PASS="$(gen_key 16)"
LANGFUSE_DB_PASS="$(gen_key 16)"
NEXTAUTH_SECRET="$(gen_key 32)"
LANGFUSE_SALT="$(gen_key 16)"
LANGFUSE_PUB="pk-lf-$(gen_key 12)"
LANGFUSE_SEC="sk-lf-$(gen_key 16)"

log "  Keys generated"

echo ""

# ══════════════════════════════════════════════
# SCAFFOLD DIRECTORY STRUCTURE
# ══════════════════════════════════════════════

log "Scaffolding $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"

# Config directories
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/config/mosquitto"
mkdir -p "$INSTALL_DIR/config/searxng"

# Data directories — hermes agent
mkdir -p "$INSTALL_DIR/data/hermes/plugins"
mkdir -p "$INSTALL_DIR/data/hermes/skills"
mkdir -p "$INSTALL_DIR/data/hermes/cron"
mkdir -p "$INSTALL_DIR/data/hermes/memories"
mkdir -p "$INSTALL_DIR/data/hermes/workspace"

# Data directories — claude bridge
mkdir -p "$INSTALL_DIR/data/claude-bridge/inbox"
mkdir -p "$INSTALL_DIR/data/claude-bridge/outbox"

# Data directories — services (create all, even if tier is base — no harm)
mkdir -p "$INSTALL_DIR/data/mqtt"
mkdir -p "$INSTALL_DIR/data/qdrant"
mkdir -p "$INSTALL_DIR/data/ntfy"
mkdir -p "$INSTALL_DIR/data/n8n"
mkdir -p "$INSTALL_DIR/data/uptimekuma"

# Build & source directories
mkdir -p "$INSTALL_DIR/dockerfiles"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/src"

log "  Directory structure created"

# ══════════════════════════════════════════════
# CLONE HERMES-AGENT
# ══════════════════════════════════════════════

if [ ! -d "$INSTALL_DIR/src/hermes-agent" ]; then
    log "Cloning hermes-agent..."
    git clone --depth 1 https://github.com/NousResearch/hermes-agent.git "$INSTALL_DIR/src/hermes-agent"
else
    log "  hermes-agent source already present"
fi

# ══════════════════════════════════════════════
# WRITE .env
# ══════════════════════════════════════════════

log "Writing .env ..."

cat > "$INSTALL_DIR/.env" << ENVEOF
# Hermes Stack — generated by setup.sh
# Modify values as needed, then run: bash setup-services.sh

# --- Core API Keys ---
OPENAI_API_KEY=${OPENAI_KEY}
OPENAI_API_BASE=${OPENAI_BASE}
MOONSHOT_API_KEY=${MOONSHOT_KEY}
MOONSHOT_API_BASE=${MOONSHOT_BASE}
DASHSCOPE_API_KEY=${DASHSCOPE_KEY}
DASHSCOPE_API_BASE=${DASHSCOPE_BASE}
ZAI_API_KEY=${ZAI_KEY}
ZAI_API_BASE=${ZAI_BASE}
OPENROUTER_API_KEY=${OPENROUTER_KEY}
OPENROUTER_API_BASE=${OPENROUTER_BASE}
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}
DISCORD_BOT_TOKEN=${DISCORD_TOKEN}

# --- Internal Service Keys (auto-generated) ---
LITELLM_MASTER_KEY=${LITELLM_KEY}
API_SERVER_KEY=${API_KEY}

# --- n8n Database ---
N8N_DB_PASSWORD=${N8N_DB_PASS}

# --- Langfuse ---
LANGFUSE_DB_PASSWORD=${LANGFUSE_DB_PASS}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
LANGFUSE_SALT=${LANGFUSE_SALT}
LANGFUSE_PUBLIC_KEY=${LANGFUSE_PUB}
LANGFUSE_SECRET_KEY=${LANGFUSE_SEC}

# --- Timezone ---
TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
ENVEOF

chmod 600 "$INSTALL_DIR/.env"
log "  .env written (permissions: 600)"

# ══════════════════════════════════════════════
# WRITE .gitignore
# ══════════════════════════════════════════════

cat > "$INSTALL_DIR/.gitignore" << 'GIEOF'
.env
data/
*.log
__pycache__/
.DS_Store
GIEOF

log "  .gitignore written"

# ══════════════════════════════════════════════
# WRITE CONFIG FILES
# ══════════════════════════════════════════════

log "Writing config files..."

# ── LiteLLM config ──
cp "$SCRIPT_DIR/templates/litellm.yaml" "$INSTALL_DIR/config/litellm.yaml"

log "  config/litellm.yaml"

# ── Mosquitto config ──
cat > "$INSTALL_DIR/config/mosquitto/mosquitto.conf" << 'MQEOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
MQEOF

log "  config/mosquitto/mosquitto.conf"

# ── SearXNG settings ──
SEARXNG_SECRET="$(gen_key 16)"
cat > "$INSTALL_DIR/config/searxng/settings.yml" << SXEOF
use_default_settings: true
server:
  secret_key: "${SEARXNG_SECRET}"
  limiter: false
search:
  safe_search: 0
  autocomplete: ""
  default_lang: "en"
SXEOF

log "  config/searxng/settings.yml"

# ── Init files ──
if [ ! -f "$INSTALL_DIR/data/claude-bridge/channel.jsonl" ]; then
    touch "$INSTALL_DIR/data/claude-bridge/channel.jsonl"
fi
if [ ! -f "$INSTALL_DIR/data/hermes/cron/jobs.json" ]; then
    echo '[]' > "$INSTALL_DIR/data/hermes/cron/jobs.json"
fi

# ══════════════════════════════════════════════
# SAVE STATE FOR NEXT PHASES
# ══════════════════════════════════════════════

cat > "$SCRIPT_DIR/.setup-state" << STEOF
INSTALL_DIR=${INSTALL_DIR}
STEOF

# ══════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════

echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "        Phase 1 Complete — Foundation"
echo "  ============================================"
echo -e "${NC}"
echo "  Install directory:  $INSTALL_DIR"
echo "  Model keys:         optional; configure now or later"
echo "  Telegram token:     ${TELEGRAM_TOKEN:+set}${TELEGRAM_TOKEN:-skipped}"
echo "  Discord token:      ${DISCORD_TOKEN:+set}${DISCORD_TOKEN:-skipped}"
echo ""
echo "  Created:"
echo "    .env               API keys + generated secrets"
echo "    config/             litellm.yaml, mosquitto, searxng"
echo "    data/hermes/        plugins, skills, cron, memories"
echo "    data/claude-bridge/ inbox, outbox"
echo "    src/hermes-agent/   cloned from NousResearch"
echo ""
echo -e "  ${BOLD}Next: bash setup-services.sh${NC}"
echo "  Pick a service tier and start Docker containers."
echo ""
