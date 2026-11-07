# Плагин kind

Даёт агенту доступ к одному локальному [kind](https://kind.sigs.k8s.io/)-кластеру (Kubernetes
в Docker), который работает в VM agentcell. Агент администратор только своего namespace и
не видит других ваших кластеров. Общие правила плагинов: [PLUGINS.md](../PLUGINS.md).

Только macOS: на Linux нет VM, а ноды kind там были бы привилегированными контейнерами
прямо на вашем компьютере. Без плагина agentcell работает как обычно: kind и kubectl ему не
нужны.

## Что нужно

- macOS с настроенной VM agentcell (см. [QUICKSTART.md](../QUICKSTART.md)).
- `kind` на Маке: `brew install kind` (он нужен только для создания кластера). kubectl на
  Маке не нужен.

## Установка и удаление

```bash
./scripts/install.sh --with kind     # ставит плагин и пересобирает образ с kubectl
./scripts/install.sh --without kind  # убирает плагин; образ без kubectl пересоберётся
```

Образ получает kubectl (версия закреплена, `v1.37.2`, файл сверяется с контрольной суммой)
и метку `agentcell.kubectl=1`; плагин проверяет её при запуске. Версия `kubectl` должна быть
не дальше одной минорной версии от Kubernetes в ноде. Если ваш кластер старше или новее:

```bash
KUBECTL_VERSION=v1.xx.y ./scripts/install.sh --with kind
```

## Как пользоваться

**1. Создать кластер** в VM agentcell (один раз; переживает остановку VM):

```bash
DOCKER_CONTEXT=colima-agentcell kind create cluster --name lab \
  --kubeconfig ~/.config/agentcell/kind-lab.kubeconfig
```

`--kubeconfig` обязателен: без него kind допишет кластер в ваш `~/.kube/config` и
переключит там текущий контекст.

**2. Запустить агента с кластером:**

```bash
cd ~/src/my-project
AGENTCELL_KIND_CLUSTER=lab agentcell
```

Внутри контейнера `kubectl` уже настроен: namespace `agent`, где агент — администратор.
Смотреть ноды, namespaces, storageclasses и CRD он тоже может. Привилегированные поды
запрещены.

**3. Если нужны права на весь кластер** (CRD, операторы) — только на эту сессию:

```bash
AGENTCELL_KIND_CLUSTER=lab AGENTCELL_KIND_ADMIN=1 agentcell
```

Прочитайте перед этим раздел «cluster-admin» ниже.

**Полезное:**

```bash
# свой образ — в кластер (у агента нет доступа к docker, это делаете вы)
DOCKER_CONTEXT=colima-agentcell kind load docker-image my-image:dev --name lab
# посмотреть кластер с Мака (нужен kubectl на Маке)
kubectl --kubeconfig ~/.config/agentcell/kind-lab.kubeconfig get nodes
# удалить кластер
DOCKER_CONTEXT=colima-agentcell kind delete cluster --name lab \
  --kubeconfig ~/.config/agentcell/kind-lab.kubeconfig
```

## Переменные и настройки

| Переменная | Что делает |
|---|---|
| `AGENTCELL_KIND_CLUSTER=<имя>` | включает плагин в этой сессии и называет кластер |
| `AGENTCELL_KIND_ADMIN=1` | на эту сессию даёт агенту cluster-admin (опасно) |

Настройки лежат в `~/.config/agentcell/plugins/kind/config`:

| Ключ | Что делает | По умолчанию |
|---|---|---|
| `KIND_TOKEN_TTL` | срок токена агента: число и буква `h` или `m` (`8h`, `90m`) | `8h` |

Токен истёк (`kubectl` отвечает `Unauthorized`) или кластер пересоздан: перезапустите
`agentcell`. Изменённые настройки вступают в силу при следующем запуске, VM
перезапускать не нужно.

## Как это работает

Без `AGENTCELL_KIND_CLUSTER` плагин ничего не делает: не обращается ни к docker, ни к
кластеру, не пишет kubeconfig и ничего не добавляет контейнеру. С переменной, на каждом
запуске:

1. `kind_check` проверяет имя кластера (только `a-z`, `0-9`, `-`), срок токена, что образ
   собран с kubectl, что нода `lab-control-plane` запущена и помечена как нода кластера
   `lab`. Сеть берёт у этой ноды (обычно `kind`).
