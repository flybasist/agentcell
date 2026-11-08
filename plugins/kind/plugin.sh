# Плагин kind для agentcell: агент получает доступ к одному локальному kind-кластеру,
# который работает в VM agentcell. Только macOS. Описание: docs/plugins/kind.md,
# общие правила плагинов: docs/PLUGINS.md.
#
# Этот файл не запускают сам: его загружает scripts/agentcell (source). Поэтому здесь можно
# пользоваться функциями и переменными ядра (die, info, warn, dkr, STATE_REAL и т.д.).
#
# Плагин включается переменной окружения; без неё он ничего не делает:
#   AGENTCELL_KIND_CLUSTER=<имя>   подключить агента к кластеру с этим именем
#   AGENTCELL_KIND_ADMIN=1         на эту сессию дать агенту cluster-admin (опасно)
# Настройки лежат в ~/.config/agentcell/plugins/kind/config (см. config.example).

KIND_NAMESPACE="agent"   # namespace, в котором агент — администратор
KIND_SA="agentcell"      # ServiceAccount агента
KIND_TOKEN_TTL=8h        # срок токена агента (настройка плагина)

# --- Точки входа плагина (вызывает ядро) -------------------------------------------

# Проверка перед запуском контейнера. Ничего не меняет в кластере.
kind_check() {
    if [ -z "${AGENTCELL_KIND_CLUSTER:-}" ]; then
        if [ "${AGENTCELL_KIND_ADMIN:-0}" = "1" ]; then
            warn "AGENTCELL_KIND_ADMIN is ignored without AGENTCELL_KIND_CLUSTER."
        fi
        return 0
    fi
    KIND_CLUSTER="$AGENTCELL_KIND_CLUSTER"
    KIND_NODE="$KIND_CLUSTER-control-plane"
    KIND_KUBECONFIG_NAME="agentcell-$KIND_CLUSTER.config"
    plugin_read_config kind KIND_TOKEN_TTL
    kind_check_ttl "$KIND_TOKEN_TTL"
    kind_check_image
    kind_check_cluster
}

# Подготовка: права агента в кластере, токен, kubeconfig, сеть и переменная для контейнера.
kind_prepare() {
    [ -n "${AGENTCELL_KIND_CLUSTER:-}" ] || return 0
    kind_wait_ready
    kind_apply_rbac
    kind_apply_admin_mode
    kind_write_kubeconfig
    # Контейнер — в сети нод кластера; kubectl внутри берёт kubeconfig этого кластера.
    plugin_add_network "$KIND_NETWORK"
    plugin_add_env "KUBECONFIG=$CELL_HOME/.kube/$KIND_KUBECONFIG_NAME"
}

# Строки для agentcell --vm-status.
kind_status() {
    plugin_read_config kind KIND_TOKEN_TTL
    echo "Plugin kind: installed (agent token lifetime: $KIND_TOKEN_TTL)"
    echo "  use: AGENTCELL_KIND_CLUSTER=<cluster> agentcell"
    if [ "$(profile_state "$VM_PROFILE")" = "Running" ]; then
        echo "  kind nodes:"
        dkr ps --filter "label=io.x-k8s.kind.cluster" \
            --format '    {{.Label "io.x-k8s.kind.cluster"}}  {{.Names}}  {{.Status}}'
    fi
}

# --- Проверки -----------------------------------------------------------------------

# Срок токена: число и буква h (часы) или m (минуты), например 8h или 90m.
kind_check_ttl() {
    local number=""
    case "$1" in
        *h|*m) number="${1%?}" ;;
    esac
    case "$number" in
        ''|*[!0-9]*) die "KIND_TOKEN_TTL must look like 8h or 90m, got '$1' in $PLUGINS_DIR/kind/config" ;;
    esac
}

# Образ должен быть собран с kubectl: install.sh --with kind ставит метку agentcell.kubectl=1.
kind_check_image() {
    local has
    has="$(dkr image inspect -f '{{index .Config.Labels "agentcell.kubectl"}}' "$IMAGE" 2>/dev/null || true)"
    [ "$has" = "1" ] || die "The image '$IMAGE' was built without kubectl, which the kind plugin needs." \
        "Rebuild it: ./scripts/install.sh --with kind"
}

# --- Работа с кластером ------------------------------------------------------------
# Всё делается через docker exec в ноду кластера: в образе ноды kind есть kubectl и
# admin.conf. Права администратора кластера остаются у скрипта на хосте, агенту
# достаётся только токен ServiceAccount.

kind_node_kubectl() {
    dkr exec "$KIND_NODE" kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
}

# То же, но манифест подаётся через stdin (kubectl apply -f -).
kind_node_kubectl_stdin() {
    dkr exec -i "$KIND_NODE" kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
}

