# Проверка v0.2.0 (временный документ)

Этот файл нужен только на время проверки ветки с v0.2.0. Перед слиянием в `main` его
удаляют.

## Для кого и зачем

Вы проверяете новую версию agentcell на своей машине и присылаете автору отчёт по шаблону
из конца документа. По отчёту автор решает, что дорабатывать и можно ли выпускать релиз.

**Что нового в v0.2.0:** на macOS у agentcell своя виртуальная машина Colima (она не видит
вашу домашнюю папку), параллельные сессии, замок при старте VM, опция
`BLOCK_HOST_ACCESS`, и **плагины** (первый плагин: kind). Подробности: [README.md](README.md).

**Время:** около 40–60 минут (большая часть на ожидание скачивания и сборки).

## Что нужно

- macOS 13+ (проверка в основном для неё) с `colima` и `docker` (`brew install colima docker`).
  Для блока 2 ещё `kind` (`brew install kind`). Нужны 6 ГиБ свободной памяти под VM.
- Аккаунт Claude (подписка Pro/Max) **или** API-ключ: он нужен только для проверок 1.4 и 1.5.
- Желательно: вторая машина или VM с Linux (Debian 13) для блока 3. Если её нет, пропустите.

## Безопасность проверки

- Проверка **не трогает** вашу Colima `default` и ваш текущий docker-контекст: у agentcell
  своя VM (`colima-agentcell`).
- Всё лежит в отдельных тестовых папках в домашней папке: `agentcell-test-*`. После
  проверки их удаляют (раздел «Уборка»).
- Ваша настоящая установка agentcell (если она есть в `~/bin`) не затрагивается: проверка
  идёт через отдельную команду и отдельное хранилище (переменные ниже).
- **Хранилище проверки** (`~/agentcell-test-state`) после входа в Claude хранит токен.
  Удалите его при уборке.

## Подготовка

**1. Запомните состояние вашего docker до проверки** (для сравнения в конце):

```bash
docker context show
docker ps -a --format '{{.Names}} {{.Status}}'
colima list
```

**2. Получите ветку:**

```bash
git clone https://github.com/flybasist/agentcell.git
cd agentcell
git checkout <ветка, которую назвал автор>
```

**3. Тестовые переменные и папки** (переменные нужно задавать в каждом новом окне
терминала, где вы работаете):

```bash
export AGENTCELL_STATE=~/agentcell-test-state
export BIN_DIR=~/agentcell-test-bin
AG=~/agentcell-test-bin/agentcell
mkdir -p ~/agentcell-test-a ~/agentcell-test-b
git init -q ~/agentcell-test-a && git init -q ~/agentcell-test-b
```

**4. Запишите окружение для отчёта:**

```bash
sw_vers -productVersion; uname -m; colima version | head -1; docker --version; kind version
```

## Блок 1. Основной сценарий (без плагинов)

Главное требование: **простой запуск `agentcell` в папке работает без kind и kubectl**.

**1.1 Установка.**

```bash
./scripts/install.sh
```

Первый запуск создаёт `~/.config/agentcell/config` и останавливается. Откройте файл и
впишите две строки (остальное оставьте):

```
PROJECT_DIR=~/agentcell-test-a
PROJECT_DIR=~/agentcell-test-b
```

Затем снова `./scripts/install.sh`. Первый раз скачивается образ VM (несколько минут), потом
собирается образ agentcell.

Ожидается: строки `INFO: The agentcell VM is ready`, `OK: Launcher installed to ...`;
`colima list` показывает профиль `agentcell`; `docker context show` тот же, что был до
проверки. Если сборка образа упала с `DeadlineExceeded`, повторите `./scripts/install.sh` и
отметьте это в отчёте.

**1.2 VM видит только тестовые папки.**

```bash
colima ssh --profile agentcell -- grep /Users /proc/mounts
```

Ожидается: только `~/agentcell-test-a`, `~/agentcell-test-b` и
`~/agentcell-test-state` (хранилище). Домашней папки целиком нет.

**1.3 Контейнер и изоляция.**

