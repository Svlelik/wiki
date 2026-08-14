# Миграция Talos/Kubernetes и Cilium 1.20 для исправления gRPC-web Argo CD

Практический runbook выполненной миграции однонодового кластера
`kubernetes-admin@k8s-dev`:

- Kubernetes `1.32.3 -> 1.33.13 -> 1.34.10 -> 1.35.7`;
- Cilium `1.19.6 -> 1.20.0`;
- Gateway API experimental bundle `v1.6.1`;
- отказ от hostname-scoped HTTPS listeners и Argo CD TLS passthrough;
- один общий HTTPS listener и `HTTPRoute -> argocd-server:80`;
- отключение преобразования gRPC-web в native gRPC.

> **Важно:** команды `upgrade-k8s`, `helm upgrade`, применение CRD, Gateway и
> удаление routes изменяют живой кластер. Выполняйте их только после snapshot,
> проверки rollback и подтверждения правильного context. На однонодовом
> control plane перезапуск API server временно прерывает доступ к Kubernetes.

## 1. Причина миграции

Исходная схема:

```text
Client
  -> HTTPS Cilium Gateway
  -> TLS termination в Envoy
  -> HTTPRoute
  -> argocd-server:80
```

На Cilium `1.19.6` Envoy преобразовывал gRPC-web в native gRPC. Argo CD на
HTTP-порту ожидал gRPC-web, поэтому:

- UI и REST работали;
- `/session.SessionService/Create` возвращал `404`;
- добавление только `--grpc-web` в CLI не устраняло несовместимость на Gateway.

Временный TLS passthrough до `argocd-server:443` обходил L7-преобразование, но
сочетание общего HTTPS listener и TLS passthrough listener на `:443` приводило
к `ProtocolConflict` в Cilium 1.19. Пришлось перечислить HTTPS hostnames в
отдельных listeners.

Cilium 1.20 добавляет `CiliumGatewayClassConfig` с настройкой:

```yaml
spec:
  httpOptions:
    grpcWebTranslation:
      enabled: false
```

После ее применения можно снова завершать TLS на одном общем HTTPS listener и
передавать исходный gRPC-web на HTTP backend Argo CD.

## 2. Переменные

Перед началом задайте параметры окружения:

```bash
export CTX='kubernetes-admin@k8s-dev'
export NODE='ap-k8s-dev'
export TALOS_ENDPOINT='192.168.215.17'
export GATEWAY_VIP='192.168.215.9'

export K8S_OLD='1.32.3'
export K8S_133='1.33.13'
export K8S_134='1.34.10'
export K8S_135='1.35.7'
export CILIUM_OLD='1.19.6'
export CILIUM_NEW='1.20.0'
export GATEWAY_API_VERSION='1.6.1'
export TALOSCTL_VERSION='1.13.5'

export INFRA_REPO='/path/to/talos-dev'
export TALOSCONFIG_SOPS="$INFRA_REPO/talosconfig"
export ADMIN_NS='kube-system'
export ADMIN_POD='talos-migration-admin'
export ADMIN_SECRET='talos-migration-config'

export BACKUP_DIR="/tmp/talos-dev-migration-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$BACKUP_DIR"
```

Проверьте context и API server:

```bash
kubectl --context="$CTX" config current-context
kubectl --context="$CTX" config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl --context="$CTX" get nodes -o wide
kubectl --context="$CTX" get --raw=/readyz
```

Ожидаемый context — `kubernetes-admin@k8s-dev`, API server —
`https://192.168.215.17:6443`.

## 3. Preflight и rollback

### 3.1. Состояние Kubernetes, DNS и Cilium

```bash
kubectl --context="$CTX" get nodes
kubectl --context="$CTX" get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl --context="$CTX" get events -A --field-selector=type=Warning

kubectl --context="$CTX" -n kube-system \
  get deployment coredns cilium-operator
kubectl --context="$CTX" -n kube-system \
  get daemonset cilium
kubectl --context="$CTX" -n kube-system \
  exec daemonset/cilium -- cilium-dbg status --brief
```

Проверьте deprecated API:

```bash
kubectl --context="$CTX" get --raw /metrics \
  | awk '/apiserver_requested_deprecated_apis/ && $NF != "0" {print}'

kubectl --context="$CTX" get ciliumnodeconfigs.cilium.io -A
```

