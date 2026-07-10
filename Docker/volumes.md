# Docker volumes

Docker volume - это управляемое Docker хранилище данных. Volume живет отдельно от контейнера, поэтому данные могут сохраниться после остановки или удаления контейнера.

Volumes удобно использовать для:

- данных баз данных;
- файлов приложения, которые должны переживать пересоздание контейнера;
- обмена данными между контейнерами;
- отделения данных от образа и контейнера.

## Volume и bind mount

В Docker есть два частых способа подключить данные к контейнеру.

| Способ | Пример | Где лежат данные | Когда использовать |
| --- | --- | --- | --- |
| Volume | `-v pgdata:/var/lib/postgresql/data` | В Docker storage | Для постоянных данных контейнеров |
| Bind mount | `-v "$PWD/html:/usr/share/nginx/html"` | В указанном каталоге хоста | Для разработки и прямого доступа к файлам |

Volume управляется Docker: его можно создать, посмотреть, подключить к контейнеру и удалить командами `docker volume`.

Bind mount напрямую привязан к пути на хосте. Если путь удалить или изменить права на файлы, контейнер сразу это почувствует.

## Основные команды

Показать список volumes:

```bash
docker volume ls
```

Создать volume:

```bash
docker volume create pgdata
```

Посмотреть подробную информацию:

```bash
docker volume inspect pgdata
```

## Где физически хранится volume

Команда:

```bash
docker volume create pgdata
```

создает именованный volume `pgdata`. Если используется стандартный драйвер `local`, Docker хранит его в своей служебной директории.

На Linux Docker Engine данные обычно лежат здесь:

```text
/var/lib/docker/volumes/pgdata/_data
```

Проверить точный путь можно командой:

```bash
docker volume inspect pgdata
```

В выводе будет поле `Mountpoint`, например:

```json
"Mountpoint": "/var/lib/docker/volumes/pgdata/_data"
```

Важно: на Docker Desktop для macOS и Windows этот путь находится не напрямую в файловой системе хоста, а внутри Linux VM, в которой работает Docker Engine. То есть `docker volume inspect` тоже может показать путь вида `/var/lib/docker/volumes/pgdata/_data`, но это путь внутри виртуальной машины Docker Desktop, а не обычная папка macOS или Windows.

Практический вывод:

- внутри контейнера volume виден по тому пути, куда его смонтировали, например `/var/lib/postgresql/data`;
- на Linux-хосте его можно найти через `Mountpoint`;
- на Docker Desktop volume физически хранится внутри служебной VM Docker, поэтому напрямую работать с ним как с обычной локальной папкой не стоит;
- для доступа к данным лучше использовать контейнеры, `docker cp`, временный контейнер для копирования или бэкап через `tar`.

Удалить volume:

```bash
docker volume rm pgdata
```

Удалить все неиспользуемые volumes:

```bash
docker volume prune
```

Важно: удалить можно только volume, который не используется контейнерами.

## Подключение через -v

Формат:

```bash
docker run -v <volume_name>:<path_inside_container> <image>
```

Пример с PostgreSQL:

```bash
docker volume create pgdata

docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

В этом примере данные PostgreSQL будут храниться в volume `pgdata`, а не внутри слоя контейнера.

Остановить и удалить контейнер:

```bash
docker stop postgres
docker rm postgres
```

Volume при этом останется:

```bash
docker volume ls
```

Если снова запустить PostgreSQL с тем же volume, данные будут доступны:

```bash
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

## Подключение через --mount

`--mount` более явный, чем `-v`, и удобен для читаемых команд.

Формат:

```bash
docker run --mount type=volume,source=<volume_name>,target=<path_inside_container> <image>
```

Пример:

```bash
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  --mount type=volume,source=pgdata,target=/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

## Пример с Nginx

Создать volume:

```bash
docker volume create nginx-data
```

Запустить Nginx с volume:

```bash
docker run -d \
  --name web \
  -p 8080:80 \
  -v nginx-data:/usr/share/nginx/html \
  nginx
