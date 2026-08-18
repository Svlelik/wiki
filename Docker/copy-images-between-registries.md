# Копирование container images между registry

Практическая инструкция по переносу container image из одного registry в
другой через Docker CLI, `crane`, `skopeo` и Podman.

Если Docker daemon не нужен и требуется сохранить multi-arch image, обычно
проще использовать `crane copy` или `skopeo copy --all`.

## Что копируется

Container image состоит не из одного файла:

- `layers` — слои файловой системы;
- `image config` — команда запуска, environment, architecture и metadata;
- `manifest` — ссылки на config и layers одной платформы;
- `manifest list` или OCI `index` — ссылки на manifests разных платформ;
- `tag` — изменяемое имя, указывающее на manifest или index;
- `digest` — хеш конкретного manifest/index, например `sha256:...`.

Упрощенная схема single-platform image:

```text
tag -> manifest -> image config
                -> layer 1
                -> layer 2
```

Multi-platform image:

```text
tag -> manifest list / OCI index
       |- linux/amd64 manifest -> config + layers
       |- linux/arm64 manifest -> config + layers
       `- linux/arm/v7 manifest -> config + layers
```

Копирование только одного platform-specific manifest не сохраняет исходный
multi-arch index.

Signatures, attestations, SBOM и другие OCI referrers могут храниться как
отдельные registry objects. Обычное копирование image graph не гарантирует их
перенос. Если они используются в policy, проверяйте и переносите их отдельным
инструментом для конкретного формата подписи/артефакта.

## Полный image reference

Пример:

```text
source.registry.example.com/team/app:1.2.3
```

Состав:

- `source.registry.example.com` — registry;
- `team` — namespace/project;
- `app` — repository/image name;
- `1.2.3` — tag.

Ссылка по digest:

```text
source.registry.example.com/team/app@sha256:0123456789abcdef...
```

Tag может быть перезаписан. Digest идентифицирует точные байты manifest или
index. Для воспроизводимого копирования сначала разрешите tag в digest, а
после операции убедитесь, что tag назначения указывает на ожидаемый объект.

## Какой инструмент выбрать

| Инструмент | Нужен daemon | Registry-to-registry | Multi-arch по умолчанию | HTTP registry |
| --- | --- | --- | --- | --- |
| Docker `pull/tag/push` | Да | Через локальное хранилище | Обычно нет, переносится выбранная платформа | Настройка daemon |
| `crane copy` | Нет | Да | Да, если не задан `--platform` | `--insecure` |
| `skopeo copy --all` | Нет | Да | Да только с `--all`/`--multi-arch=all` | `--*-tls-verify=false` |
| Podman `pull/tag/push` | Нет отдельного daemon | Через local storage | Обычно одна выбранная платформа | `--tls-verify=false`/config |

Практический выбор:

- простой single-platform перенос при уже запущенном Docker — Docker CLI;
- прямое точное копирование удаленного image — `crane`;
- сложные transports, отдельные auth files и явное управление multi-arch —
  `skopeo`;
- Podman уже является стандартным локальным runtime — Podman, а для прямого
  registry-to-registry удобнее `skopeo`.

## Переменные и preflight

Задайте ссылки один раз:

```bash
SOURCE_REGISTRY="source.registry.example.com"
TARGET_REGISTRY="target.registry.example.com"
SOURCE_IMAGE="${SOURCE_REGISTRY}/team/app:1.2.3"
TARGET_IMAGE="${TARGET_REGISTRY}/team/app:1.2.3"

