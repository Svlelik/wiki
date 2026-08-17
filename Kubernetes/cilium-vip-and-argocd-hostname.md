# Смена Cilium Gateway VIP и hostname Argo CD

Практический runbook выполненного cutover однонодового кластера
`kubernetes-admin@k8s-dev` 2026-08-17:

- VIP Gateway `192.168.215.9 -> 192.168.215.18`;
- hostname Argo CD `argocd-talos-dev.oro.moscow -> argocd-dev.oro.moscow`;
- исправление зависания `argocd-repo-server` в `Init` на скачивании
  `kubectl` с `dl.k8s.io`.

Предыдущая миграция Kubernetes/Cilium и схема трафика описаны в
[talos-cilium-1.20-grpc-web-migration.md](talos-cilium-1.20-grpc-web-migration.md).
Там VIP и hostname ещё старые — после 2026-08-17 ориентируйтесь на этот файл.

> **Важно:** `kubectl apply` пула/Gateway/HTTPRoute и `helm upgrade` Argo CD
> меняют живой кластер. При прямой замене VIP старый адрес перестаёт
> анонсироваться сразу. На однонодовом кластере downtime допустим, если это
> согласовано. Перед изменяющими командами проверьте context.

## 1. Что меняется

Cilium как CNI и адрес ноды не трогаются. `192.168.215.9` — не IP агента, а
внешний VIP Gateway.

| Объект | Роль | Менять |
| --- | --- | --- |
| Нода `ap-k8s-dev` / API `192.168.215.17:6443` | control plane | нет |
| `cilium/values.yaml` → `k8sServiceHost` | API для агента | нет |
| `CiliumL2AnnouncementPolicy` | ARP всех LB IP на `ens192` | нет |
| `CiliumLoadBalancerIPPool/pool` | пул VIP | да |
| `Gateway cilium-gateway/ingress` | явный адрес | да |
| `HTTPRoute argocd/argocd` | Host | да |
| `argocd/values.yaml` → `domain`, `configs.cm.url` | внешний URL Argo CD | да |
| DNS A-запись и Keycloak redirect URI | доступ снаружи и OIDC | да, вне кластера |

```text
Client
  -> DNS argocd-dev.oro.moscow
  -> VIP 192.168.215.18  (CiliumLoadBalancerIPPool + L2 ARP на ens192)
  -> Cilium Gateway HTTPS :443
  -> HTTPRoute Host: argocd-dev.oro.moscow
  -> Service argocd-server:80
```

## 2. Переменные

```bash
export CTX='kubernetes-admin@k8s-dev'
export INFRA_REPO='/path/to/talos-dev'
export OLD_VIP='192.168.215.9'
export NEW_VIP='192.168.215.18'
export OLD_HOST='argocd-talos-dev.oro.moscow'
export NEW_HOST='argocd-dev.oro.moscow'
export ARGO_CHART_VERSION='10.3.2'
export ARGO_CHART_REPO='https://argoproj.github.io/argo-helm'

kubectl --context="$CTX" config current-context
kubectl --context="$CTX" get nodes -o wide
```

Ожидаемый context — `kubernetes-admin@k8s-dev`, нода —
`ap-k8s-dev` / `192.168.215.17`.

## 3. Preflight

Проверьте текущий VIP и hostname:

```bash
kubectl --context="$CTX" -n cilium-gateway get gateway ingress
kubectl --context="$CTX" -n cilium-gateway get svc cilium-gateway-ingress
kubectl --context="$CTX" get ciliumloadbalancerippool pool -o yaml
kubectl --context="$CTX" -n argocd get httproute argocd \
  -o jsonpath='{.spec.hostnames}{"\n"}'
kubectl --context="$CTX" -n argocd get cm argocd-cm \
  -o jsonpath='{.data.url}{"\n"}'
```

До cutover 2026-08-17 ожидалось:

- Gateway и Service: `192.168.215.9`;
- пул: `192.168.215.9/32`;
- HTTPRoute и `argocd-cm.url`: `argocd-talos-dev.oro.moscow`.