2. `kind_prepare` через `docker exec` в ноду (там есть kubectl и `admin.conf`) применяет
   манифест:
   - namespace `agent` с Pod Security `enforce=baseline`, `warn/audit=restricted`;
   - ServiceAccount `agent/agentcell`;
   - RoleBinding на встроенную роль `admin` в namespace `agent`;
   - ClusterRole `agentcell-cluster-view`: только чтение nodes, namespaces,
     storageclasses и CRD.
3. При `AGENTCELL_KIND_ADMIN=1` добавляет ClusterRoleBinding `agentcell-cluster-admin` и
   печатает предупреждение; без неё удаляет эту привязку (права пропадают сразу).
4. Выпускает токен ServiceAccount на `KIND_TOKEN_TTL` и пишет kubeconfig
   `~/.config/agentcell/state/.kube/agentcell-lab.config` (права 600): адрес
   `https://lab-control-plane:6443`, сертификат CA кластера, токен. Сертификат
   администратора кластера туда не попадает.
5. Подключает контейнер к сети ноды (`plugin_add_network`) и передаёт
   `KUBECONFIG=/home/agent/.kube/agentcell-lab.config` (`plugin_add_env`).

Отдельный файл на кластер и переменная `KUBECONFIG` нужны, чтобы параллельные сессии с
разными кластерами не перезаписывали друг другу доступ. В сессии без плагина переменной
нет, контейнер не в сети кластера, а токен истекает сам, поэтому старые файлы не мешают.

Права администратора кластера остаются у плагина на хосте: он работает с кластером через
`docker exec` в ноду. Агенту достаётся только токен ServiceAccount, kubectl на Маке не
нужен, и случайная команда не затронет другие кластеры из вашего `~/.kube`.

## Безопасность

- **Другие кластеры.** Агент не получает доступа к вашим другим кластерам Kubernetes:
  `~/.kube` в VM нет, а токен выдан только для выбранного кластера. Другие kind-кластеры в
  той же VM находятся в общей docker-сети `kind`: агент может обращаться к ним по сети
  (проверено: `/version` отвечает), но данных они анонимно не отдают (403), а токен агента к
  ним не подходит.
- **Права в своём namespace.** Namespace агент изменить не может, значит, и метку Pod
  Security снять не может. Привилегированные поды, `hostPath` и `hostNetwork` отклоняются.
- **cluster-admin.** Ноды kind — привилегированные контейнеры. Агент с правами cluster-admin
  может создать под с доступом к ноде и из неё выйти в VM agentcell, а там он увидит все
  `PROJECT_DIR` и хранилище. Поэтому по умолчанию таких прав нет, а `AGENTCELL_KIND_ADMIN=1`
  действует только на одну сессию. Следующий запуск без этой переменной снимает права. Это
  касается и параллельных сессий: обычный запуск при работающей сессии с cluster-admin
  снимет права и у неё. Включайте режим только если задача требует CRD, операторов или
  других объектов уровня кластера, и только после коммита во всех проектах из
  `PROJECT_DIR`.
- **Доступ к Маку.** Поды кластера ходят в сеть через ту же VM. Опция `BLOCK_HOST_ACCESS=1`
  (см. [SECURITY.md](../SECURITY.md)) закрывает доступ к хосту и им тоже.

## Частые проблемы

| Сообщение или симптом | Что делать |
|---|---|
| `kind cluster '...' is not running` | Создайте кластер или запустите его ноду: команды есть в сообщении. |
| `The image ... was built without kubectl` | Пересоберите образ с плагином: `./scripts/install.sh --with kind`. |
| `KIND_TOKEN_TTL must look like 8h or 90m` | Исправьте значение в `~/.config/agentcell/plugins/kind/config`. |
| `Unknown setting` / `Bad line` в файле настроек | В `config` допустим только ключ `KIND_TOKEN_TTL`, формат `КЛЮЧ=значение`. |
| `kubectl`: `Unauthorized` | Истёк токен или кластер пересоздан. Перезапустите `agentcell`. |
| `Plugin 'kind' supports only: macos` | Плагин работает только на macOS. |
| `AGENTCELL_KIND_ADMIN is ignored` | Админский режим работает только вместе с `AGENTCELL_KIND_CLUSTER`. |