Перед обновлением Cilium 1.20 объектов `CiliumNodeConfig/v2alpha1` быть не
должно. В выполненной миграции API фиксировался в метрике, но список объектов
был пуст.

### 3.2. Сохранение live-конфигурации

```bash
helm --kube-context "$CTX" -n kube-system \
  get values cilium -a -o yaml \
  > "$BACKUP_DIR/cilium-values-${CILIUM_OLD}.yaml"

kubectl --context="$CTX" -n cilium-gateway \
  get gateway ingress -o yaml \
  > "$BACKUP_DIR/gateway-before.yaml"

helm --kube-context "$CTX" -n argocd history argocd \
  > "$BACKUP_DIR/argocd-helm-history.txt"

shasum -a 256 "$BACKUP_DIR"/*
```

Не сохраняйте через `kubectl get secret -o yaml` TLS-ключи или Argo CD
credentials в обычные незашифрованные файлы.

### 3.3. Проверка внешних endpoints

```bash
curl --fail --silent --show-error --output /dev/null \
  --resolve "argocd-talos-dev.oro.moscow:443:${GATEWAY_VIP}" \
  https://argocd-talos-dev.oro.moscow/

curl --fail --silent --show-error --output /dev/null \
  --resolve "apc-dev.oro.moscow:443:${GATEWAY_VIP}" \
  https://apc-dev.oro.moscow/
```

Не продолжайте обновление, если control plane, Cilium, CoreDNS или основные
маршруты уже деградировали.

## 4. Если Talos API `:50000` недоступен с рабочей станции

В этом окружении Kubernetes API `:6443` был доступен, но прямое подключение
`talosctl` к `192.168.215.17:50000` завершалось timeout.

Проверка с рабочей станции:

```bash
nc -vz -w 5 "$TALOS_ENDPOINT" 50000
```

Проверка из host network ноды:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" run talos-connectivity-test \
  --image=alpine:3.22 \
  --restart=Never \
  --overrides="$(printf \
    '{"spec":{"hostNetwork":true,"nodeName":"%s"}}' "$NODE")" \
  --command -- sh -c "nc -zvw5 '$TALOS_ENDPOINT' 50000"

kubectl --context="$CTX" -n "$ADMIN_NS" \
  wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/talos-connectivity-test --timeout=60s
kubectl --context="$CTX" -n "$ADMIN_NS" logs talos-connectivity-test
kubectl --context="$CTX" -n "$ADMIN_NS" \
  delete pod talos-connectivity-test
```

Если порт доступен из host network, но недоступен с рабочей станции, можно
временно запускать `talosctl` в host-network pod.

### 4.1. Краткоживущий Secret с talosconfig

> **Секретная операция:** следующая команда расшифровывает `talosconfig` и
> передает его в Kubernetes Secret. Не выводите расшифрованный файл в терминал,
> не сохраняйте его в Git и не оставляйте Secret после завершения. Убедитесь,
> что доступ к namespace ограничен RBAC.

```bash
cd "$INFRA_REPO"

sops -d --input-type yaml --output-type yaml "$TALOSCONFIG_SOPS" \
  | kubectl --context="$CTX" -n "$ADMIN_NS" \
      create secret generic "$ADMIN_SECRET" \
      --from-file=talosconfig=/dev/stdin
```

Проверять можно только имя объекта, не содержимое:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" \
  get secret "$ADMIN_SECRET" -o name
```

### 4.2. Временный административный pod

```bash
envsubst <<'EOF' \
  | kubectl --context="$CTX" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${ADMIN_POD}
  namespace: ${ADMIN_NS}
spec:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  nodeName: ${NODE}
  restartPolicy: Never
  automountServiceAccountToken: false
  containers:
    - name: admin
      image: alpine:3.22
      command: ["sh", "-c"]
      args:
        - >-
          wget -q -O /work/talosctl
          https://github.com/siderolabs/talos/releases/download/v${TALOSCTL_VERSION}/talosctl-linux-amd64
          && chmod 0700 /work/talosctl
          && sleep 28800
      volumeMounts:
        - name: config
          mountPath: /config
          readOnly: true
        - name: work
          mountPath: /work
  volumes:
    - name: config
      secret:
        secretName: ${ADMIN_SECRET}
        defaultMode: 0400
    - name: work
      emptyDir: {}
EOF

kubectl --context="$CTX" -n "$ADMIN_NS" \
  wait --for=condition=Ready "pod/$ADMIN_POD" --timeout=180s
```