`NEW_VIP` должен быть свободен в той же L2-сети, что `ens192`
(`192.168.215.0/24`), и не висеть на другой машине.

Сохраните rollback-копии без секретов:

```bash
export BACKUP_DIR="/tmp/k8s-dev-vip-cutover-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$BACKUP_DIR"

kubectl --context="$CTX" get ciliumloadbalancerippool pool \
  -o yaml > "$BACKUP_DIR/ippool.yaml"
kubectl --context="$CTX" -n cilium-gateway get gateway ingress \
  -o yaml > "$BACKUP_DIR/gateway.yaml"
kubectl --context="$CTX" -n argocd get httproute argocd \
  -o yaml > "$BACKUP_DIR/httproute.yaml"
helm --kube-context "$CTX" -n argocd history argocd \
  > "$BACKUP_DIR/argocd-helm-history.txt"
```

Не копируйте в wiki и в git полный `helm get values`: в values есть
репозиторный пароль и OIDC client secret.

## 4. Смена VIP

В репозитории два файла:

`cilium/ippool.yaml`:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: pool
spec:
  blocks:
    - cidr: 192.168.215.18/32
```

`cilium/cilium-gateway.yaml` — поле адреса:

```yaml
spec:
  gatewayClassName: cilium
  addresses:
    - type: IPAddress
      value: 192.168.215.18
```

`l2-announcement-policy.yaml` и Helm-values Cilium не меняются.

Порядок при допустимом downtime: сначала пул, затем Gateway. Если сменить
Gateway раньше пула, запрошенный IP не будет в пуле.

> **Изменяющая операция:** старый VIP перестаёт анонсироваться.

```bash
kubectl --context="$CTX" apply -f "$INFRA_REPO/cilium/ippool.yaml"
kubectl --context="$CTX" apply -f "$INFRA_REPO/cilium/cilium-gateway.yaml"
kubectl --context="$CTX" -n cilium-gateway \
  wait --for=condition=Programmed gateway/ingress --timeout=90s
```

Возможен warning: `cilium.io/v2alpha1 CiliumLoadBalancerIPPool is deprecated;
use cilium.io/v2`. На Cilium 1.20 объект в API хранится как `v2`, apply из
`v2alpha1` всё равно проходит.

Проверка:

```bash
kubectl --context="$CTX" -n cilium-gateway get gateway ingress
kubectl --context="$CTX" -n cilium-gateway get svc cilium-gateway-ingress

curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Host: hubble.test" --connect-timeout 5 \
  "http://${NEW_VIP}/"

curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve "${NEW_HOST}:443:${NEW_VIP}" \
  -H "Host: ${NEW_HOST}" --connect-timeout 5 \
  "https://${NEW_HOST}/"
```

Ожидание: Gateway `PROGRAMMED=True`, `EXTERNAL-IP` сервиса равен `NEW_VIP`,
HTTP Hubble отвечает `200`. HTTPS Argo CD по новому VIP заработает после
смены HTTPRoute в следующем шаге; до неё Host ещё старый.

Старый VIP должен перестать отвечать:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  --connect-timeout 3 "http://${OLD_VIP}/" || true
```

Мягкий вариант без немедленного отказа `.9`: временно держать в пуле оба
`/32`, переключить Gateway, сменить DNS, затем убрать старый блок. 2026-08-17
выполнена прямая замена.

## 5. Смена hostname Argo CD

`manifests/argocd-httproute.yaml`:

```yaml
spec:
  parentRefs:
    - name: ingress
      namespace: cilium-gateway
  hostnames:
    - argocd-dev.oro.moscow
```

В `argocd/values.yaml` меняются только публичные поля:

```yaml
domain: argocd-dev.oro.moscow
configs:
  cm:
    url: https://argocd-dev.oro.moscow
```

`HTTPRoute` и остальные маршруты (`hubble-ui` и т.д.) цепляются к Gateway по
имени, не по VIP. Их не нужно переписывать из-за смены адреса.

> **Изменяющая операция:** старый Host перестаёт маршрутизироваться.
> `helm upgrade` перезапускает `argocd-server` и `argocd-repo-server`.

