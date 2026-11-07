# Образ для agentcell: Claude Code внутри Node.js.
#
# В образ ничего не копируется из репозитория, поэтому scripts/install.sh
# передаёт docker только этот файл (без остальных файлов проекта).
# Пути внутри контейнера (/workspace, /home/agent) задаёт скрипт
# scripts/agentcell, а не образ.

# Официальный образ Node.js: в нём уже есть git, curl и python3,
# которые агенту обычно нужны. Нужны другие инструменты — добавьте строку
# RUN apt-get update && apt-get install -y <пакет> перед установкой Claude Code.
FROM node:24

# kubectl нужен только плагину kind и ставится, только если WITH_KUBECTL=1. Это передаёт
# scripts/install.sh из манифеста установленного плагина (./scripts/install.sh --with kind).
# Без плагина образ остаётся без kubectl.
ARG WITH_KUBECTL=0

# Версия закреплена, чтобы не «уезжать» при пересборке. Она должна быть не дальше
# ±1 минорной версии от Kubernetes в ноде kind: kind по умолчанию создаёт ноду самой
# свежей версии, а если ваш кластер старше, поменяйте версию kubectl.
# Поменять без правки файла: KUBECTL_VERSION=v1.xx.y ./scripts/install.sh --with kind
ARG KUBECTL_VERSION=v1.37.2

# Архитектуру (amd64 или arm64) берём у самой системы образа: так сборка не зависит
# от того, есть ли у docker BuildKit. Скачанный файл сверяем с контрольной суммой.
RUN if [ "$WITH_KUBECTL" = "1" ]; then \
        ARCH="$(dpkg --print-architecture)" \
        && URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
        && curl -fsSL -o /usr/local/bin/kubectl "$URL" \
        && echo "$(curl -fsSL "$URL.sha256")  /usr/local/bin/kubectl" | sha256sum -c - \
        && chmod 755 /usr/local/bin/kubectl; \
    fi

# Метка сообщает плагину, что kubectl в образе есть: плагин проверяет её перед запуском.
LABEL agentcell.kubectl="${WITH_KUBECTL}"

# Версию можно закрепить: --build-arg CLAUDE_CODE_VERSION=x.y.z
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Версия вморожена в образ, поэтому самообновление внутри контейнера не нужно:
# обновляется Claude Code только пересборкой образа (scripts/install.sh).
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