Проверка Talos:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" exec "$ADMIN_POD" -- \
  /work/talosctl \
  --talosconfig /config/talosconfig \
  --endpoints "$TALOS_ENDPOINT" \
  --nodes "$TALOS_ENDPOINT" \
  version
```

Это обходной путь, а не исправление сети. Для постоянной эксплуатации нужно
отдельно проверить firewall, VPN, ACL и маршрут от рабочей станции до Talos
API `:50000`.

## 5. Etcd snapshot

> **Высокая чувствительность:** etcd snapshot содержит все состояние
> Kubernetes, включая Secrets. Храните файл с правами `0600`, не добавляйте в
> Git и перенесите из `/tmp` в одобренное зашифрованное хранилище.

Создание snapshot:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" exec "$ADMIN_POD" -- \
  /work/talosctl \
  --talosconfig /config/talosconfig \
  --endpoints "$TALOS_ENDPOINT" \
  --nodes "$TALOS_ENDPOINT" \
  etcd snapshot /work/pre-migration.snapshot
```

Сжатие внутри pod уменьшает риск обрыва `kubectl cp`:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" exec "$ADMIN_POD" -- \
  sh -c 'gzip -c /work/pre-migration.snapshot > /work/pre-migration.snapshot.gz'

kubectl --context="$CTX" -n "$ADMIN_NS" exec "$ADMIN_POD" -- \
  ls -lh /work/pre-migration.snapshot /work/pre-migration.snapshot.gz
```

Копирование и проверка:

```bash
SNAPSHOT="$BACKUP_DIR/talos-dev-etcd-pre-migration.snapshot.gz"

kubectl --context="$CTX" -n "$ADMIN_NS" cp \
  "$ADMIN_POD:/work/pre-migration.snapshot.gz" \
  "$SNAPSHOT"

chmod 600 "$SNAPSHOT"
gzip -t "$SNAPSHOT"
shasum -a 256 "$SNAPSHOT" | tee "$SNAPSHOT.sha256"
```

Во время выполненной миграции проверенный backup был сохранен как:

```text
/tmp/talos-dev-etcd-pre-migration-20260814.snapshot.gz
```

Его размер был `8852651` байт, SHA-256:

```text
45e0f85215f18a38d24fe1d00659343589845bd098defb280353e9c566044a24
```

Значение checksum не раскрывает содержимое snapshot, но сам файл остается
секретным.

## 6. Последовательное обновление Kubernetes

Talos не позволяет перескакивать через minor-версии. Использован порядок:

```text
1.32.3 -> 1.33.13 -> 1.34.10 -> 1.35.7
```

Cilium 1.20 требует Kubernetes не ниже 1.33, поэтому Cilium обновлялся только
после завершения всех Kubernetes hops до целевой версии 1.35.7.

### 6.1. Dry-run каждого шага

```bash
dry_run_k8s_upgrade() {
  target="$1"
  kubectl --context="$CTX" -n "$ADMIN_NS" exec "$ADMIN_POD" -- \
    /work/talosctl \
    --talosconfig /config/talosconfig \
    --endpoints "$TALOS_ENDPOINT" \
    --nodes "$TALOS_ENDPOINT" \
    upgrade-k8s --to "$target" --dry-run
}