```bash
kubectl --context="$CTX" apply -f "$INFRA_REPO/manifests/argocd-httproute.yaml"

helm --kube-context "$CTX" upgrade argocd argo-cd \
  --repo "$ARGO_CHART_REPO" \
  --version "$ARGO_CHART_VERSION" \
  -n argocd \
  -f "$INFRA_REPO/argocd/values.yaml"

kubectl --context="$CTX" -n argocd \
  rollout status deploy/argocd-server --timeout=90s
```

Если локально нет `helm repo add argo`, флаг `--repo` достаточен.

Проверка:

```bash
kubectl --context="$CTX" -n argocd get httproute argocd \
  -o jsonpath='{.spec.hostnames}{"\n"}'
kubectl --context="$CTX" -n argocd get cm argocd-cm \
  -o jsonpath='{.data.url}{"\n"}'

curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve "${NEW_HOST}:443:${NEW_VIP}" \
  "https://${NEW_HOST}/"

curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve "${OLD_HOST}:443:${NEW_VIP}" \
  "https://${OLD_HOST}/"
```

Ожидание: новый Host — HTML UI Argo CD и `200`; старый Host — `404`.
Сразу после rollout возможен краткий `503`, пока новый `argocd-server` не
Ready.

## 6. DNS и Keycloak

Кластер не создаёт публичные DNS-записи.

- A-запись `argocd-dev.oro.moscow` должна указывать на `192.168.215.18`.
- Старое имя `argocd-talos-dev.oro.moscow` больше не обслуживается Gateway.
- В клиенте Keycloak `argocd-dev` нужно сменить redirect URI на
  `https://argocd-dev.oro.moscow/...`. Иначе UI откроется, а OIDC-логин
  уйдёт на старый hostname.

Проверка DNS с рабочей станции:

```bash
dig +short "$NEW_HOST"
```

Ожидание: `192.168.215.18`.

## 7. `argocd-repo-server` зависает в Init

`helm upgrade` пересоздаёт `argocd-repo-server`. Init `copyutil` завершается
сразу. Второй init `download-tools` качает инструменты в `emptyDir`:

- helm-secrets и sops с GitHub — обычно проходят;
- `kubectl` с `https://dl.k8s.io/release/v1.35.7/bin/linux/amd64/kubectl` —
  из этого кластера уходит в таймаут на Fastly (`151.101.x.x`);
- `wget -q` не пишет прогресс, под остаётся в `Init:1/2`.

Диагностика:

```bash
kubectl --context="$CTX" -n argocd get pods \
  -l app.kubernetes.io/name=argocd-repo-server

kubectl --context="$CTX" -n argocd describe pod \
  -l app.kubernetes.io/name=argocd-repo-server

kubectl --context="$CTX" -n argocd exec -c download-tools \
  deploy/argocd-repo-server -- ps aux
```

Если в `ps` виден `wget`/`ssl_client` на `dl.k8s.io`, а в `/custom-tools`
уже есть `helm-plugins` и `sops`, сеть до GitHub жива, а `dl.k8s.io` — нет.

Пока новый под в Init, старый replica set ещё может обслуживать манифесты.
Не удаляйте единственный Ready-под, пока новый не станет `1/1`.

Исправленный `repoServer.initContainers` в `argocd/values.yaml`:

```yaml
initContainers:
  - name: download-tools
    image: alpine:latest
    command: ["sh", "-ec"]
    env:
      - name: HELM_SECRETS_VERSION
        value: "4.7.7"
      - name: SOPS_VERSION
        value: "3.13.3"
      - name: CURL_VERSION
        value: "8.17.0"
    args:
      - |
        mkdir -p /custom-tools/helm-plugins
        wget --timeout=30 --tries=3 -qO- \
          https://github.com/jkroepke/helm-secrets/releases/download/v${HELM_SECRETS_VERSION}/helm-secrets.tar.gz \
          | tar -C /custom-tools/helm-plugins -xzf-

        wget --timeout=30 --tries=3 -qO /custom-tools/sops \
          https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64
        wget --timeout=30 --tries=3 -qO /custom-tools/curl \
          https://github.com/moparisthebest/static-curl/releases/download/v${CURL_VERSION}/curl-amd64

        apk add --no-cache kubectl
        install -m 0755 "$(command -v kubectl)" /custom-tools/kubectl
        chmod +x /custom-tools/sops /custom-tools/kubectl /custom-tools/curl
    volumeMounts:
      - mountPath: /custom-tools
        name: custom-tools
```