```bash
cd ~/agentcell-test-a
$AG --shell <<'EOF'
id
ls -A /workspace
ls /Users 2>&1 | head -1
ls /var/run/docker.sock 2>&1 | head -1
grep -E 'CapEff|NoNewPrivs' /proc/self/status
touch /workspace/from-container.txt && echo written
claude --version
echo "KUBECONFIG=[${KUBECONFIG:-}]"
EOF
ls -l ~/agentcell-test-a/from-container.txt
```

Ожидается: `id` с вашим uid; `/workspace` показывает `.git`; `ls /Users` и docker-сокет:
`No such file or directory`; `CapEff: 0000000000000000` и `NoNewPrivs: 1`; `written`;
версия Claude Code; `KUBECONFIG=[]`; файл `from-container.txt` на Маке принадлежит вам.

**1.4 Вход и интерактивная сессия** (нужен аккаунт Claude).

```bash
cd ~/agentcell-test-a
$AG
```

Выполните вход (откройте ссылку в браузере, вставьте код), напишите `say hi`, выйдите.
Запустите `$AG` ещё раз: входить заново не должно потребоваться.

**1.5 Режим `-p` и пайп.**

```bash
$AG -p "say hi in three words"
echo "The text is: hello" | $AG -p "repeat the text after 'is:' and nothing else"
```

Ожидается: ответ Claude; во втором случае `hello` (данные из пайпа дошли).

**1.6 Отказ вне тестовых папок.**

```bash
cd ~ && mkdir -p agentcell-test-outside && cd agentcell-test-outside && $AG --shell </dev/null
```

Ожидается: `ERROR: Folder ... is not inside any PROJECT_DIR` с подсказкой.

**1.7 Состояние, остановка, автозапуск.**

```bash
cd ~/agentcell-test-a
$AG --vm-status
$AG --vm-stop
echo "echo started-ok" | $AG --shell
```

Ожидается: `--vm-status` показывает VM, папки, `Config applied: yes`; после `--vm-stop` и
запуска VM поднимается сама (10–60 секунд) и печатается `started-ok`.

**1.8 Параллельная работа и обычный docker.** Откройте три окна терминала (в первых двух
задайте переменные из «Подготовки»).

- Окно 1: `cd ~/agentcell-test-a && $AG --shell <<<'sleep 90'`
- Окно 2: `cd ~/agentcell-test-b && $AG --shell <<<'sleep 90'`
- Окно 3 (обычный docker, без agentcell). Создайте файл `compose.yml`:

```yaml
services:
  tiny:
    image: alpine:3
    command: ["sh", "-c", "sleep 3600"]
```

```bash
docker context show
docker compose -p agentcelltest -f compose.yml up -d
docker compose -p agentcelltest -f compose.yml ps
docker compose -p agentcelltest -f compose.yml down -v
docker context show
```

Ожидается: обычный compose работает, пока идут две сессии agentcell; контекст до и после
один и тот же; контейнеры compose не видны в `docker --context colima-agentcell ps`.
Попробуйте в окне 3 `$AG --vm-stop`: должен быть отказ (`sessions are running`).

**1.9 Применение изменённого конфига.** Удалите из `~/.config/agentcell/config` строку
`PROJECT_DIR=~/agentcell-test-b`, затем:

```bash
cd ~/agentcell-test-a && $AG --shell </dev/null    # ожидается отказ: config was changed
$AG --vm-apply                                     # VM перезапускается
```

Верните строку и снова `$AG --vm-apply`. Ожидается: отказ без применения, потом успешное
применение.