dry_run_k8s_upgrade "$K8S_133"
```

Переходите к следующему dry-run только после фактического обновления и проверки
предыдущей версии.

### 6.2. One-shot pod для upgrade

Не запускайте долгий `upgrade-k8s` обычным `kubectl exec`: перезапуск API
server может оборвать stream. Отдельный pod продолжит работать независимо от
соединения клиента.

> **Высокорисковая операция:** функция ниже изменяет компоненты control plane и
> kubelet. Snapshot и rollback-файлы должны быть уже проверены.

```bash
upgrade_k8s() {
  target="$1"
  suffix="$(printf '%s' "$target" | tr '.' '-')"
  pod="talos-upgrade-k8s-$suffix"

  cat <<EOF | kubectl --context="$CTX" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  namespace: ${ADMIN_NS}
  labels:
    migration.talos.dev/role: k8s-upgrade
spec:
  hostNetwork: true
  nodeName: ${NODE}
  restartPolicy: Never
  automountServiceAccountToken: false
  containers:
    - name: talosctl
      image: ghcr.io/siderolabs/talosctl:v${TALOSCTL_VERSION}
      command: ["/talosctl"]
      args:
        - --talosconfig
        - /config/talosconfig
        - --endpoints
        - ${TALOS_ENDPOINT}
        - --nodes
        - ${TALOS_ENDPOINT}
        - upgrade-k8s
        - --to
        - ${target}
      volumeMounts:
        - name: config
          mountPath: /config
          readOnly: true
  volumes:
    - name: config
      secret:
        secretName: ${ADMIN_SECRET}
        defaultMode: 0400
EOF

  while true; do
    phase="$(
      kubectl --context="$CTX" -n "$ADMIN_NS" \
        get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true
    )"

    case "$phase" in
      Succeeded)
        kubectl --context="$CTX" -n "$ADMIN_NS" logs "$pod"
        break
        ;;
      Failed)
        kubectl --context="$CTX" -n "$ADMIN_NS" logs "$pod"
        return 1
        ;;
    esac

    sleep 5
  done
}
```

### 6.3. Проверки после каждого minor hop

```bash
verify_k8s_hop() {
  kubectl --context="$CTX" version -o json \
    | jq -r '.serverVersion.gitVersion'

  kubectl --context="$CTX" get nodes \
    -o custom-columns='NAME:.metadata.name,READY:.status.conditions[-1].status,KUBELET:.status.nodeInfo.kubeletVersion'

  kubectl --context="$CTX" get --raw=/readyz

  kubectl --context="$CTX" -n kube-system \
    exec daemonset/cilium -- cilium-dbg status --brief

  kubectl --context="$CTX" -n kube-system \
    get deployment coredns \
    -o jsonpath='CoreDNS ready={.status.readyReplicas}/{.status.replicas}{"\n"}'

  curl --fail --silent --show-error --output /dev/null \
    --resolve "argocd-talos-dev.oro.moscow:443:${GATEWAY_VIP}" \
    https://argocd-talos-dev.oro.moscow/
}
```

Последовательность:

```bash
dry_run_k8s_upgrade "$K8S_133"
upgrade_k8s "$K8S_133"
verify_k8s_hop

dry_run_k8s_upgrade "$K8S_134"
upgrade_k8s "$K8S_134"
verify_k8s_hop

dry_run_k8s_upgrade "$K8S_135"
upgrade_k8s "$K8S_135"
verify_k8s_hop
```

Не переходите к следующему hop при `Ready=False`, ошибке `/readyz`, проблемах
Cilium/CoreDNS или недоступности основных endpoints.

## 7. Обновление image pins в инфраструктурном репозитории

После успешного обновления live-кластера замените `v1.32.3` на `v1.35.7`:

- `controlplane.yaml`:
  - `ghcr.io/siderolabs/kubelet:v1.35.7`;
  - `registry.k8s.io/kube-apiserver:v1.35.7`;
  - `registry.k8s.io/kube-controller-manager:v1.35.7`;
  - `registry.k8s.io/kube-proxy:v1.35.7`;
  - `registry.k8s.io/kube-scheduler:v1.35.7`;
- `ap-k8s-dev.yaml` — те же component images;
- `worker.yaml` — `ghcr.io/siderolabs/kubelet:v1.35.7`;
- `argocd/values.yaml` — init container `KUBECTL_VERSION: "1.35.7"`.

Проверка:

```bash
cd "$INFRA_REPO"

rg 'v1\.32\.3|1\.32\.3' \
  controlplane.yaml worker.yaml ap-k8s-dev.yaml argocd/values.yaml

talosctl validate --config ap-k8s-dev.yaml --mode metal
```

Первый `rg` после редактирования не должен находить старые image pins.

## 8. Gateway API experimental CRDs v1.6.1

Сначала server-side dry-run:

```bash
GATEWAY_API_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GATEWAY_API_VERSION}/experimental-install.yaml"

kubectl --context="$CTX" apply --server-side --dry-run=server \
  -f "$GATEWAY_API_URL"
```

> **Кластерная операция:** CRD действуют на весь кластер.

```bash
kubectl --context="$CTX" apply --server-side \
  -f "$GATEWAY_API_URL"
