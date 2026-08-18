# TASK_019

## Заголовок

Практическая инструкция по копированию container images между registry

## Статус

`done`

## Кратко

Нужно подготовить подробную русскоязычную инструкцию в разделе `Docker` по копированию container images между публичными и приватными registry разными способами: через Docker CLI, `crane`, `skopeo` и при необходимости Podman.

Материал должен объяснять разницу между обычным `pull/tag/push` через локальный daemon и прямым копированием registry-to-registry без запуска Docker daemon. Особое внимание нужно уделить сохранению multi-arch manifest, проверке digest, авторизации, HTTP/insecure registry и безопасной работе с паролями.

## Контекст

При обновлении `kube-prometheus-stack` admission hook использовал внешний образ:

```text
registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6
```

Остальные образы чарта загружались из внутреннего Nexus registry. Для исключения зависимости от внешнего registry образ потребовалось скопировать в:

```text
192.168.215.16:5000/infractructure/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6
```

Docker daemon на рабочей станции не был запущен, поэтому способ через `docker pull`, `docker tag`, `docker push` использовать было неудобно. Для прямого копирования был применён `crane`.

Первая попытка через `docker buildx imagetools create` завершилась ошибкой:

```text
http: server gave HTTP response to HTTPS client
```

Внутренний Nexus Docker registry работает по HTTP, поэтому инструменту нужно явно разрешить insecure-соединение.

Попытка `crane copy --insecure` без авторизации завершилась:

```text
UNAUTHORIZED: access to the requested resource is not authorized
```

После безопасной авторизации через `crane auth login --password-stdin` multi-arch image был успешно скопирован. Digest исходного и целевого manifest совпал.

## Цель

Создать руководство, по которому инженер сможет:

- выбрать подходящий способ копирования image между registry;
- скопировать image через Docker CLI;
- выполнить прямое registry-to-registry копирование через `crane`;
- скопировать image через `skopeo copy`;
- понять, когда можно использовать Podman;
- сохранить все платформы multi-arch image;
- скопировать только выбранную платформу, если это требуется;
- авторизоваться без передачи пароля в аргументах команд и shell history;
- работать с HTTPS registry и осознанно использовать HTTP/insecure registry;
- проверить digest, manifest и список платформ после копирования;
- диагностировать `UNAUTHORIZED`, `MANIFEST_UNKNOWN` и ошибки TLS/HTTP;
- безопасно использовать команды в локальной среде и CI/CD.

## Объем

- Создать материал `Docker/copy-images-between-registries.md`.
- Добавить ссылку на материал в индекс раздела `Docker`, если индекс существует.
- Добавить ссылку из `Docker/registry.md` или расширить существующую страницу краткой ссылкой на новую инструкцию.
- Рассмотреть Docker CLI, `crane`, `skopeo` и Podman.
- Для каждого способа описать требования, ограничения и влияние на multi-arch manifest.
- Использовать нейтральные адреса `source.registry.example.com` и `target.registry.example.com` в основных примерах.
- Реальный Nexus `192.168.215.16:5000` использовать только в отдельном практическом примере без логинов и паролей.
- Показать read-only проверки до и после копирования.
- Обновить `TASK.md` и `LOG.md` при фактическом выполнении задачи.

## Вне объема

- Установка и администрирование Nexus, Harbor, GitLab Registry или Docker Registry.
- Настройка RBAC и создание пользователей в registry.
- Публикация реальных паролей, token, содержимого `~/.docker/config.json` или расшифрованных SOPS-файлов.
- Настройка production TLS и выпуск сертификатов.
- Сборка application image и написание Dockerfile, кроме краткого контекста.
- Массовая миграция всех repositories и tags между registry.
- Удаление images, manifests, tags или blobs из registry.

## Предварительные требования

- Доступ к source registry на чтение.
- Доступ к target registry с правом push.
- Известны полные source и target image references.
- Установлен хотя бы один подходящий инструмент: Docker, `crane`, `skopeo` или Podman.
- Для HTTP registry осознанно настроен insecure-режим.
- Для приватных registry подготовлен token или service account.

## Предлагаемые файлы

- `Docker/copy-images-between-registries.md` — основная инструкция.
- `Docker/registry.md` — ссылка на подробную инструкцию.
- `Docker/README.md` или другой индекс раздела — ссылка на материал, если файл существует.
- `TASK.md` — состояние задачи при выполнении.
- `LOG.md` — записи начала и завершения работы.

## Предлагаемая структура материала

