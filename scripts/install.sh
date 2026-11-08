#!/usr/bin/env bash
# Установка и обновление agentcell:
#   1. выбранные плагины копируются в ~/.config/agentcell/plugins/<имя>/;
#   2. только macOS: создаётся шаблон конфига и собственная VM Colima (профиль agentcell);
#   3. собирается Docker-образ (внутри Claude Code и то, что нужно установленным плагинам);
#   4. скрипт scripts/agentcell копируется в папку BIN_DIR.
# Повторный запуск обновляет Claude Code и код плагинов. VM при этом не перезапускается,
# если конфиг не менялся.
#
# Использование:
#   ./scripts/install.sh                  ядро и уже установленные плагины
#   ./scripts/install.sh --with kind      ядро и плагин kind (флаг можно повторять)
#   ./scripts/install.sh --without kind   убрать плагин kind вместе с его настройками
# Список плагинов и правила: docs/PLUGINS.md.
#
# Настройки через переменные окружения:
#   CLAUDE_CODE_VERSION  закрепить версию Claude Code (по умолчанию latest)
#   KUBECTL_VERSION      другая версия kubectl, если он нужен плагину (по умолчанию — из Dockerfile)
#   BIN_DIR              куда положить команду agentcell (по умолчанию ~/bin)
#   AGENTCELL_IMAGE      имя Docker-образа (по умолчанию agentcell)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${AGENTCELL_IMAGE:-agentcell}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
CONFIG_DIR="$HOME/.config/agentcell"
CONFIG_FILE="$CONFIG_DIR/config"
PLUGINS_DIR="$CONFIG_DIR/plugins"   # куда ставятся плагины (там же их настройки)
PLUGINS_SRC="$ROOT_DIR/plugins"     # плагины в репозитории

# Должно совпадать с DOCKER_CONTEXT_NAME в scripts/agentcell.
DOCKER_CONTEXT_NAME="colima-agentcell"

PLATFORM=linux
if [ "$(uname -s)" = "Darwin" ]; then
    PLATFORM=macos
fi

die() {
    echo "ERROR: $1" >&2
    shift
    local line
    for line in "$@"; do
        echo "       $line" >&2
    done
    exit 1
}

# Значение поля из манифеста плагина (КЛЮЧ=значение). Нет файла или поля — пустая строка.
# Копия функции из scripts/agentcell: скрипты самодостаточны, поэтому держим их в синхроне.
manifest_get() {
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1" 2>/dev/null || true
}

# Имя плагина: только a-z и 0-9 (по нему называются функции плагина).
check_plugin_name() {
    case "$1" in
        ''|*[!a-z0-9]*) die "Bad plugin name '$1': use only a-z and 0-9." ;;
    esac
}