```

Проверка версий `TLSRoute`:

```bash
kubectl --context="$CTX" \
  get crd tlsroutes.gateway.networking.k8s.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{" storage="}{.storage}{"\n"}{end}'
```

Ожидается `v1 served=true storage=true`. Пока passthrough еще используется,
обновите временный `argocd-tlsroute.yaml` с `v1alpha2` на
`gateway.networking.k8s.io/v1`. После финального переключения `TLSRoute` будет
удален.

## 9. Cilium 1.19.6 -> 1.20.0

### 9.1. Values и рендер

Добавьте в `cilium/values.yaml`:

```yaml
upgradeCompatibility: "1.19"
```

Проверка chart:

```bash
cd "$INFRA_REPO"

helm repo add cilium https://helm.cilium.io/
helm repo update cilium

helm template cilium cilium/cilium \
  --version "$CILIUM_NEW" \
  --namespace kube-system \
  -f cilium/values.yaml \
  > /dev/null
```

### 9.2. Cilium preflight

```bash
helm --kube-context "$CTX" upgrade --install cilium-preflight cilium/cilium \
  --version "$CILIUM_NEW" \
  --namespace kube-system \
  --set preflight.enabled=true \
  --set agent=false \
  --set operator.enabled=false \
  --wait \
  --timeout 10m

kubectl --context="$CTX" -n kube-system \
  get daemonset,deployment -l k8s-app=cilium-pre-flight-check

kubectl --context="$CTX" -n kube-system \
  logs -l app.kubernetes.io/name=cilium-pre-flight-check \
  --all-containers --prefix
```

В логах должно быть:

```text
All CCNPs and CNPs valid!
```

### 9.3. Helm upgrade

> **Высокорисковая сетевая операция:** обновляется CNI и Envoy datapath.

```bash
helm --kube-context "$CTX" upgrade cilium cilium/cilium \
  --version "$CILIUM_NEW" \
  --namespace kube-system \
  -f cilium/values.yaml \
  --wait \
  --timeout 15m
```

Проверка:

```bash
helm --kube-context "$CTX" -n kube-system status cilium

kubectl --context="$CTX" -n kube-system \
  get daemonset cilium cilium-envoy
kubectl --context="$CTX" -n kube-system \
  get deployment cilium-operator hubble-relay hubble-ui

kubectl --context="$CTX" -n kube-system \
  exec daemonset/cilium -- cilium-dbg status --brief
kubectl --context="$CTX" -n kube-system \
  exec daemonset/cilium -- cilium-dbg version
```

После успешного обновления удалите preflight release:

```bash
helm --kube-context "$CTX" -n kube-system uninstall cilium-preflight
```

## 10. Отключение gRPC-web translation

Создайте `cilium/cilium-gateway-class-config.yaml`:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumGatewayClassConfig
metadata:
  name: cilium
  namespace: kube-system
spec:
  description: Disable gRPC-Web translation at Cilium Gateways
  httpOptions:
    grpcWebTranslation:
      enabled: false
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
  parametersRef:
    group: cilium.io
    kind: CiliumGatewayClassConfig
    name: cilium
    namespace: kube-system
```

Проверка и применение:

```bash
kubectl --context="$CTX" apply --dry-run=server \
  -f cilium/cilium-gateway-class-config.yaml

kubectl --context="$CTX" apply \
  -f cilium/cilium-gateway-class-config.yaml
```

Проверьте оба объекта:

```bash
kubectl --context="$CTX" -n kube-system \
  get ciliumgatewayclassconfig cilium -o yaml

kubectl --context="$CTX" \
  get gatewayclass cilium -o yaml
```

Условия должны содержать `Accepted=True`. В `GatewayClass` должен появиться
`gateway.cilium.io/config-checksum`, подтверждающий обработку config.

## 11. Общий HTTPS listener и HTTPRoute Argo CD

### 11.1. Целевой Gateway

В `cilium/cilium-gateway.yaml` оставьте только общий HTTP и общий HTTPS
listeners:

```yaml
listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All

  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
        - group: ""
          kind: Secret
          name: oromoscow
          namespace: mediascope
    allowedRoutes:
      kinds:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
        - group: gateway.networking.k8s.io
          kind: GRPCRoute
      namespaces:
        from: All
```

Удалите из целевого манифеста:

- 13 hostname-scoped HTTPS listeners;
- listener `argocd-tls`;
- `TLSRoute` passthrough после успешной проверки нового маршрута.

### 11.2. HTTPRoute Argo CD

`manifests/argocd-httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  parentRefs:
    - name: ingress
      namespace: cilium-gateway
  hostnames:
    - argocd-talos-dev.oro.moscow
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 80
```

### 11.3. Argo CD HTTP backend

В `argocd/values.yaml`:

```yaml
configs:
  params:
    server.insecure: true

server:
  certificateSecret:
    enabled: false
  ingress:
    enabled: false
  service:
    type: ClusterIP
```

Проверьте Helm render без вывода values:

```bash
helm template argocd \
  oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --version 10.3.2 \
  --namespace argocd \
  -f argocd/values.yaml \
  > /dev/null

kubectl --context="$CTX" apply --dry-run=server \
  -f manifests/argocd-httproute.yaml \
  -f cilium/cilium-gateway.yaml
```

## 12. Согласованное переключение и автоматический rollback

Сохраните текущую revision Argo CD и Gateway:

```bash
ARGO_ROLLBACK_REV="$(
  helm --kube-context "$CTX" -n argocd history argocd -o json \
    | jq -r '.[-1].revision'
)"

kubectl --context="$CTX" -n cilium-gateway \
  get gateway ingress -o yaml \
  > "$BACKUP_DIR/gateway-switch-rollback.yaml"
```

Не удаляйте live `TLSRoute` до завершения проверки нового маршрута.

> **Высокорисковая операция:** между перезапуском Argo CD в HTTP-режиме и
> перепрограммированием Gateway возможен короткий перерыв доступности.

```bash
cd "$INFRA_REPO"

if \
  helm --kube-context "$CTX" upgrade argocd \
    oci://ghcr.io/argoproj/argo-helm/argo-cd \
    --version 10.3.2 \
    --namespace argocd \
    -f argocd/values.yaml \
    --wait \
    --timeout 10m \
  && kubectl --context="$CTX" apply \
    -f manifests/argocd-httproute.yaml \
  && kubectl --context="$CTX" apply \
    -f cilium/cilium-gateway.yaml \
  && kubectl --context="$CTX" -n cilium-gateway \
    wait --for=condition=Accepted gateway/ingress --timeout=120s \
  && kubectl --context="$CTX" -n cilium-gateway \
    wait --for=condition=Programmed gateway/ingress --timeout=120s \
  && curl --fail --silent --show-error --output /dev/null \
    --resolve "argocd-talos-dev.oro.moscow:443:${GATEWAY_VIP}" \
    https://argocd-talos-dev.oro.moscow/
then
  echo 'Switch completed'
else
  echo 'Switch failed, rolling back' >&2

  helm --kube-context "$CTX" rollback argocd "$ARGO_ROLLBACK_REV" \
    --namespace argocd \
    --wait \
    --timeout 10m

  kubectl --context="$CTX" apply \
    -f "$BACKUP_DIR/gateway-switch-rollback.yaml"

  kubectl --context="$CTX" -n argocd \
    delete httproute argocd --ignore-not-found

  exit 1
fi
```

Если rollback потребовался, убедитесь, что прежний `TLSRoute`, listener
`argocd-tls`, Argo CD TLS mode и `argocd-server-tls` восстановлены.

## 13. Итоговая проверка

### 13.1. Kubernetes и Cilium

```bash
kubectl --context="$CTX" version -o json \
  | jq -r '"Kubernetes " + .serverVersion.gitVersion'

kubectl --context="$CTX" get nodes
kubectl --context="$CTX" get --raw=/readyz

kubectl --context="$CTX" -n kube-system \
  exec daemonset/cilium -- cilium-dbg status --brief
kubectl --context="$CTX" -n kube-system \
  exec daemonset/cilium -- cilium-dbg version
```

Фактический результат:

```text
Kubernetes v1.35.7
ap-k8s-dev v1.35.7 Ready=True
Cilium 1.20.0: OK
```

### 13.2. GatewayClass, config, listeners и routes

