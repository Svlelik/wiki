# Docker registry

Docker registry - это хранилище Docker images. Из registry образы скачивают командой `docker pull`, а загружают командой `docker push`.

Самый известный публичный registry - Docker Hub. Также часто используют приватные registry: GitLab Container Registry, GitHub Container Registry, Harbor, Nexus, Artifactory, Amazon ECR, Google Artifact Registry и другие.

Подробное прямое копирование images между registry через Docker CLI, `crane`,
`skopeo` и Podman описано в
[отдельной инструкции](copy-images-between-registries.md).

## Registry, repository, image и tag

В имени образа обычно есть несколько частей:

```text
registry/repository/image:tag
```

Примеры:

```text
nginx:latest
postgres:16
docker.io/library/nginx:latest
ghcr.io/company/app:1.0.0
registry.example.com/backend/api:2026-04-29
```

Что означает каждая часть:

- `registry` - адрес хранилища образов, например `docker.io`, `ghcr.io`, `registry.example.com`;
- `repository` - namespace, project или группа внутри registry;
- `image` - имя образа;
- `tag` - версия или метка образа.

Если registry не указан, Docker по умолчанию использует Docker Hub. Поэтому команды ниже эквивалентны:

```bash
docker pull nginx:latest
docker pull docker.io/library/nginx:latest
```

Важно: `latest` - это не обязательно самая свежая версия. Это обычный tag, который владелец образа может обновлять как угодно.

## Скачать образ из registry

Скачать образ:

```bash
docker pull nginx:latest
```

Скачать конкретную версию:

```bash
docker pull postgres:16
```

Скачать образ из приватного registry:

```bash
docker pull registry.example.com/backend/api:1.0.0
```

Посмотреть локальные образы:

```bash
docker images
```

или:

```bash
docker image ls
```

## Авторизация в registry

Войти в Docker Hub:

```bash
docker login
```

Войти в конкретный registry:

```bash
docker login registry.example.com
```

После этого Docker сохранит данные авторизации в конфиге клиента:

```text
~/.docker/config.json
```

Выйти из registry:

```bash
docker logout registry.example.com
```

Для Docker Hub:

```bash
docker logout
```

Для CI/CD лучше использовать token или service account, а не личный пароль пользователя.

## Собрать образ и подготовить к push

Собрать образ локально:

```bash
docker build -t my-app:latest .
```

Такой образ называется `my-app:latest` и пока существует только локально.

Чтобы отправить образ в registry, его имя должно содержать адрес registry и путь к repository.

Переименовать образ через tag:

```bash
docker tag my-app:latest registry.example.com/backend/my-app:1.0.0
```

Теперь локально есть две ссылки на один и тот же image:

```bash
docker images
```

## Отправить образ в registry

Залогиниться:

```bash
docker login registry.example.com
```

Отправить образ:

```bash
docker push registry.example.com/backend/my-app:1.0.0
```

После этого образ можно скачать на другой машине:

```bash
docker pull registry.example.com/backend/my-app:1.0.0
```

и запустить контейнер:

```bash
docker run -d --name my-app registry.example.com/backend/my-app:1.0.0
```

## Работа с несколькими tag

Один и тот же image можно пометить несколькими tag.

Например, для релиза:

```bash
docker tag my-app:latest registry.example.com/backend/my-app:1.0.0
docker tag my-app:latest registry.example.com/backend/my-app:stable
```

Отправить оба tag:

```bash
docker push registry.example.com/backend/my-app:1.0.0
docker push registry.example.com/backend/my-app:stable
```

Для production лучше использовать конкретные версии или digest, а не только `latest` или `stable`.

## Pull по digest

Tag может быть перезаписан. Digest указывает на конкретное содержимое образа.

Пример:

```text
registry.example.com/backend/my-app@sha256:...
```

Скачать образ по digest:

```bash
docker pull registry.example.com/backend/my-app@sha256:abc123
```

Digest удобно использовать там, где нужна воспроизводимость: production, Kubernetes manifests, GitOps.

## Приватный registry на localhost

Для локальных тестов можно запустить официальный registry как контейнер:

```bash
docker run -d \
  --name registry \
  -p 5000:5000 \
  registry:2
```

Собрать образ:

```bash
docker build -t my-app:latest .
```

Поставить tag для локального registry:

```bash
docker tag my-app:latest localhost:5000/my-app:1.0.0
```

Отправить образ:

```bash
docker push localhost:5000/my-app:1.0.0
```

Скачать образ:

```bash
docker pull localhost:5000/my-app:1.0.0
```

Остановить и удалить локальный registry:

```bash
docker stop registry
docker rm registry
```

## Insecure registry

По умолчанию Docker ожидает, что registry работает по HTTPS. Если registry работает без TLS по HTTP, Docker будет считать его insecure.

Для Linux Docker Engine insecure registry добавляют в файл:

```text
/etc/docker/daemon.json
```

Пример:

```json
{
  "insecure-registries": ["registry.example.com:5000"]
}
```

После изменения конфигурации нужно перезапустить Docker:

```bash
sudo systemctl restart docker
```

Для Docker Desktop insecure registries настраиваются в настройках Docker Desktop или через Docker Engine config.

В production лучше использовать HTTPS и нормальный сертификат.

## Частые ошибки

Ошибка:

```text
denied: requested access to the resource is denied
```

Частые причины:

- нет `docker login`;
- нет прав на repository;
- образ помечен tag не в тот registry или namespace;
- repository не существует или запрещено создавать его автоматически.

Ошибка:

```text
pull access denied
```

Частые причины:

- образ приватный;
- неправильное имя образа;
- неправильный registry;
- не указан нужный namespace.

Ошибка:

```text
server gave HTTP response to HTTPS client
```

Причина: Docker пытается подключиться к registry по HTTPS, а registry отвечает по HTTP. Нужно настроить HTTPS или добавить registry в `insecure-registries`.

## Короткая памятка

```bash
docker login registry.example.com
docker pull registry.example.com/backend/my-app:1.0.0
docker build -t my-app:latest .
docker tag my-app:latest registry.example.com/backend/my-app:1.0.0
docker push registry.example.com/backend/my-app:1.0.0
docker images
docker logout registry.example.com
```
