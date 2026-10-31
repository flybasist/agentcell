# Быстрый старт

## 1. Требования

- macOS 13+ или Linux с Docker (рассчитано на Debian 13).
- Доступ в интернет: при сборке образа (скачивание пакета из npm) и во время работы Claude.
- Аккаунт Claude с подпиской Pro/Max **или** API-ключ из Anthropic Console.

## 2. Docker

**macOS:**
```bash
brew install docker colima
colima start
```

**Debian 13:**
```bash
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker "$USER"   # затем выйдите из системы и войдите снова
```

Проверка:
```bash
docker info >/dev/null 2>&1 && echo "Docker is running"
```

## 3. Установка

Из корня репозитория:

```bash
./scripts/install.sh
```

Скрипт собирает образ `agentcell` и копирует команду в `~/bin/agentcell`. Если `~/bin`
не в `PATH`, скрипт напечатает команду, которую нужно выполнить. Для zsh (macOS):

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Команду можно положить в другое место: `BIN_DIR=/путь ./scripts/install.sh`.

## 4. Первый запуск и вход

```bash
cd ~/путь/к/проекту
agentcell
```

**Вариант А — подписка (Pro/Max).** Claude Code предложит войти. Откройте выданную ссылку
в браузере на своём компьютере, подтвердите вход и вставьте полученный код в терминал.
Вход сохранится в хранилище и будет общим для всех проектов. Если хотите работать по
подписке, не экспортируйте `ANTHROPIC_API_KEY` на хосте.

**Вариант Б — API-ключ (оплата за токены).** Экспортируйте ключ перед запуском:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
agentcell
```

## 5. Повседневное использование

```bash
agentcell                                           # интерактивная сессия в текущей папке
agentcell -p "прогони тесты и исправь падающие"     # одна задача без диалога
agentcell --shell                                   # bash внутри контейнера
```

Все остальные флаги уходят в `claude` как есть. Список флагов: `agentcell --help`.

`--shell` пригодится, чтобы один раз настроить `git config user.name` и `user.email`:
настройки сохранятся в хранилище.

### Работа без подтверждений

Контейнер ограничивает агента одной папкой, поэтому режим без запросов разрешений
относительно безопасен. Он включается флагом Claude Code (точное имя проверьте в
`agentcell --help`):

```bash
agentcell --dangerously-skip-permissions
agentcell --dangerously-skip-permissions -p "задача"   # из скрипта или cron
```

Запуск без терминала (cron, пайпы) поддерживается: терминал подключается, только если он есть.
Перед таким режимом прочитайте [SECURITY.md](SECURITY.md).

### Переменные окружения

| Переменная | Что делает | По умолчанию |
|---|---|---|
| `AGENTCELL_IMAGE` | имя Docker-образа | `agentcell` |
| `AGENTCELL_STATE` | папка хранилища на хосте | `~/.config/agentcell/state` |
| `AGENTCELL_ALLOW_ANY_DIR=1` | разрешить запуск из `~` и `/` | выключено |
| `ANTHROPIC_API_KEY` | API-ключ, передаётся в контейнер | не задан |

## 6. Обновление Claude Code

Claude Code установлен внутри образа, поэтому обновляется только пересборкой образа:

```bash
./scripts/install.sh                              # последняя версия
CLAUDE_CODE_VERSION=x.y.z ./scripts/install.sh    # конкретная версия
```

## 7. Частые проблемы

| Сообщение или симптом | Что делать |
|---|---|
| `Docker is not available` | macOS: `colima start`. Linux: `sudo systemctl start docker` и проверьте, что вы в группе `docker`. |
| `Image 'agentcell' not found` | Выполните `./scripts/install.sh`. |
| `Refusing to mount ...` | Вы запустили из `~` или `/`. Перейдите в папку проекта. Если это осознанно — `AGENTCELL_ALLOW_ANY_DIR=1`. |
| macOS: контейнер не видит проект | Colima по умолчанию пробрасывает только домашнюю папку. Держите проекты внутри неё или настройте монтирование Colima. |
| Не получается войти | Удалите хранилище и повторите вход: `rm -rf ~/.config/agentcell/state`. |

Проверить, что контейнеру видны только две папки:

```bash
docker run --rm --entrypoint sh \
  -v "$HOME/.config/agentcell/state:/home/agent" -v "$PWD:/workspace" agentcell \
  -c 'grep -E " /workspace | /home/agent " /proc/mounts'
```

## 8. Удаление

```bash
rm ~/bin/agentcell
docker rmi agentcell
rm -rf ~/.config/agentcell
```