```bash
kubectl --context="$CTX" get gatewayclass cilium -o json \
  | jq -e '.status.conditions[]
      | select(.type == "Accepted" and .status == "True")' \
  > /dev/null

kubectl --context="$CTX" -n kube-system \
  get ciliumgatewayclassconfig cilium -o json \
  | jq -e '
      .spec.httpOptions.grpcWebTranslation.enabled == false
      and (
        .status.conditions[]
        | select(.type == "Accepted" and .status == "True")
      )' \
  > /dev/null

kubectl --context="$CTX" -n cilium-gateway \
  get gateway ingress -o json \
  | jq -r '
      .status.listeners[]
      | [
          .name,
          (.attachedRoutes | tostring),
          ([.conditions[] | select(.status != "True") | .type] | join(","))
        ]
      | @tsv'

kubectl --context="$CTX" get httproute -A -o json \
  | jq -r '
      .items[]
      | select(any(.status.parents[]?.conditions[]?; .status != "True"))
      | [.metadata.namespace, .metadata.name]
      | @tsv'
```

Фактический результат:

```text
GatewayClass/cilium Accepted=True
CiliumGatewayClassConfig/cilium Accepted=True
Gateway/ingress Accepted=True Programmed=True
listeners: http, https
http attachedRoutes=61
https attachedRoutes=61
HTTPRoute с отрицательными conditions отсутствуют
```

### 13.3. gRPC-web: проверка framed request

Создайте бинарный gRPC-web frame с заведомо неверными данными:

```bash
GRPC_REQUEST="$(mktemp)"
GRPC_HEADERS="$(mktemp)"
GRPC_BODY="$(mktemp)"

chmod 600 "$GRPC_REQUEST" "$GRPC_HEADERS" "$GRPC_BODY"

printf '\000\000\000\000\006\012\001x\022\001x' > "$GRPC_REQUEST"

curl --silent --show-error --http1.1 \
  --dump-header "$GRPC_HEADERS" \
  --output "$GRPC_BODY" \
  --write-out 'grpc-web HTTP %{http_code}\n' \
  --resolve "argocd-talos-dev.oro.moscow:443:${GATEWAY_VIP}" \
  -H 'content-type: application/grpc-web+proto' \
  -H 'x-grpc-web: 1' \
  --data-binary "@$GRPC_REQUEST" \
  https://argocd-talos-dev.oro.moscow/session.SessionService/Create

awk 'BEGIN { IGNORECASE=1 }
     /^(HTTP|content-type:|grpc-|x-envoy)/ { print }' \
  "$GRPC_HEADERS"
```

Ожидаемый и фактически полученный результат:

```text
grpc-web HTTP 200
HTTP/1.1 200 OK
content-type: application/grpc-web+proto
grpc-message: Invalid username or password
grpc-status: 16
```

`grpc-status: 16` ожидаем для неверных credential. Главное — endpoint отвечает
gRPC-web `HTTP 200`, а не прежним `404`.

Удалите временные файлы:

```bash
rm -f "$GRPC_REQUEST" "$GRPC_HEADERS" "$GRPC_BODY"
```

### 13.4. Проверка прежних HTTPS hostnames

```bash
for host in \
  apc-dev.oro.moscow \
  apcn-dev.oro.moscow \
  apm-dev.oro.moscow \
  apr-dev.oro.moscow \
  aprw-dev.oro.moscow \
  aps-dev.oro.moscow \
  apt-dev.oro.moscow \
  backend-dev.oro.moscow \
  gtn-dev.oro.moscow \
  gtnn-dev.oro.moscow \
  mpf-dev.oro.moscow \
  mpu-dev.oro.moscow \
  redis-dev.oro.moscow
do
  code="$(
    curl --silent --show-error --max-time 10 \
      --output /dev/null \
      --write-out '%{http_code}' \
      --resolve "${host}:443:${GATEWAY_VIP}" \
      "https://${host}/" \
      || true
  )"

  printf '%-32s %s\n' "$host" "$code"
  test "$code" != '000' || exit 1
done
```

Во время миграции все hostnames установили TLS/HTTP-соединение. Были получены
ожидаемые ответы приложений `200`, `307` и `404`; код `000` отсутствовал.
`404` от `backend-dev` означал ответ самого backend на `/`, а не отказ
Gateway.

### 13.5. Argo CD и rollback Secret

