# Быстрый старт

## 1. Требования

- macOS 13+ или Linux с Docker (рассчитано на Debian 13).
- Доступ в интернет: при сборке образа (npm) и во время работы Claude.
- Аккаунт Claude с подпиской Pro/Max **или** API-ключ из Anthropic Console.
- macOS: свободная память под VM agentcell (по умолчанию 6 ГиБ).

## 2. Docker

**macOS:**
```bash
brew install colima docker
```

Запускать `colima start` не нужно: у agentcell своя VM, её создаст установка.

**Debian 13:**
```bash
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker "$USER"   # затем выйдите из системы и войдите снова
```

Проверка (Linux):
```bash
docker info >/dev/null 2>&1 && echo "Docker is running"
```

## 3. Установка

### macOS

Из корня репозитория:

```bash
./scripts/install.sh
```

Первый запуск создаёт конфиг `~/.config/agentcell/config` и останавливается. Впишите в
него папки, где лежат ваши проекты, — по строке на папку:

```
PROJECT_DIR=~/src
PROJECT_DIR=~/Documents/infra
```

Только эти папки (и хранилище agentcell) увидит VM agentcell, и только внутри них можно
запускать `agentcell`. Домашнюю папку целиком указать нельзя. Затем снова:

```bash
./scripts/install.sh
```

Скрипт создаст VM Colima `agentcell` (первый раз несколько минут: скачивается образ VM), соберёт
в ней образ и скопирует
команду в `~/bin/agentcell`. Ваш текущий docker-контекст не меняется: обычный `docker`
в терминале работает как раньше, а образ agentcell виден только так:
`docker --context colima-agentcell images`.

### Linux

```bash
./scripts/install.sh
```

Скрипт собирает образ `agentcell` и копирует команду в `~/bin/agentcell`. Конфиг на Linux
не нужен.

### Плагины (необязательно)

Плагины добавляют возможности, нужные не всем (сейчас один: [kind](plugins/kind.md), доступ
агента к локальному kind-кластеру, только macOS). Они ставятся при установке:

```bash
./scripts/install.sh --with kind     # поставить плагин и пересобрать образ
./scripts/install.sh --without kind  # убрать плагин
```

Установленный плагин остаётся в системе, повторная установка без `--with` его не удаляет, а
обновляет. Каждый плагин включается в сессии своими переменными. Правила и список:
[PLUGINS.md](PLUGINS.md).

### Если `~/bin` не в `PATH`

Скрипт напечатает команду, которую нужно выполнить. Для zsh (macOS):

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

### Параллельная работа

Можно открывать сколько угодно сессий `agentcell` одновременно, в том числе в одной папке, а
остановленная VM при одновременном запуске поднимается один раз. Обычный `docker compose` и
другие проекты в вашей Colima `default` работают как раньше и не мешают agentcell: у него своя
VM и свой docker-контекст (`colima-agentcell`), а ваш текущий контекст не меняется.

### VM agentcell (macOS)

VM стартует сама при первом запуске после перезагрузки Мака (обычно до минуты) и работает,
пока вы её не остановите.

```bash
agentcell --vm-status    # запущена ли VM, какие папки она видит, что в ней работает
agentcell --vm-stop      # остановить и освободить память
agentcell --vm-apply     # применить изменённый конфиг (VM перезапустится)
```

**Новая папка проектов.** Допишите строку `PROJECT_DIR=...` в конфиг и выполните
`agentcell --vm-apply`. Пока в VM работают сессии agentcell, команда откажется: завершите
их. То же — после изменения ресурсов VM (`VM_CPU`, `VM_MEMORY`, `VM_DISK`).

### Работа без подтверждений

Контейнер ограничивает агента одной папкой, поэтому режим без запросов разрешений
относительно безопасен. Он включается флагом Claude Code (точное имя проверьте в
`agentcell --help`):

```bash
agentcell --dangerously-skip-permissions
agentcell --dangerously-skip-permissions -p "задача"   # из скрипта или cron
```

Запуск без терминала (cron, пайпы) поддерживается: терминал подключается, только если он есть.
В `cron` задайте полный `PATH`: на macOS `colima` и `docker` лежат в `/opt/homebrew/bin` или
`/usr/local/bin`, и без этого скрипт их не найдёт.
Перед таким режимом прочитайте [SECURITY.md](SECURITY.md).

### Переменные окружения

| Переменная | Что делает | По умолчанию |
|---|---|---|
| `AGENTCELL_IMAGE` | имя Docker-образа | `agentcell` |
| `AGENTCELL_STATE` | папка хранилища на хосте | `~/.config/agentcell/state` |
| `AGENTCELL_ALLOW_ANY_DIR=1` | только Linux: разрешить запуск из `~` и `/` | выключено |
| `ANTHROPIC_API_KEY` | API-ключ, передаётся в контейнер | не задан |

### Конфиг (macOS)

`~/.config/agentcell/config`, формат `КЛЮЧ=значение` без кавычек:

| Ключ | Что делает | По умолчанию |
|---|---|---|
| `PROJECT_DIR` | папка проектов, видимая VM; можно несколько строк | нет, обязательно |
| `VM_CPU` | процессоров у VM | `4` |
| `VM_MEMORY` | память VM, ГиБ | `6` |
| `VM_DISK` | диск VM, ГиБ (только увеличивать) | `60` |
| `BLOCK_HOST_ACCESS` | `1` — закрыть контейнерам доступ к сервисам на localhost вашего Мака (см. [SECURITY.md](SECURITY.md)); после изменения `agentcell --vm-apply` | `0` |