printf 'source=%s\ntarget=%s\n' "$SOURCE_IMAGE" "$TARGET_IMAGE"
```

Проверьте, что:

- source tag существует;
- target reference содержит правильные registry, project и repository;
- учетная запись имеет pull на source и push на target;
- target registry поддерживает media types исходного image;
- для HTTP registry insecure-режим включается только точечно.

Read-only проверка source через `crane`:

```bash
crane digest "$SOURCE_IMAGE"
crane manifest "$SOURCE_IMAGE" | jq -r '.mediaType'
```

Сохраните digest до копирования:

```bash
SOURCE_DIGEST="$(crane digest "$SOURCE_IMAGE")"
printf 'source_digest=%s\n' "$SOURCE_DIGEST"
```

Опционально проверьте, существует ли target tag до изменения:

```bash
if TARGET_DIGEST_BEFORE="$(crane digest "$TARGET_IMAGE" 2>/dev/null)"; then
  printf 'target already exists: %s\n' "$TARGET_DIGEST_BEFORE"
else
  echo 'target tag is absent or unavailable'
fi
```

Отсутствующий tag до первой публикации — нормальное состояние.
`MANIFEST_UNKNOWN` не доказывает наличие push permission: право записи
проверяется только фактическим push/copy или средствами RBAC конкретного
registry.

Если source приватный, сначала выполните безопасный login.

## Авторизация без пароля в аргументах

Не передавайте password/token через `-p`, URL или `user:password` в команде.
Аргументы могут попасть в shell history, process list и CI log.

Отключите shell tracing:

```bash
set +x
```

Введите пароль без отображения:

```bash
read -r -s REGISTRY_PASSWORD
echo
export REGISTRY_PASSWORD
```

### Docker login

```bash
printf '%s' "$REGISTRY_PASSWORD" |
  docker login target.registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin
```

### Crane login

```bash
printf '%s' "$REGISTRY_PASSWORD" |
  crane auth login target.registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin
```

### Skopeo login в отдельный auth file

```bash
AUTH_DIR="$(mktemp -d)"
AUTH_FILE="$AUTH_DIR/auth.json"

printf '%s' "$REGISTRY_PASSWORD" |
  skopeo login target.registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin \
    --authfile "$AUTH_FILE"

chmod 600 "$AUTH_FILE"
```

Для Podman синтаксис аналогичен:

```bash
printf '%s' "$REGISTRY_PASSWORD" |
  podman login target.registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin \
    --authfile "$AUTH_FILE"
```

Docker, `crane` и инструменты containers ecosystem могут читать credentials
из Docker-compatible auth config. Это удобно, но содержимое
`~/.docker/config.json` или `auth.json` нельзя публиковать. Base64 внутри
auth-файла не является шифрованием.

После работы:

```bash
unset REGISTRY_PASSWORD
docker logout target.registry.example.com
crane auth logout target.registry.example.com
```

Для временного Skopeo/Podman auth file:

```bash
test -n "${AUTH_DIR:-}" && rm -rf -- "$AUTH_DIR"
unset AUTH_FILE AUTH_DIR
```

## Способ 1: Docker pull, tag и push

Требования:

- установлен Docker CLI;
- запущен Docker daemon;
- daemon имеет доступ к обоим registry;
- target HTTP registry добавлен в daemon insecure registries.

Проверьте daemon:

```bash
docker version
docker info
```

Безопасно авторизуйтесь:

```bash
printf '%s' "$SOURCE_REGISTRY_PASSWORD" |
  docker login "$SOURCE_REGISTRY" \
    --username "$SOURCE_REGISTRY_USER" \
    --password-stdin

printf '%s' "$TARGET_REGISTRY_PASSWORD" |
  docker login "$TARGET_REGISTRY" \
    --username "$TARGET_REGISTRY_USER" \
    --password-stdin
```

Копирование:

```bash
docker pull "$SOURCE_IMAGE"
docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
docker push "$TARGET_IMAGE"
```

Проверка локального image:

```bash
docker image inspect "$TARGET_IMAGE" \
  --format '{{json .RepoDigests}}'