# Кластер существует, запущен, и это именно нода kind с этим именем.
kind_check_cluster() {
    local running label networks

    case "$KIND_CLUSTER" in
        ''|*[!a-z0-9-]*)
            die "AGENTCELL_KIND_CLUSTER may contain only a-z, 0-9 and '-', got '$KIND_CLUSTER'"
            ;;
    esac

    running="$(dkr inspect -f '{{.State.Running}}' "$KIND_NODE" 2>/dev/null || true)"
    if [ "$running" != "true" ]; then
        die "kind cluster '$KIND_CLUSTER' is not running in the agentcell VM." \
            "Create it:" \
            "  DOCKER_CONTEXT=$DOCKER_CONTEXT_NAME kind create cluster --name $KIND_CLUSTER --kubeconfig $CONFIG_DIR/kind-$KIND_CLUSTER.kubeconfig" \
            "If it exists but is stopped:" \
            "  docker --context $DOCKER_CONTEXT_NAME start $KIND_NODE"
    fi

    label="$(dkr inspect -f '{{index .Config.Labels "io.x-k8s.kind.cluster"}}' "$KIND_NODE")"
    [ "$label" = "$KIND_CLUSTER" ] || die "Container '$KIND_NODE' is not a node of kind cluster '$KIND_CLUSTER'."

    # Сеть берём у ноды, а не по имени: обычно это kind, но так скрипт не зависит от неё.
    networks="$(dkr inspect -f '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$KIND_NODE")"
    KIND_NETWORK="${networks%% *}"
    [ -n "$KIND_NETWORK" ] || die "Could not find the docker network of '$KIND_NODE'."
}

# Ждём, пока кластер будет готов принимать права. Сразу после `kind create cluster` или
# после старта VM контейнер ноды уже работает, но API может ещё не отвечать, а встроенная
# роль admin сначала пустая: Kubernetes наполняет её правилами чуть позже (агрегированная
# роль). Пока правил нет, привязка к admin ничего не разрешает. Поэтому ждём, пока в роли
# admin появятся правила. Ждём до 90 секунд.
kind_wait_ready() {
    local attempt rules
    for attempt in $(seq 1 45); do
        rules="$(kind_node_kubectl get clusterrole admin -o 'jsonpath={.rules[*].resources[*]}' 2>/dev/null || true)"
        if [ -n "$rules" ]; then
            return 0
        fi
        if [ "$attempt" -eq 1 ]; then
            info "Waiting for kind cluster '$KIND_CLUSTER' to become ready (up to 90 seconds)..."
        fi
        sleep 2
    done
    die "kind cluster '$KIND_CLUSTER' did not become ready in 90 seconds." \
        "Check it: docker --context $DOCKER_CONTEXT_NAME logs $KIND_NODE" \
        "Then run agentcell again."
}

# Namespace агента, его ServiceAccount и права. Повторное применение ничего не ломает.
# PSA baseline запрещает привилегированные поды, hostPath, hostPID и hostNetwork —
# всё, через что под может выбраться в ноду, а из неё в VM.
kind_apply_rbac() {
    info "Preparing agent access to kind cluster '$KIND_CLUSTER'..."
    kind_node_kubectl_stdin apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $KIND_NAMESPACE
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $KIND_SA
  namespace: $KIND_NAMESPACE
---
# Администратор своего namespace (встроенная роль admin).
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: agentcell-admin
  namespace: $KIND_NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
- kind: ServiceAccount
  name: $KIND_SA
  namespace: $KIND_NAMESPACE
---
# Чтение общих сведений о кластере, чтобы агенту было проще в нём ориентироваться.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: agentcell-cluster-view
rules:
- apiGroups: [""]
  resources: ["nodes", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: agentcell-cluster-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: agentcell-cluster-view
subjects:
- kind: ServiceAccount
  name: $KIND_SA
  namespace: $KIND_NAMESPACE
EOF
}

# cluster-admin — только на одну сессию по AGENTCELL_KIND_ADMIN=1. Запуск без неё
# убирает привязку: права пропадают сразу, даже если старый токен ещё не истёк.
# Привязка общая для кластера: обычный запуск, начатый при работающей сессии с
# AGENTCELL_KIND_ADMIN=1, снимет права и у неё.
kind_apply_admin_mode() {
    if [ "${AGENTCELL_KIND_ADMIN:-0}" = "1" ]; then
        kind_node_kubectl_stdin apply -f - >/dev/null <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: agentcell-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: $KIND_SA
  namespace: $KIND_NAMESPACE
EOF
        warn "The agent has cluster-admin in kind cluster '$KIND_CLUSTER' for this session."
        warn "A privileged pod can escape into the agentcell VM and reach every PROJECT_DIR and the state folder."
    else
        kind_node_kubectl delete clusterrolebinding agentcell-cluster-admin --ignore-not-found >/dev/null
    fi
}

# Пишет kubeconfig агента: адрес ноды внутри docker-сети, сертификат CA кластера и
# токен ServiceAccount. Сертификат администратора кластера сюда не попадает.
# Отдельный файл на кластер, чтобы параллельные сессии с разными кластерами не
# перезаписывали друг друга.
kind_write_kubeconfig() {
    local token ca_data kube_dir
    token="$(kind_node_kubectl create token "$KIND_SA" -n "$KIND_NAMESPACE" --duration="$KIND_TOKEN_TTL")"
    # base64 без переносов строк одинаково на macOS и Linux.
    ca_data="$(dkr exec "$KIND_NODE" cat /etc/kubernetes/pki/ca.crt | base64 | tr -d '\n')"

    kube_dir="$STATE_REAL/.kube"
    mkdir -p "$kube_dir"
    chmod 700 "$kube_dir"
    # umask 077 в подоболочке: файл с токеном сразу создаётся с правами 600.
    (
        umask 077
        cat > "$kube_dir/$KIND_KUBECONFIG_NAME" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: kind-$KIND_CLUSTER
  cluster:
    server: https://$KIND_NODE:6443
    certificate-authority-data: $ca_data
users:
- name: $KIND_SA
  user:
    token: $token
contexts:
- name: kind-$KIND_CLUSTER
  context:
    cluster: kind-$KIND_CLUSTER
    user: $KIND_SA
    namespace: $KIND_NAMESPACE
current-context: kind-$KIND_CLUSTER
EOF
    )
}
