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

# Версию можно закрепить: --build-arg CLAUDE_CODE_VERSION=x.y.z
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Версия вморожена в образ, поэтому самообновление внутри контейнера не нужно:
# обновляется Claude Code только пересборкой образа (scripts/install.sh).
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