```

Проверьте target независимо от локального daemon:

```bash
crane digest "$TARGET_IMAGE"
crane manifest "$TARGET_IMAGE" | jq -r '.mediaType'
```

### Ограничение Docker для multi-arch

Обычный `docker pull` выбирает подходящую платформу для текущего host, а
`docker tag` ставит новую ссылку на локальный image. Поэтому классическая
последовательность обычно отправляет один platform-specific manifest, а не
исходный manifest list/index.

Даже если современный containerd image store умеет хранить multi-platform
images, не считайте сохранение index гарантированным без проверки manifest и
платформ после push. Docker без `--platform` может отправить index, только если
полный multi-platform объект действительно присутствует в совместимом local
image store.

Явный single-platform push в современных Docker API также не сохраняет index:

```bash
docker pull --platform linux/amd64 "$SOURCE_IMAGE"
docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
docker push --platform linux/amd64 "$TARGET_IMAGE"
```

Для точного registry-to-registry переноса multi-arch используйте `crane copy`
или `skopeo copy --all`.

## Способ 2: crane copy

`crane` работает напрямую с registry и не требует Docker daemon.

Установка на macOS:

```bash
brew install crane
crane version
```

### Проверки до копирования

```bash
crane digest "$SOURCE_IMAGE"
crane manifest "$SOURCE_IMAGE" | jq -r '.mediaType'
```

Безопасный login в target:

```bash
printf '%s' "$TARGET_REGISTRY_PASSWORD" |
  crane auth login "$TARGET_REGISTRY" \
    --username "$TARGET_REGISTRY_USER" \
    --password-stdin
```

Если source приватный, отдельно выполните login в `$SOURCE_REGISTRY`.

### Копирование всех платформ

```bash
crane copy "$SOURCE_IMAGE" "$TARGET_IMAGE"
```

В `crane 0.21.9` global `--platform` по умолчанию имеет значение `all`.
`crane copy` копирует index, связанные manifests/configs/layers и стремится
сохранить digest удаленного объекта.

Проверка:

```bash
SOURCE_DIGEST="$(crane digest "$SOURCE_IMAGE")"
TARGET_DIGEST="$(crane digest "$TARGET_IMAGE")"

printf 'source=%s\ntarget=%s\n' "$SOURCE_DIGEST" "$TARGET_DIGEST"
test "$SOURCE_DIGEST" = "$TARGET_DIGEST"
```

Если `test` завершился с кодом `0`, manifest/index digest совпал.

### Копирование одной платформы

```bash
crane copy \
  --platform linux/amd64 \
  "$SOURCE_IMAGE" \
  "$TARGET_IMAGE"
```

Target теперь является single-platform image. Его digest закономерно
отличается от digest исходного multi-arch index.

Проверьте config выбранной платформы:

```bash
crane config "$TARGET_IMAGE" |
  jq -r '[.os, .architecture, (.variant // "")] | @tsv'
```

### HTTP registry

```bash
crane copy \
  --insecure \
  "$SOURCE_IMAGE" \
  "registry.example.com:5000/team/app:1.2.3"
```

Для login в HTTP registry:

```bash
printf '%s' "$TARGET_REGISTRY_PASSWORD" |
  crane auth login registry.example.com:5000 \
    --username "$TARGET_REGISTRY_USER" \
    --password-stdin \
    --insecure
```

У `crane` `--insecure` — global flag операции, а не отдельная настройка только
destination. Он разрешает работу без нормальной TLS-защиты. Используйте его
только в доверенной изолированной сети, когда registry действительно работает
по HTTP или временно использует непроверяемый TLS.

## Способ 3: skopeo copy

`skopeo` работает без daemon и поддерживает несколько transports. Для remote
Docker Registry используется prefix `docker://`.

Установка:

```bash
brew install skopeo
skopeo --version
```

### Read-only inspect

```bash
skopeo inspect "docker://${SOURCE_IMAGE}"
skopeo inspect --raw "docker://${SOURCE_IMAGE}" |
  jq -r '.mediaType'
```

### Авторизация через auth file