# Имена установленных плагинов через пробел.
installed_plugins() {
    local dir out=""
    for dir in "$PLUGINS_DIR"/*/; do
        if [ -f "${dir}plugin.sh" ]; then
            out="$out $(basename "$dir")"
        fi
    done
    echo "$out"
}

# Манифест плагина: из репозитория, а если там его нет — из установленной копии.
plugin_manifest() {
    if [ -f "$PLUGINS_SRC/$1/plugin.conf" ]; then
        echo "$PLUGINS_SRC/$1/plugin.conf"
    else
        echo "$PLUGINS_DIR/$1/plugin.conf"
    fi
}

# Шаблон конфига для macOS. Папок по умолчанию нет: их нужно вписать явно.
write_config_template() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'EOF'
# Конфиг agentcell (только macOS). Формат: КЛЮЧ=значение, без пробелов вокруг "=" и
# без кавычек. Строки с # — комментарии. После изменения выполните: agentcell --vm-apply

# Папки, в которых лежат ваши проекты. Только их (и хранилище agentcell) видит VM
# agentcell, и только внутри них можно запускать agentcell. По строке на папку.
# Нельзя: домашнюю папку целиком, а также ~/.ssh, ~/.kube, ~/.aws, ~/.gnupg, ~/.docker,
# ~/.config, ~/Library и папки, которые их содержат.
# Пример:
# PROJECT_DIR=~/src
# PROJECT_DIR=~/Documents/infra

# Ресурсы VM: процессоры, память (ГиБ), диск (ГиБ, можно только увеличивать).
VM_CPU=4
VM_MEMORY=6
VM_DISK=60

# Доступ контейнеров к сервисам, которые слушают localhost вашего Мака (локальные базы, панели,
# dev-серверы): 0 — оставить как есть, 1 — закрыть правилом межсетевого экрана в VM.
# После изменения выполните: agentcell --vm-apply
BLOCK_HOST_ACCESS=0
EOF
}

# --- Разбор аргументов ---------------------------------------------------------------

WITH=""      # плагины, которые нужно поставить, через пробел
WITHOUT=""   # плагины, которые нужно убрать, через пробел
while [ $# -gt 0 ]; do
    case "$1" in
        --with)
            [ $# -ge 2 ] || die "--with needs a plugin name."
            WITH="$WITH $2"
            shift 2
            ;;
        --without)
            [ $# -ge 2 ] || die "--without needs a plugin name."
            WITHOUT="$WITHOUT $2"
            shift 2
            ;;
        *)
            die "Unknown argument: $1" "Usage: ./scripts/install.sh [--with <plugin>] [--without <plugin>]"
            ;;
    esac
done

# --- Плагины: проверка до любых изменений ----------------------------------------------

for name in $WITH; do
    check_plugin_name "$name"
    [ -f "$PLUGINS_SRC/$name/plugin.sh" ] \
        || die "Unknown plugin '$name'." "Available plugins: $(ls "$PLUGINS_SRC" | tr '\n' ' ')"
    bash -n "$PLUGINS_SRC/$name/plugin.sh" || die "Plugin '$name' has a syntax error in plugin.sh."
    platforms="$(manifest_get "$PLUGINS_SRC/$name/plugin.conf" PLATFORMS)"
    if [ -n "$platforms" ]; then
        case " $platforms " in
            *" $PLATFORM "*) ;;
            *) die "Plugin '$name' supports only: $platforms. This system is: $PLATFORM." ;;
        esac
    fi
done
for name in $WITHOUT; do
    check_plugin_name "$name"
done

# Итоговый набор: установленные плагины без убираемых плюс новые.
FINAL=""
for name in $(installed_plugins); do
    case " $WITHOUT " in
        *" $name "*) continue ;;
    esac
    FINAL="$FINAL $name"
done
for name in $WITH; do
    case " $FINAL " in
        *" $name "*) ;;
        *) FINAL="$FINAL $name" ;;
    esac
done

# Несовместимые плагины вместе не ставятся (поле CONFLICTS манифеста).
for name in $FINAL; do
    for other in $(manifest_get "$(plugin_manifest "$name")" CONFLICTS); do
        case " $FINAL " in
            *" $other "*)
                die "Plugins '$name' and '$other' cannot be used together." \
                    "Choose one: ./scripts/install.sh --without $other"
                ;;
        esac
    done
done

# --- Плагины: установка и удаление -------------------------------------------------------

for name in $WITHOUT; do
    if [ -d "$PLUGINS_DIR/$name" ]; then
        rm -rf "${PLUGINS_DIR:?}/$name"
        echo "OK: Plugin '$name' removed (its settings are removed too)"
    else
        echo "WARN: Plugin '$name' is not installed, nothing to remove"
    fi
done

for name in $FINAL; do
    if [ -f "$PLUGINS_SRC/$name/plugin.sh" ]; then
        mkdir -p "$PLUGINS_DIR/$name"
        install -m 644 "$PLUGINS_SRC/$name/plugin.sh" "$PLUGINS_DIR/$name/plugin.sh"
        install -m 644 "$PLUGINS_SRC/$name/plugin.conf" "$PLUGINS_DIR/$name/plugin.conf"
        # Настройки пользователя не перезаписываем: берём пример только при первой установке.
        if [ ! -f "$PLUGINS_DIR/$name/config" ] && [ -f "$PLUGINS_SRC/$name/config.example" ]; then
            install -m 644 "$PLUGINS_SRC/$name/config.example" "$PLUGINS_DIR/$name/config"
        fi
        echo "OK: Plugin '$name' installed: $(manifest_get "$PLUGINS_SRC/$name/plugin.conf" SUMMARY)"
    else
        echo "WARN: Plugin '$name' is not in this repository, left as it is"
    fi
done

# --- Docker и VM ---------------------------------------------------------------------------

if [ "$PLATFORM" = "macos" ]; then
    if ! command -v colima >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
        die "Colima or Docker CLI is not installed. Install them: brew install colima docker"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        write_config_template
        echo "INFO: Created config template: $CONFIG_FILE"
        echo "Next: add your project folders (PROJECT_DIR=...) to it and run this script again."
        exit 1
    fi

    # VM создаёт и проверяет сам скрипт запуска из репозитория: логика VM живёт в одном месте.
    "$ROOT_DIR/scripts/agentcell" --vm-apply
    DOCKER_CMD=(docker --context "$DOCKER_CONTEXT_NAME")
else
    if ! docker info >/dev/null 2>&1; then
        die "Docker is not available. Install it (sudo apt install docker.io), add your user to the 'docker' group and log in again."
    fi
    DOCKER_CMD=(docker)
fi

# --- Образ ------------------------------------------------------------------------------------

# --pull и --no-cache нужны, чтобы повторный запуск действительно обновлял
# Claude Code: иначе Docker возьмёт из кэша старый слой с npm install.
# Dockerfile подаётся через stdin, чтобы docker не отправлял в сборку всю папку проекта.
BUILD_ARGS=(build --pull --no-cache
    --build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION:-latest}")
if [ -n "${KUBECTL_VERSION:-}" ]; then
    BUILD_ARGS+=(--build-arg "KUBECTL_VERSION=$KUBECTL_VERSION")
fi
# Что нужно образу для установленных плагинов (поле IMAGE_ARGS манифеста: КЛЮЧ=значение).
for name in $FINAL; do
    for arg in $(manifest_get "$PLUGINS_DIR/$name/plugin.conf" IMAGE_ARGS); do
        BUILD_ARGS+=(--build-arg "$arg")
    done
done

echo "INFO: Plugins in the image: ${FINAL:-none}"
echo "INFO: Building image '$IMAGE' (fresh install, no cache)..."
"${DOCKER_CMD[@]}" "${BUILD_ARGS[@]}" -t "$IMAGE" - < "$ROOT_DIR/Dockerfile"

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
for name in $FINAL; do
    echo "      plugin $name: see docs/plugins/$name.md"
done