`kubectl` для helm-secrets не обязан совпадать с версией кластера `1.35.7`.
`CURL_VERSION` должен существовать в
[moparisthebest/static-curl](https://github.com/moparisthebest/static-curl/releases);
тега `v8.16.0` там нет, рабочий — `v8.17.0`.

После правки values повторите `helm upgrade` из раздела 5 и дождитесь:

```bash
kubectl --context="$CTX" -n argocd \
  rollout status deploy/argocd-repo-server --timeout=180s
```

Init с Alpine `apk` и GitHub должен уложиться в десятки секунд, а не в
минуты молчаливого `wget`.

## 8. Rollback

Вернуть VIP:

```bash
# восстановить cidr 192.168.215.9/32 и addresses.value
kubectl --context="$CTX" apply -f "$BACKUP_DIR/ippool.yaml"
kubectl --context="$CTX" apply -f "$BACKUP_DIR/gateway.yaml"
```

Вернуть hostname:

```bash
kubectl --context="$CTX" apply -f "$BACKUP_DIR/httproute.yaml"
helm --kube-context "$CTX" -n argocd rollback argocd <revision>
```

`<revision>` возьмите из `$BACKUP_DIR/argocd-helm-history.txt`. После
rollback снова проверьте `download-tools`: старый init снова ходит на
`dl.k8s.io`.

DNS и Keycloak откатываются отдельно.

## 9. Фактический результат 2026-08-17

| Проверка | Результат |
| --- | --- |
| `CiliumLoadBalancerIPPool/pool` | `192.168.215.18/32` |
| `Gateway cilium-gateway/ingress` | `192.168.215.18`, `PROGRAMMED=True` |
| `Service cilium-gateway-ingress` | `EXTERNAL-IP 192.168.215.18` |
| `http://192.168.215.18/` Host `hubble.test` | `200` |
| `https://192.168.215.18/` Host `argocd-dev.oro.moscow` | `200`, UI Argo CD |
| Старый VIP `192.168.215.9` | таймаут, ARP больше не анонсируется |
| Старый Host `argocd-talos-dev.oro.moscow` | `404` |
| `argocd-cm.url` | `https://argocd-dev.oro.moscow` |
| Helm Argo CD | chart `10.3.2`, revision 7 |
| `argocd-repo-server` после фикса init | `1/1 Running` за ~30 с |

Наблюдения:

- прямая замена пула и Gateway заняла секунды;
- первый `helm upgrade` (revision 6) сменил URL, но новый repo-server висел
  в `Init:1/2` около 8 минут на `dl.k8s.io`;
- после перехода init на Alpine/GitHub revision 7 поднялся без зависания.

## 10. Чеклист

- [ ] Проверен context `kubernetes-admin@k8s-dev`.
- [ ] `NEW_VIP` свободен в L2 `ens192`.
- [ ] Сохранены rollback-копии пула, Gateway, HTTPRoute и Helm history.
- [ ] Применены `ippool.yaml` и `cilium-gateway.yaml`.
- [ ] Gateway `PROGRAMMED`, Service слушает новый VIP.
- [ ] Применены HTTPRoute и `helm upgrade` Argo CD.
- [ ] Новый Host отвечает `200`, старый — `404`.
- [ ] `argocd-repo-server` не застрял в `Init`.
- [ ] DNS `argocd-dev.oro.moscow` указывает на `192.168.215.18`.
- [ ] В Keycloak обновлён redirect URI.
- [ ] В git нет секретов из `argocd/values.yaml`.