1. Что именно копируется: image config, layers, manifest, manifest list/index и tags.
2. Полный image reference: registry, repository, image, tag и digest.
3. Выбор инструмента: сравнительная таблица Docker, `crane`, `skopeo` и Podman.
4. Предварительная проверка source image и доступа к target registry.
5. Авторизация и безопасная передача пароля через stdin.
6. Способ 1: `docker pull`, `docker tag`, `docker push`.
7. Ограничения обычного Docker-подхода для multi-arch images.
8. Способ 2: прямое копирование через `crane copy`.
9. Установка `crane` и работа без Docker daemon.
10. Проверка через `crane digest`, `crane manifest` и `crane config`.
11. Способ 3: `skopeo copy` с `--all`.
12. Способ 4: Podman pull/tag/push или `skopeo` из экосистемы containers.
13. Копирование одной платформы и сохранение всех платформ.
14. HTTPS, custom CA и HTTP/insecure registry.
15. Проверка результата на машине или Kubernetes node.
16. Типовые ошибки и порядок диагностики.
17. Использование в CI/CD.
18. Краткая таблица выбора инструмента и готовые шаблоны команд.

## Обязательные примеры

### Docker CLI

Показать классический вариант, требующий запущенного Docker daemon:

```bash
SOURCE_IMAGE="source.registry.example.com/team/app:1.2.3"
TARGET_IMAGE="target.registry.example.com/team/app:1.2.3"

docker login source.registry.example.com
docker login target.registry.example.com

docker pull "$SOURCE_IMAGE"
docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"
docker push "$TARGET_IMAGE"
```

Объяснить, что такой способ обычно работает с платформой текущей машины и может не сохранить исходный multi-arch manifest list.

### Crane

Показать установку:

```bash
brew install crane
```

Показать безопасную авторизацию:

```bash
printf '%s' "$REGISTRY_PASSWORD" |
  crane auth login target.registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin
```

Показать прямое копирование без Docker daemon:

```bash
crane copy \
  source.registry.example.com/team/app:1.2.3 \
  target.registry.example.com/team/app:1.2.3
```

Для HTTP registry показать:

```bash
crane copy --insecure \
  source.registry.example.com/team/app:1.2.3 \
  registry.example.com:5000/team/app:1.2.3
```

Обязательно пояснить, что `--insecure` снижает безопасность и должен применяться только для доверенной сети или временной инфраструктуры, где TLS действительно отсутствует.

### Skopeo

Показать прямое копирование всех платформ:

```bash
skopeo copy --all \
  docker://source.registry.example.com/team/app:1.2.3 \
  docker://target.registry.example.com/team/app:1.2.3
```

Показать вариант для HTTP registry:

```bash
skopeo copy --all \
  --dest-tls-verify=false \
  docker://source.registry.example.com/team/app:1.2.3 \
  docker://registry.example.com:5000/team/app:1.2.3
```

Отдельно описать `--src-creds`, `--dest-creds` и более безопасные auth files, не вставляя реальные пароли в документацию.

### Проверка digest

Показать сравнение:

```bash
crane digest "$SOURCE_IMAGE"
crane digest "$TARGET_IMAGE"
```

Объяснить:

- одинаковый digest manifest list подтверждает идентичность multi-arch index;
- при копировании одной платформы digest target manifest может отличаться;
- совпадение tag само по себе ничего не гарантирует;
- digest нужно проверять после завершения push/copy.

### Проверка платформ

Показать:

```bash
crane manifest "$TARGET_IMAGE" |
  jq -r '.manifests[].platform |
    [.os, .architecture, (.variant // "")] |
    @tsv'
```

Для примера `kube-webhook-certgen` ожидаются платформы:

```text
linux/amd64
linux/arm/v7
linux/arm64
linux/s390x
```

### Проверка скачивания

Показать проверку через Docker:

```bash
docker pull "$TARGET_IMAGE"
```

Для Kubernetes node с containerd:

```bash
sudo crictl pull "$TARGET_IMAGE"
```

Отметить, что выполнение `crictl pull` изменяет локальный image cache ноды. На production node такую проверку выполняют осознанно и только при наличии доступа.

## Авторизация и секреты

В инструкции обязательно:

- использовать `--password-stdin`;
- не показывать пароль в `-p`, URL, shell history или process list;
- не печатать расшифрованный SOPS-файл в терминал или лог CI;
- не публиковать содержимое `~/.docker/config.json`;
- рекомендовать short-lived token или service account для CI;
- объяснить, что Docker-compatible инструменты могут использовать credentials из `~/.docker/config.json`;
- показать logout после разовой операции:

```bash
docker logout target.registry.example.com
```

или:

```bash
crane auth logout target.registry.example.com
```

Для SOPS привести только безопасный шаблон без реальных путей и значений:

```bash
REGISTRY_USER="$(sops --decrypt credentials.sops.json | jq -r '.registry.login')"

sops --decrypt credentials.sops.json |
  jq -r '.registry.password' |
  crane auth login registry.example.com \
    --username "$REGISTRY_USER" \
    --password-stdin
```

Указать, что shell tracing (`set -x`) при работе с секретами должен быть выключен.

## Multi-arch особенности

Нужно отдельно объяснить:

- разницу между platform-specific manifest и manifest list/OCI index;
- почему локальный `docker pull/tag/push` может перенести только одну архитектуру;
- что `crane copy` по умолчанию сохраняет index и связанные manifests;
- что для `skopeo copy` при multi-arch переносе нужен `--all`;
- как проверить список платформ до и после;
- почему нельзя считать операцию успешной только по наличию target tag;
- когда допустимо сознательно копировать только `linux/amd64`.

## Типовые ошибки

Разобрать минимум:

### `UNAUTHORIZED`

Причины:

- отсутствует login;
- credentials сохранены для другого hostname или порта;
- пользователь имеет pull, но не push;
- нет права создавать repository или загружать blobs.

### `server gave HTTP response to HTTPS client`

Причина: инструмент ожидает HTTPS, а registry слушает HTTP.

Решения:

- предпочтительно включить TLS;
- для доверенного HTTP registry явно использовать `--insecure`, `--dest-tls-verify=false` или настройку Docker daemon;
- не отключать TLS verification глобально без необходимости.

### `MANIFEST_UNKNOWN` или `manifest unknown`

Причины:

- неправильный tag;
- неправильный repository;
- manifest ещё не опубликован;
- registry proxy/cache не содержит нужного image.

### Digest исходника и копии различается

Проверить:

- копировался ли весь multi-arch index;
- не была ли выбрана одна платформа;
- не изменился ли media type Docker Schema 2/OCI;
- не был ли target tag перезаписан параллельным процессом.

## Требования к стилю

- Писать по-русски простым инженерным языком.
- Все команды должны быть копируемыми и использовать переменные для длинных image references.
- Перед изменяющими командами показывать read-only проверку.
- После каждого способа давать проверку результата.
- Явно отмечать, нужен ли Docker daemon.
- Явно отмечать, сохраняется ли multi-arch image.
- Не использовать реальные credentials.
- Не рекомендовать insecure registry как нормальный production-вариант.
- Для актуальных флагов свериться со встроенной справкой и официальной документацией инструментов.

## Критерии готовности

- [x] Создан `Docker/copy-images-between-registries.md`.
- [x] Объяснены layers, manifests, manifest lists/indexes, tags и digests.
- [x] Добавлен способ через Docker CLI.
- [x] Добавлен способ через `crane`.
- [x] Добавлен способ через `skopeo`.
- [x] Описан вариант с Podman.
- [x] Есть сравнительная таблица инструментов.
- [x] Объяснена работа без Docker daemon.
- [x] Подробно разобрано сохранение multi-arch images.
- [x] Добавлены безопасные примеры авторизации через stdin.
- [x] Разобраны HTTPS, custom CA и HTTP/insecure registry.
- [x] Добавлены проверки digest и списка платформ.
- [x] Добавлена проверка фактического pull.
- [x] Разобраны `UNAUTHORIZED`, HTTP/HTTPS и manifest errors.
- [x] В материале отсутствуют реальные логины, пароли и tokens.
- [x] Обновлены ссылки в разделе `Docker`.
- [x] `TASK.md` и `LOG.md` обновлены при выполнении.

## Вопросы

- Создан `Docker/README.md`, так как индекс раздела отсутствовал.
- `docker buildx imagetools create` не включен как основной способ: он предназначен прежде всего для формирования/публикации manifest list, а для прямого копирования, особенно в HTTP registry, менее удобен, чем `crane` или `skopeo`.
- Поведение и флаги сверены со встроенной справкой `crane 0.21.9` и официальной документацией Docker, Crane, Skopeo и Podman. Публичный source manifest проверен read-only; push в registry не выполнялся.

## Блокеры

- Нет.

## Последнее состояние

Создан `Docker/copy-images-between-registries.md` с подробным сравнением Docker CLI, `crane`, `skopeo` и Podman, безопасной авторизацией, multi-arch сценариями, digest/platform проверками, HTTP/custom CA, диагностикой и CI/CD шаблонами. Создан индекс `Docker/README.md`, а `Docker/registry.md` дополнен ссылкой. Задача завершена без push в registry.

## Связанные записи лога

- `LOG.md`: 2026-08-18 11:05 - TASK_019 - in_progress
- `LOG.md`: 2026-08-18 11:05 - TASK_019 - done