**1.10 Опция `BLOCK_HOST_ACCESS`.** В окне 1 запустите на Маке тестовый сервер:

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory ~/agentcell-test-outside
```

В другом окне:

```bash
cd ~/agentcell-test-a
echo 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://host.docker.internal:8765/' | $AG --shell
```

Ожидается `200` (по умолчанию контейнер достаёт до localhost Мака). Затем впишите в конфиг
`BLOCK_HOST_ACCESS=1`, выполните `$AG --vm-apply` и повторите команду: ожидается `000`
(доступ закрыт). Верните `BLOCK_HOST_ACCESS=0` и `--vm-apply`. Остановите сервер (Ctrl+C).

## Блок 2. Плагины (на macOS)

**2.1 Установка плагина kind.**

```bash
cd <папка agentcell>
./scripts/install.sh --with kind
ls ~/.config/agentcell/plugins/kind
docker --context colima-agentcell image inspect agentcell --format '{{index .Config.Labels "agentcell.kubectl"}}'
```

Ожидается: `OK: Plugin 'kind' installed`, `INFO: Plugins in the image:  kind`, в папке
`config plugin.conf plugin.sh`, метка образа `1`.

**2.2 Удаление и повторная установка.**

```bash
./scripts/install.sh --without kind
ls ~/.config/agentcell/plugins/
docker --context colima-agentcell image inspect agentcell --format '{{index .Config.Labels "agentcell.kubectl"}}'
./scripts/install.sh --with kind
```

Ожидается: после `--without` папки плагина нет и метка `0`; после `--with` снова `1`.
Проверьте также, что `./scripts/install.sh` без флагов **не удаляет** плагин.

**2.3 Ошибки установки** (каждая команда должна завершиться понятной ошибкой):

```bash
./scripts/install.sh --with nope
./scripts/install.sh --bogus
```

**2.4 kind-кластер и права агента.**

```bash
DOCKER_CONTEXT=colima-agentcell kind create cluster --name lab \
  --kubeconfig ~/.config/agentcell/kind-lab.kubeconfig
cd ~/agentcell-test-a
AGENTCELL_KIND_CLUSTER=lab $AG --shell <<'EOF'
echo "KUBECONFIG=$KUBECONFIG"
kubectl get nodes
echo "own namespace: $(kubectl auth can-i create pods)"
echo "kube-system:   $(kubectl auth can-i create pods -n kube-system)"
echo "everything:    $(kubectl auth can-i '*' '*' -A)"
kubectl label ns agent pod-security.kubernetes.io/enforce=privileged --overwrite 2>&1 | head -1
kubectl apply -f - <<'POD' 2>&1 | head -2
apiVersion: v1
kind: Pod
metadata: {name: bad}
spec:
  containers:
  - {name: c, image: busybox:1.36, command: ["sleep","5"], securityContext: {privileged: true}}