```bash
AUTH_DIR="$(mktemp -d)"
AUTH_FILE="$AUTH_DIR/auth.json"

printf '%s' "$TARGET_REGISTRY_PASSWORD" |
  skopeo login "$TARGET_REGISTRY" \
    --username "$TARGET_REGISTRY_USER" \
    --password-stdin \
    --authfile "$AUTH_FILE"

chmod 600 "$AUTH_FILE"
```

Если оба registry приватные, запишите обе авторизации в один временный auth
file или используйте разные `--src-authfile` и `--dest-authfile`.

### Копирование всех платформ

```bash
skopeo copy --all \
  --authfile "$AUTH_FILE" \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

Без `--all` Skopeo по умолчанию выбирает image для OS/architecture текущей
машины.

Строгий вариант:

```bash
skopeo copy --all \
  --preserve-digests \
  --authfile "$AUTH_FILE" \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

`--preserve-digests` требует сохранить исходные digests и завершает операцию
ошибкой, если destination transport/registry требует преобразования. Это
полезная проверка, но не универсальный обязательный флаг.

### Копирование только linux/amd64

```bash
skopeo --override-os linux --override-arch amd64 copy \
  --authfile "$AUTH_FILE" \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

В новых версиях Skopeo также доступно управление через `--multi-arch`, но
`--all` остается понятным и широко совместимым вариантом полного копирования.

### HTTP registry

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  --authfile "$AUTH_FILE" \
  "docker://${SOURCE_IMAGE}" \
  "docker://registry.example.com:5000/team/app:1.2.3"
```

Если source также insecure:

```bash
skopeo copy --all \
  --src-tls-verify=false \
  --dest-tls-verify=false \
  --authfile "$AUTH_FILE" \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

Флаги `--src-creds username[:password]` и
`--dest-creds username[:password]` существуют, но password в аргументе может
попасть в process list и CI log. Предпочитайте `skopeo login
--password-stdin` и `--src-authfile`/`--dest-authfile`.

## Способ 4: Podman

Podman не требует постоянного daemon, но `pull/tag/push` использует локальное
image storage:

```bash
podman pull "$SOURCE_IMAGE"
podman tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
podman push "$TARGET_IMAGE"
```

Как и классический Docker workflow, этот путь обычно работает с выбранной
платформой. Для multi-arch в Podman используется manifest workflow:

```bash
LOCAL_MANIFEST="$TARGET_IMAGE"

podman manifest create --all \
  "$LOCAL_MANIFEST" \
  "docker://${SOURCE_IMAGE}"

podman manifest inspect "$LOCAL_MANIFEST"
podman manifest push --all \
  "$LOCAL_MANIFEST" \
  "docker://${TARGET_IMAGE}"
```

`manifest create --all` формирует local manifest list из remote source.
`manifest push --all` отправляет list и связанные images. Podman может
пересобрать или преобразовать index, в том числе в OCI format, поэтому
top-level digest source и target не обязан совпасть. Для прямого копирования
с требованием сохранить digest удобнее `crane copy` или
`skopeo copy --all --preserve-digests`.

HTTP destination:

```bash
podman push \
  --tls-verify=false \
  "$SOURCE_IMAGE" \
  "docker://registry.example.com:5000/team/app:1.2.3"
```

Для постоянной настройки registry в containers ecosystem используйте
`registries.conf` и custom CA вместо повторного отключения TLS verification.

## Проверка multi-arch manifest

Получите raw manifest:

```bash
crane manifest "$TARGET_IMAGE" |
  jq -r '.mediaType'
