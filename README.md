# agentcell

Запуск [Claude Code](https://claude.com/claude-code) в Docker-контейнере так, чтобы агент
видел только одну папку — ту, из которой вы его запустили.

> Неофициальный проект, не связан с Anthropic.

## Как это работает

Из вашей системы контейнер видит ровно две папки:

| В контейнере | На вашем компьютере | Зачем |
|---|---|---|
| `/workspace` | папка, из которой запущен `agentcell` | проект, с которым работает агент |
| `/home/agent` | `~/.config/agentcell/state` | хранилище: вход в аккаунт, настройки, кэш |

Домашняя папка, SSH-ключи, другие проекты и сокет Docker контейнеру недоступны.
Контейнер работает не от root, без привилегий и удаляется после выхода.

## Что нужно

- macOS 13+ (Docker и Colima) или Linux с Docker (рассчитано на Debian 13).
- Аккаунт Claude с подпиской Pro/Max или API-ключ из Anthropic Console.

## Установка и запуск

```bash
./scripts/install.sh      # собирает образ и кладёт команду agentcell в ~/bin
cd ~/путь/к/проекту
agentcell                 # интерактивная сессия Claude Code
```

Повторный запуск `./scripts/install.sh` обновляет Claude Code.

Другие режимы:

```bash
agentcell -p "прогони тесты и исправь падающие"   # одна задача без диалога
agentcell --shell                                 # bash внутри контейнера
```

## Важно

Проект доступен агенту на запись целиком, а сеть открыта. Держите проект в git и
делайте коммит перед рискованными задачами. Подробности — в [docs/SECURITY.md](docs/SECURITY.md).

## Документация

Все подробности — в [docs/README.md](docs/README.md): установка по шагам, устройство,
безопасность. История изменений — в [CHANGELOG.md](CHANGELOG.md).

## Контакты

Автор: Ognev Aleksandr (FlyBasist) — [github.com/flybasist](https://github.com/flybasist)

## Лицензия

GNU General Public License v3.0 — см. [LICENSE](LICENSE). Сторонние компоненты
и их условия перечислены в [docs/CREDITS.md](docs/CREDITS.md).