```

Положить файл в volume через временный контейнер:

```bash
docker run --rm \
  -v nginx-data:/data \
  alpine \
  sh -c 'echo "hello from volume" > /data/index.html'
```

Проверить содержимое:

```bash
curl http://localhost:8080
```

## Копирование данных из volume

Docker volume нельзя скопировать обычной командой `cp` напрямую по имени. Практичный способ - подключить volume к временному контейнеру.

Скопировать данные из volume в текущий каталог:

```bash
mkdir -p ./volume-copy

docker run --rm \
  -v pgdata:/from \
  -v "$PWD/volume-copy:/to" \
  alpine \
  sh -c "cp -a /from/. /to/"
```

Скопировать данные из локального каталога в volume:

```bash
docker run --rm \
  -v pgdata:/to \
  -v "$PWD/volume-copy:/from" \
  alpine \
  sh -c "cp -a /from/. /to/"
```

## Бэкап volume через tar

Создать архив с содержимым volume:

```bash
docker run --rm \
  -v pgdata:/data \
  -v "$PWD:/backup" \
  alpine \
  tar -czf /backup/pgdata-backup.tar.gz -C /data .
```

Восстановить данные из архива в volume:

```bash
docker run --rm \
  -v pgdata:/data \
  -v "$PWD:/backup" \
  alpine \
  tar -xzf /backup/pgdata-backup.tar.gz -C /data
```

Перед восстановлением лучше остановить контейнеры, которые используют этот volume.

## Удаление containers и сохранность данных

Удаление контейнера не удаляет именованный volume:

```bash
docker rm postgres
docker volume ls
```

Но если контейнер был запущен с анонимным volume, его сложнее найти по понятному имени. Поэтому для важных данных лучше создавать именованные volumes:

```bash
docker volume create app-data
docker run -d --name app -v app-data:/app/data my-app
```

Удалить контейнер вместе с anonymous volumes можно так:

```bash
docker rm -v container_name
```

Для именованных volumes команда `docker rm -v` не удаляет сам volume, если он был указан явно по имени.

## Очистка volumes

Посмотреть volumes:

```bash
docker volume ls
```

Удалить конкретный volume:

```bash
docker volume rm pgdata
```

Удалить все volumes, которые не используются контейнерами:

```bash
docker volume prune
```

Команда `docker system prune` по умолчанию не удаляет volumes. Для удаления неиспользуемых volumes вместе с остальными ресурсами нужна отдельная опция:

```bash
docker system prune --volumes
```

Перед очисткой стоит проверить, что нужные контейнеры не удалены и volume не остался единственной копией важных данных.

## Практический сценарий

1. Создать volume:

```bash
docker volume create pgdata
```

2. Запустить PostgreSQL:

```bash
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

3. Проверить, что контейнер работает:

```bash
docker ps
docker logs postgres
```

4. Пересоздать контейнер без потери данных:

```bash
docker stop postgres
docker rm postgres

docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

5. Сделать бэкап volume:

```bash
docker run --rm \
  -v pgdata:/data \
  -v "$PWD:/backup" \
  alpine \
  tar -czf /backup/pgdata-backup.tar.gz -C /data .
```

## Короткая памятка

```bash
docker volume create pgdata
docker volume ls
docker volume inspect pgdata
docker run -d --name postgres -e POSTGRES_PASSWORD=secret -v pgdata:/var/lib/postgresql/data postgres
docker run -d --name postgres -e POSTGRES_PASSWORD=secret --mount type=volume,source=pgdata,target=/var/lib/postgresql/data postgres
docker stop postgres
docker rm postgres
docker volume rm pgdata
docker volume prune
docker system prune --volumes
docker run --rm -v pgdata:/data -v "$PWD:/backup" alpine tar -czf /backup/pgdata-backup.tar.gz -C /data .
```
