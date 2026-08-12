# Push образа из containerd ноды в Nexus registry

Когда под на новом кластере (Talos) падает с `ErrImagePull` / `ImagePullBackOff`, а на старой ноде образ ещё есть в `containerd`, его можно заново запушить в Nexus.

Типичный случай: репозиторий в registry уже удалён/пропал, но локальный кэш на worker/control-plane старого кластера остался.

## Контекст окружения

| Что | Значение |
|-----|----------|
| Registry (Nexus) | `http://192.168.215.16:5000` |
| Runtime на k8s-ноде | `containerd` (не Docker как CRI) |
| Namespace образов k8s | `k8s.io` |
| Пример ноды со старым образом | `access-panel-k8s-develop` (`192.168.215.15`) |
| Пример образа | `192.168.215.16:5000/eva-sync:1e9aa8dd3bb29935041e67b8411539ed96abef25` |

## 1. Найти образ на ноде

```bash
ssh asvetlakov@192.168.215.15

sudo ctr -n k8s.io images ls | grep eva-sync
```

Ожидаем строку вида:

```text
192.168.215.16:5000/eva-sync:1e9aa8dd...  ... sha256:5e4f2a87...
```

## 2. Рекомендуемый способ: `ctr push` (без рестарта Docker)

Kubernetes на ноде использует **containerd**. Для пуша лучше `ctr`, а не `docker`:

- образ уже лежит в namespace `k8s.io`;
- есть флаг `--plain-http` для HTTP-registry;
- не нужно трогать Docker daemon.

```bash
IMG='192.168.215.16:5000/eva-sync:1e9aa8dd3bb29935041e67b8411539ed96abef25'

sudo ctr -n k8s.io images push --plain-http \
  -u 'admin:PASSWORD' \
  "$IMG"
```

### Разбор команды

| Часть | Смысл |
|-------|--------|
| `sudo` | Доступ к образам containerd k8s |
| `ctr` | CLI к containerd |
| `-n k8s.io` | Namespace, где лежат образы подов |
| `images push` | Отправить локальный образ в registry |
| `--plain-http` | HTTP без TLS (Nexus на `:5000` отвечает HTTP) |
| `-u 'USER:PASSWORD'` | Basic/auth для Nexus, иначе `401 Unauthorized` |
| `"$IMG"` | Полный ref: `registry/name:tag` |

## 3. Альтернатива: через Docker

Если хочется именно `docker push`, сначала нужен insecure registry: Docker по умолчанию идёт на HTTPS и падает с:

```text
http: server gave HTTP response to HTTPS client
```

### 3.1. Можно ли рестартить Docker на работающей k8s-ноде?

На ноде, где CRI = **containerd**, рестарт Docker **обычно не валит поды**.

Но:

- контейнеры, запущенные самим Docker/Compose, перезапустятся;
- кратковременно пропадёт docker-сокет.

Для пуша образа Docker лучше не трогать — используйте `ctr` из раздела 2.

### 3.2. Настройка insecure-registries (если всё же Docker)

Если файла ещё нет:

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "insecure-registries": ["192.168.215.16:5000"]
}
EOF

sudo systemctl restart docker
```file-storage-adm

Если `daemon.json` уже есть — **не затирайте**, только добавьте поле `insecure-registries`.

Логин и пуш:

```bash
IMG='192.168.215.16:5000/eva-sync:1e9aa8dd3bb29935041e67b8411539ed96abef25'
TMP=/tmp/eva-sync.tar

# экспорт из containerd -> docker
sudo ctr -n k8s.io images export "$TMP" "$IMG"
sudo docker load -i "$TMP"

echo 'PASSWORD' | docker login 192.168.215.16:5000 -u 'admin' --password-stdin
docker push "$IMG"
```

## 4. Проверка, что образ появился в Nexus

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "http://192.168.215.16:5000/v2/eva-sync/manifests/1e9aa8dd3bb29935041e67b8411539ed96abef25"
```

Ожидаем `200`.

Список тегов:

```bash
curl -s http://192.168.215.16:5000/v2/eva-sync/tags/list
```

## 5. Пересоздать под на Talos

```bash
kubectl --context=kubernetes-admin@k8s-dev -n mediascope delete pod -l app=eva-sync

kubectl --context=kubernetes-admin@k8s-dev -n mediascope get po -l app=eva-sync -w
```

## Типичные ошибки

| Ошибка | Причина | Что делать |
|--------|---------|------------|
| `401 Unauthorized` при `ctr push` | Нет/неверный `-u` | Передать `admin:PASSWORD` |
| `HTTP response to HTTPS client` | Docker без insecure-registries | Добавить insecure registry или использовать `ctr --plain-http` |
| `repository name not known` / `not found` при pull | Образа нет в Nexus | Запушить с ноды, где образ ещё в containerd |
| `ImagePullBackOff` на Talos | Образ не в registry | Шаги 2 → 4 → 5 |