```

Выведите платформы:

```bash
crane manifest "$TARGET_IMAGE" |
  jq -r '
    .manifests[]?.platform |
    [.os, .architecture, (.variant // "")] |
    @tsv
  '
```

Если `.manifests` отсутствует, target является single-platform manifest.

Через Skopeo:

```bash
skopeo inspect --raw "docker://${TARGET_IMAGE}" |
  jq -r '
    .manifests[]?.platform |
    [.os, .architecture, (.variant // "")] |
    @tsv
  '
```

Проверяйте платформы как до, так и после копирования:

```bash
for IMAGE in "$SOURCE_IMAGE" "$TARGET_IMAGE"; do
  echo "=== $IMAGE ==="
  crane manifest "$IMAGE" |
    jq -r '
      .manifests[]?.platform |
      [.os, .architecture, (.variant // "")] |
      @tsv
    '
done
```

## Как интерпретировать digest

Сравнение:

```bash
crane digest "$SOURCE_IMAGE"
crane digest "$TARGET_IMAGE"
```

Одинаковый digest manifest list/index означает, что его байты идентичны. Это
сильная проверка полного multi-arch копирования.

Digest может различаться, если:

- скопирована только одна платформа;
- registry или инструмент преобразовал Docker Schema 2 в OCI или обратно;
- изменились annotations;
- target tag перезаписал параллельный процесс;
- копировался другой source tag/digest.

Одинаковый набор платформ при разном digest не доказывает идентичность
manifest. И наоборот, совпадение имени tag ничего не говорит о содержимом.

Если необходима строгая воспроизводимость, копируйте source по digest:

```bash
SOURCE_DIGEST="$(crane digest "$SOURCE_IMAGE")"
SOURCE_PINNED="${SOURCE_IMAGE%:*}@${SOURCE_DIGEST}"

crane copy "$SOURCE_PINNED" "$TARGET_IMAGE"
```

Форма `${SOURCE_IMAGE%:*}` подходит для reference с tag и registry port не в
последнем path segment. Для универсального automation лучше разбирать image
reference специализированной библиотекой, а не shell-операциями.

## HTTPS, custom CA и HTTP

Предпочтительный вариант — HTTPS с сертификатом от доверенного CA.

Для private CA добавьте CA certificate в доверенное хранилище конкретного
инструмента/daemon:

- Docker Engine: `/etc/docker/certs.d/<registry-host>:<port>/ca.crt`;
- Skopeo/Podman:
  `$HOME/.config/containers/certs.d/<registry-host>:<port>/ca.crt` или
  `/etc/containers/certs.d/<registry-host>:<port>/ca.crt`, а также
  `--src-cert-dir`/`--dest-cert-dir`;
- `crane`: системное trust store процесса.

После добавления CA оставьте TLS verification включенным.

Ошибка:

```text
http: server gave HTTP response to HTTPS client
```

означает, что client начал HTTPS handshake, а endpoint ответил обычным HTTP.
Это не ошибка credentials.

Решения:

1. Предпочтительно включить TLS на registry.
2. Для временного HTTP registry включить insecure только для конкретного
   host/операции.
3. Не отключать TLS verification глобально.

Docker CLI не имеет универсального `docker push --insecure`. HTTP registry
настраивается в Docker daemon:

```json
{
  "insecure-registries": ["registry.example.com:5000"]
}
```

После изменения Linux Docker Engine требуется restart daemon. Подробности —
в [материале по Docker registry](registry.md#insecure-registry).

## Практический пример: kube-webhook-certgen в Nexus

Исходник:

```bash
SOURCE_IMAGE="registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6"
TARGET_REGISTRY="192.168.215.16:5000"
TARGET_IMAGE="${TARGET_REGISTRY}/infractructure/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6"
```

Публичный source manifest проверен с `crane 0.21.9`:

```text
mediaType: application/vnd.docker.distribution.manifest.list.v2+json
digest: sha256:4d99688e557396f5baa150e019ff7d5b7334f9b9f9a8dab64038c5c2a006f6b5
platforms:
  linux/amd64
  linux/arm/v7
  linux/arm64
  linux/s390x
```

Read-only проверка source:

```bash
crane digest "$SOURCE_IMAGE"
crane manifest "$SOURCE_IMAGE" |
  jq -r '
    .manifests[].platform |
    [.os, .architecture, (.variant // "")] |
    @tsv
  '
```

Nexus работает по HTTP. Безопасный login без публикации credentials:

```bash
set +x

printf '%s' "$NEXUS_PASSWORD" |
  crane auth login "$TARGET_REGISTRY" \
    --username "$NEXUS_USER" \
    --password-stdin \
    --insecure
```

Прямое multi-arch копирование без Docker daemon:

```bash
crane copy \
  --insecure \
  "$SOURCE_IMAGE" \
  "$TARGET_IMAGE"
```

Проверка target также требует `--insecure`:

```bash
SOURCE_DIGEST="$(crane digest "$SOURCE_IMAGE")"
TARGET_DIGEST="$(crane digest --insecure "$TARGET_IMAGE")"

printf 'source=%s\ntarget=%s\n' "$SOURCE_DIGEST" "$TARGET_DIGEST"
test "$SOURCE_DIGEST" = "$TARGET_DIGEST"

crane manifest --insecure "$TARGET_IMAGE" |
  jq -r '
    .manifests[].platform |
    [.os, .architecture, (.variant // "")] |
    @tsv
  '
```

В выполненной операции source и target index digest совпали, а target
содержал все четыре платформы.

Logout:

```bash
crane auth logout "$TARGET_REGISTRY"
unset NEXUS_PASSWORD
```

## Проверка фактического pull

Через Docker:

```bash
docker pull "$TARGET_IMAGE"
```

Для конкретной платформы:

```bash
docker pull --platform linux/amd64 "$TARGET_IMAGE"
```

На Kubernetes node с containerd:

```bash
sudo crictl pull "$TARGET_IMAGE"
```

`crictl pull` изменяет локальный image cache ноды и может скачать большой
объем данных. На production node выполняйте его только осознанно. Для HTTP
registry containerd должен иметь отдельную корректную registry-конфигурацию;
настройка `crane --insecure` на рабочей станции на node не распространяется.

После pull проверьте image:

```bash
sudo crictl images |
  grep 'kube-webhook-certgen'
```

## Типовые ошибки

### UNAUTHORIZED

```text
UNAUTHORIZED: access to the requested resource is not authorized
```

Проверьте:

- выполнен ли login для точного hostname и port;
- не сохранены ли credentials для другого alias;
- есть ли pull permission на source;
- есть ли push/create repository permission на target;
- не истек ли token;
- читает ли инструмент ожидаемый auth file.

Повторите login через `--password-stdin`, затем read-only inspect source и
повторную copy.

### HTTP response to HTTPS client

```text
http: server gave HTTP response to HTTPS client
```

Client ожидает HTTPS, registry отвечает HTTP. Используйте TLS или точечный
insecure flag/config. Авторизация сама по себе эту ошибку не исправляет.

`docker buildx imagetools create` тоже обращается к registry напрямую и
формирует новый manifest list из remote manifests, которые уже должны
существовать в registry назначения. Для HTTP registry ему нужна
соответствующая insecure-конфигурация BuildKit; один только login не устраняет
protocol mismatch. Это не универсальная замена полного registry-to-registry
переноса blobs. Для разовой копии в таком окружении проще использовать
`crane --insecure` или `skopeo --dest-tls-verify=false`.

### MANIFEST_UNKNOWN

```text
MANIFEST_UNKNOWN
```

Проверьте:

- точный tag и digest;
- repository path и регистр символов;
- правильный registry hostname/port;
- опубликован ли manifest;
- не является ли registry proxy/cache, который еще не получил image;
- поддерживает ли destination media type/index.

### Digest source и target различается

Проверьте:

1. Копировался ли весь index.
2. Не использовался ли `--platform`.
3. Был ли у Skopeo указан `--all`.
4. Не преобразован ли media type.
5. Не перезаписан ли target tag.
6. Совпадает ли список платформ.

### Digest совпал, но pull не работает

Возможные причины:

- node не доверяет CA;
- containerd не настроен на HTTP registry;
- Kubernetes imagePullSecret отсутствует;
- registry недоступен из сети node;
- у runtime нет pull permission.

Registry copy и runtime pull проверяют разные пути доступа.

## CI/CD

Используйте short-lived token или service account с минимальными правами.
Отключите shell tracing и создавайте временный auth directory:

```bash
set +x
export DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT

printf '%s' "$TARGET_REGISTRY_TOKEN" |
  crane auth login "$TARGET_REGISTRY" \
    --username "$TARGET_REGISTRY_USER" \
    --password-stdin

crane copy "$SOURCE_IMAGE" "$TARGET_IMAGE"

SOURCE_DIGEST="$(crane digest "$SOURCE_IMAGE")"
TARGET_DIGEST="$(crane digest "$TARGET_IMAGE")"
test "$SOURCE_DIGEST" = "$TARGET_DIGEST"
```

Требования к pipeline:

- mask secret variables;
- не включать `set -x`;
- не печатать auth files;
- использовать immutable source digest;
- проверять digest/platforms после copy;
- не запускать две публикации одного target tag параллельно;
- удалять временный auth directory;
- хранить в artifact только digest и безопасный отчет, не credentials.

### Безопасный шаблон с SOPS

Не печатайте расшифрованный файл целиком:

```bash
set +x

REGISTRY_USER="$(
  sops --decrypt credentials.sops.json |
    jq -r '.registry.login'
)"

sops --decrypt credentials.sops.json |
  jq -r '.registry.password' |
  crane auth login registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin

unset REGISTRY_USER
```

В production CI предпочтительнее secret manager integration, которая выдает
short-lived token непосредственно job.

## Готовые шаблоны

Multi-arch через Crane:

```bash
crane copy "$SOURCE_IMAGE" "$TARGET_IMAGE"
test \
  "$(crane digest "$SOURCE_IMAGE")" = \
  "$(crane digest "$TARGET_IMAGE")"
```

Одна платформа через Crane:

```bash
crane copy \
  --platform linux/amd64 \
  "$SOURCE_IMAGE" \
  "$TARGET_IMAGE"
```

Multi-arch через Skopeo:

```bash
skopeo copy --all \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

HTTP target через Skopeo:

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}"
```

Single-platform через Docker:

```bash
docker pull "$SOURCE_IMAGE"
docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
docker push "$TARGET_IMAGE"
```

## Официальная документация

- [Docker login](https://docs.docker.com/reference/cli/docker/login/)
- [Docker pull](https://docs.docker.com/reference/cli/docker/image/pull/)
- [Docker push](https://docs.docker.com/reference/cli/docker/image/push/)
- [Docker multi-platform images](https://docs.docker.com/build/building/multi-platform/)
- [Docker manifest](https://docs.docker.com/reference/cli/docker/manifest/)
- [Docker registry certificates](https://docs.docker.com/engine/security/certificates/)
- [Docker insecure registries](https://docs.docker.com/reference/cli/dockerd/#insecure-registries)
- [Docker imagetools create](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/)
- [Crane commands](https://github.com/google/go-containerregistry/tree/main/cmd/crane/doc)
- [Crane recipes](https://github.com/google/go-containerregistry/blob/main/cmd/crane/recipes.md)
- [Skopeo copy](https://github.com/containers/skopeo/blob/main/docs/skopeo-copy.1.md)
- [Skopeo login](https://github.com/containers/skopeo/blob/main/docs/skopeo-login.1.md)
- [Podman login](https://docs.podman.io/en/stable/markdown/podman-login.1.html)
- [Podman push](https://docs.podman.io/en/stable/markdown/podman-push.1.html)
- [Podman manifest create](https://docs.podman.io/en/stable/markdown/podman-manifest-create.1.html)
- [Podman manifest push](https://docs.podman.io/en/stable/markdown/podman-manifest-push.1.html)
- [Containers certs.d](https://github.com/containers/image/blob/main/docs/containers-certs.d.5.md)
- [Containers registries.conf](https://github.com/containers/image/blob/main/docs/containers-registries.conf.5.md)