POD
kubectl run t1 --image=busybox:1.36 --restart=Never --command -- sh -c 'echo pod-ran-ok' 2>&1 | grep -v Warning
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/t1 --timeout=150s
kubectl logs t1
EOF
```

Ожидается: `KUBECONFIG=/home/agent/.kube/agentcell-lab.config`; нода `Ready`; `yes`, `no`,
`no`; метку снять нельзя (`Forbidden`); привилегированный под отклонён
(`violates PodSecurity "baseline"`); обычный под выполнился (`pod-ran-ok`).

**2.5 cluster-admin на сессию и его снятие.**

```bash
AGENTCELL_KIND_CLUSTER=lab AGENTCELL_KIND_ADMIN=1 $AG --shell <<<'kubectl auth can-i "*" "*" -A'
AGENTCELL_KIND_CLUSTER=lab $AG --shell <<<'kubectl auth can-i "*" "*" -A'
```

Ожидается: первая команда печатает предупреждение и `yes`, вторая `no`.

**2.6 Настройки плагина.** Откройте `~/.config/agentcell/plugins/kind/config`: должна быть
строка `KIND_TOKEN_TTL=8h`. Впишите `KIND_TOKEN_TTL=hh` и запустите из 2.5 вторую команду:
ожидается ошибка `KIND_TOKEN_TTL must look like 8h or 90m`. Верните `8h`.

**2.7 Без включающей переменной плагин молчит.**

```bash
$AG --shell <<'EOF'
echo "KUBECONFIG=[${KUBECONFIG:-}]"
kubectl get pods 2>&1 | head -1
EOF
$AG --vm-status
```

Ожидается: `KUBECONFIG=[]`, kubectl не находит кластер; в `--vm-status` внизу блок
`Plugin kind: installed`.

**2.8 Перезапуск VM с кластером.**

```bash
$AG --vm-stop
echo "echo ok" | $AG --shell
docker --context colima-agentcell ps --format '{{.Names}} {{.Status}}'
AGENTCELL_KIND_CLUSTER=lab $AG --shell <<<'kubectl get nodes'
```

Ожидается: нода `lab-control-plane` поднялась сама и kubectl видит кластер.

## Блок 3. Linux (если есть машина)

Docker должен быть установлен, пользователь в группе `docker`. Переменные
`AGENTCELL_STATE` и `BIN_DIR` те же.

```bash
./scripts/install.sh
cd ~/agentcell-test-a
$AG --shell <<<'id; ls /workspace; echo KUBECONFIG=[${KUBECONFIG:-}]'
./scripts/install.sh --with kind     # ожидается отказ: supports only: macos
$AG --vm-status                      # ожидается: works only on macOS
cd ~ && $AG --shell </dev/null       # ожидается отказ: Refusing to mount ... too wide
```

Ожидается: установка и запуск работают как в v0.1.0 (конфиг не нужен); три отказа с
понятными сообщениями. Если можете, проверьте и вход в Claude (1.4, 1.5).

## Уборка

```bash
DOCKER_CONTEXT=colima-agentcell kind delete cluster --name lab --kubeconfig ~/.config/agentcell/kind-lab.kubeconfig
colima delete --profile agentcell --data --force
rm -rf ~/agentcell-test-a ~/agentcell-test-b ~/agentcell-test-outside ~/agentcell-test-state ~/agentcell-test-bin
rm -f ~/.config/agentcell/config ~/.config/agentcell/vm-applied ~/.config/agentcell/kind-lab.kubeconfig
rm -rf ~/.config/agentcell/plugins
docker context show; colima list      # сравните с состоянием до проверки
```

Если на Маке вы не создавали `~/.config/agentcell` раньше, можно удалить и всю папку.
Образ `alpine:3` из проверки 1.8 можно убрать: `docker rmi alpine:3`.

## Известные ограничения (это не ошибки)

- kind работает только на macOS; на Linux плагин не ставится.
- Первая сборка образа в новой VM может упасть с `DeadlineExceeded`: повторите установку.
- Сборка образа с kind при медленной сети может идти 20–25 минут (скачивается kubectl).
- После перезапуска VM kind-кластеру нужно около минуты, чтобы API стал доступен;
  если `kubectl` сразу после старта выдаёт ошибку, подождите и повторите.
- Intel-Mac и версии macOS старше 13 не входят в план проверки.
- По умолчанию контейнер достаёт до сервисов на localhost Мака (это закрывает
  `BLOCK_HOST_ACCESS=1`).

## Что прислать автору

Скопируйте шаблон и заполните. Для каждой проверки: `OK`, `FAIL` или `не проверял`. Для
`FAIL` приложите команду, **полный** вывод и что ожидалось. Это важнее всего.

```
Окружение: macOS <версия>, <чип>, colima <версия>, docker <версия>, kind <версия>
Ветка/коммит: <git rev-parse --short HEAD>

Блок 1:  1.1 _  1.2 _  1.3 _  1.4 _  1.5 _  1.6 _  1.7 _  1.8 _  1.9 _  1.10 _
Блок 2:  2.1 _  2.2 _  2.3 _  2.4 _  2.5 _  2.6 _  2.7 _  2.8 _
Блок 3 (Linux): <система> ... install _  запуск _  --with kind _  --vm-status _  отказ в ~ _

Docker после проверки совпал с состоянием до неё: да / нет (что изменилось)
Время: первая установка ___ мин, запуск agentcell ___ сек, холодный старт VM ___ сек

Нашёл проблемы (по каждой: что делал, что произошло, что ожидал, вывод, насколько мешает:
блокирует работу / неудобство / вопрос):
1. ...

Документация (README, QUICKSTART, PLUGINS): что было непонятно или не совпало с тем, что
происходило:
- ...

Что понравилось / что бы изменил (по желанию):
- ...
```
