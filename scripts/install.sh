#!/usr/bin/env bash
# Установка и обновление agentcell:
#   1. собирает Docker-образ (внутри устанавливается Claude Code);
#   2. копирует скрипт scripts/agentcell в папку BIN_DIR.
# Повторный запуск обновляет Claude Code до свежей версии.
#
# Настройки через переменные окружения:
#   CLAUDE_CODE_VERSION  закрепить версию Claude Code (по умолчанию latest)
#   BIN_DIR              куда положить команду agentcell (по умолчанию ~/bin)
#   AGENTCELL_IMAGE      имя Docker-образа (по умолчанию agentcell)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${AGENTCELL_IMAGE:-agentcell}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"

if ! docker info >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Darwin" ]; then
        echo "ERROR: Docker is not available. Install and start it: brew install docker colima && colima start" >&2
    else
        echo "ERROR: Docker is not available. Install it (sudo apt install docker.io), add your user to the 'docker' group and log in again." >&2
    fi
    exit 1
fi

# --pull и --no-cache нужны, чтобы повторный запуск действительно обновлял
# Claude Code: иначе Docker возьмёт из кэша старый слой с npm install.
# Dockerfile подаётся через stdin, чтобы docker не отправлял в сборку всю папку проекта.
echo "INFO: Building image '$IMAGE' (fresh install, no cache)..."
docker build --pull --no-cache \
    --build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION:-latest}" \
    -t "$IMAGE" - < "$ROOT_DIR/Dockerfile"

mkdir -p "$BIN_DIR"
install -m 755 "$ROOT_DIR/scripts/agentcell" "$BIN_DIR/agentcell"
echo "OK: Launcher installed to $BIN_DIR/agentcell"

case ":$PATH:" in
    *":$BIN_DIR:"*)
        echo "OK: $BIN_DIR is already in PATH"
        ;;
    *)
        echo "WARN: $BIN_DIR is not in PATH. Add it:"
        echo "      echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc   (bash: ~/.bashrc)"
        ;;
esac

echo ""
echo "Next: cd into a project folder and run: agentcell"