```bash
kubectl --context="$CTX" -n argocd \
  get configmap argocd-cmd-params-cm \
  -o jsonpath='server.insecure={.data.server\.insecure}{"\n"}'

kubectl --context="$CTX" -n argocd \
  get deployment argocd-server \
  -o jsonpath='ready={.status.readyReplicas}/{.status.replicas}{"\n"}'

kubectl --context="$CTX" -n argocd \
  get httproute argocd \
  -o jsonpath='backendPort={.spec.rules[0].backendRefs[0].port}{"\n"}'

kubectl --context="$CTX" -n argocd \
  get secret argocd-server-tls -o name
```

Ожидается:

```text
server.insecure=true
ready=1/1
backendPort=80
secret/argocd-server-tls
```

Не выводите содержимое `argocd-server-tls`.

## 14. Удаление старого TLSRoute

После успешной end-to-end проверки:

> **Изменяющая операция:** после удаления live `TLSRoute` rollback потребует
> его повторного применения из предыдущей Git revision или backup.

```bash
kubectl --context="$CTX" delete \
  -f manifests/argocd-tlsroute.yaml \
  --ignore-not-found
```

Удалите `manifests/argocd-tlsroute.yaml` из целевой версии инфраструктурного
репозитория. `argocd-server-tls` пока оставьте как rollback-ресурс.

## 15. Cleanup временного доступа Talos

> **Обязательно:** Secret с `talosconfig` не должен оставаться в кластере.

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" \
  delete pod "$ADMIN_POD" --ignore-not-found

kubectl --context="$CTX" -n "$ADMIN_NS" \
  delete pod -l migration.talos.dev/role=k8s-upgrade --ignore-not-found

kubectl --context="$CTX" -n "$ADMIN_NS" \
  delete secret "$ADMIN_SECRET" --ignore-not-found
```

Если upgrade pods создавались без общей label, удалите их по именам:

```bash
for pod in $(
  kubectl --context="$CTX" -n "$ADMIN_NS" get pods -o name \
    | awk '/talos-upgrade-k8s-/ {print}'
); do
  kubectl --context="$CTX" -n "$ADMIN_NS" delete "$pod"
done
```

Проверка отсутствия временных ресурсов:

```bash
kubectl --context="$CTX" -n "$ADMIN_NS" get pod,secret \
  | awk '/talos-(migration|upgrade)/ {print; found=1}
         END {exit found ? 1 : 0}'
```

Сохраните только проверенный сжатый etcd snapshot и rollback-файлы. Перенесите
их из `/tmp` в защищенное хранилище по локальной политике retention.

## 16. Итоговая архитектура

```text
Client
  |
  | HTTPS :443
  v
VIP 192.168.215.9
  |
  v
Cilium Gateway ingress
  |
  | общий listener https
  | TLS termination: Secret mediascope/oromoscow
  | grpcWebTranslation.enabled: false
  v
HTTPRoute argocd/argocd
  |
  | HTTP / неизмененный gRPC-web
  v
Service argocd-server:80
  |
  v
argocd-server (server.insecure: true)
```

Добавление нового HTTPS hostname больше не требует изменения Gateway listeners:
достаточно создать новый `HTTPRoute`.

## 17. Контрольный список

- [ ] Проверен правильный context и API server.
- [ ] Kubernetes, CoreDNS, Cilium и endpoints здоровы до начала.
- [ ] Сохранены Helm values, Gateway и Argo CD revision для rollback.
- [ ] Etcd snapshot создан, сжат, скопирован и проверен.
- [ ] Каждый Kubernetes minor hop прошел dry-run.
- [ ] После каждого hop проверены `/readyz`, node, DNS, Cilium и endpoints.
- [ ] Git image pins обновлены до `v1.35.7`.
- [ ] Gateway API experimental CRDs обновлены до `v1.6.1`.
- [ ] Cilium preflight завершен успешно.
- [ ] Cilium `1.20.0` развернут и здоров.
- [ ] `CiliumGatewayClassConfig` и `GatewayClass` имеют `Accepted=True`.
- [ ] Gateway содержит только общие listeners `http` и `https`.
- [ ] Argo CD работает с `server.insecure=true` и backend port `80`.
- [ ] gRPC-web возвращает HTTP `200`, а не `404`.
- [ ] Прежние HTTPS hostnames устанавливают соединение.
- [ ] Старый `TLSRoute` удален только после проверки.
- [ ] Временные Talos pod и Secret удалены.
- [ ] `argocd-server-tls` сохранен для rollback.
- [ ] Snapshot перенесен в защищенное хранилище.