Переменные плагинов (например, `AGENTCELL_KIND_CLUSTER`) и их настройки описаны в документах
плагинов. Папки `PROJECT_DIR` не должны пересекаться ни друг с другом, ни с хранилищем. Colima сравнивает
пути как обычные строки, поэтому `~/src` и `~/src2` она уже считает пересекающимися:
перечислите внешнюю папку или переименуйте одну из них.

## 6. Плагины

Плагин ставится при установке (раздел 3) и включается в сессии своими переменными
окружения; без них он ничего не делает. Подробности и правила: [PLUGINS.md](PLUGINS.md).

| Плагин | Что даёт | Документ |
|---|---|---|
| `kind` | агент работает с одним локальным kind-кластером (macOS) | [plugins/kind.md](plugins/kind.md) |

Настройки плагина лежат в `~/.config/agentcell/plugins/<имя>/config`. Повторная установка их
не перезаписывает, `--without` удаляет вместе с плагином.

## 7. Обновление Claude Code

Claude Code установлен внутри образа, поэтому обновляется только пересборкой образа:

```bash
./scripts/install.sh                              # последняя версия (плагины остаются)
CLAUDE_CODE_VERSION=x.y.z ./scripts/install.sh    # конкретная версия
```

Образ собирается с тем, что нужно установленным плагинам, поэтому повторная установка не
теряет их инструменты.

На macOS VM при этом не перезапускается, если конфиг не менялся.

## 8. Переход с v0.1.0 (macOS)

Раньше agentcell работал в вашей Colima `default`. Теперь у него своя VM:

1. `git pull` в репозитории.
2. `./scripts/install.sh` — создаст конфиг; впишите `PROJECT_DIR` и запустите снова.
   Образ соберётся заново в новой VM.
3. Хранилище (вход в аккаунт, настройки) остаётся прежним, входить заново не нужно.
4. Colima `default` agentcell не использует и не меняет: она продолжает работать для других
   задач (например, `docker compose`). `agentcell --vm-status` покажет её для сведения.
   Если она вам больше не нужна: `colima stop`, а удалить совсем — `colima delete`; перед
   удалением проверьте, что там нет нужного: `docker --context colima ps -a`.

Старый образ из `default` можно удалить: `docker --context colima rmi agentcell`.

## 9. Частые проблемы

| Сообщение или симптом | Что делать |
|---|---|
| `Docker is not available` (Linux) | `sudo systemctl start docker` и проверьте, что вы в группе `docker`. |
| `Colima is not installed` | `brew install colima docker`. |
| `Config not found` / `No PROJECT_DIR` | Запустите `./scripts/install.sh` и впишите `PROJECT_DIR` в конфиг. |
| `The agentcell VM does not exist` | Запустите `./scripts/install.sh`. |
| `Folders '...' overlap` | Папки из `PROJECT_DIR` (или хранилище) пересекаются, в том числе как начало пути: `~/src` и `~/src2`. Оставьте одну папку или переименуйте. |
| `The config was changed after the VM was set up` | `agentcell --vm-apply`. |
| `Folder '...' is not inside any PROJECT_DIR` | Допишите папку в конфиг и выполните `agentcell --vm-apply`. |
| `The agentcell VM can see your home folder` | VM настроена не тем способом. `colima delete --profile agentcell`, затем `./scripts/install.sh`. |
| `agentcell sessions are running in the VM` | Завершите сессии agentcell и повторите команду. |
| `Image 'agentcell' not found` | Выполните `./scripts/install.sh`. |
| `DeadlineExceeded` при сборке образа | Первое обращение новой VM к Docker Hub бывает медленным. Повторите `./scripts/install.sh` (или заранее `docker --context colima-agentcell pull node:24`). |
| `Could not block container access to your Mac` | Не удалось поставить правило межсетевого экрана в VM. Поставьте `BLOCK_HOST_ACCESS=0` в конфиге и выполните `agentcell --vm-apply`; если нужна опция, сообщите об ошибке. |
| `Another agentcell is starting the VM, waiting for it...` | Это нормально: два запуска одновременно, второй ждёт, пока первый поднимет VM. |
| `Waited 5 minutes for another agentcell` | Замок `~/.config/agentcell/vm.lock` остался от аварийно завершённого запуска. Если других запусков нет, удалите его: `rmdir ~/.config/agentcell/vm.lock`. |
| `Refusing to mount ...` (Linux) | Вы запустили из `~` или `/`. Перейдите в папку проекта. Если это осознанно — `AGENTCELL_ALLOW_ANY_DIR=1`. |
| `Plugin '...' supports only: ...` | Плагин не поддерживает вашу систему (например, kind только на macOS). |
| `Plugins '...' and '...' cannot be used together` | Два установленных плагина конфликтуют. Уберите один: `./scripts/install.sh --without <имя>`. |
| `Unknown plugin '...'` | Такого плагина нет в `plugins/`. |
| Проблемы конкретного плагина | См. таблицу «Частые проблемы» в его документе, например [plugins/kind.md](plugins/kind.md). |
| Не получается войти | Удалите хранилище и повторите вход: `rm -rf ~/.config/agentcell/state`. |

Проверить, что VM agentcell не видит домашнюю папку (macOS):

```bash
colima ssh --profile agentcell -- grep /Users /proc/mounts   # только PROJECT_DIR и хранилище
```

Команда `ls /Users/$USER` внутри VM тоже уместна, но после удаления папки из конфига там может
остаться пустой каталог с её именем: он не смонтирован и ничего не содержит.

## 10. Удаление

**macOS:**

```bash
rm ~/bin/agentcell
colima delete --profile agentcell --data   # VM, образ, кластеры плагинов и диск данных (около 6 ГБ)
rm -rf ~/.config/agentcell          # конфиг и хранилище (вход в аккаунт)
```

**Linux:**

```bash
rm ~/bin/agentcell
docker rmi agentcell
rm -rf ~/.config/agentcell
```
