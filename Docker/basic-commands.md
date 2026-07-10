# Основные команды Docker

Docker используют для запуска приложений в контейнерах. Контейнер создается из образа, а образ обычно собирается из `Dockerfile` или скачивается из registry.

## Проверка установки

Показать версию Docker:

```bash
docker --version
```

Показать версии клиента и сервера:

```bash
docker version
```

Показать общую информацию о Docker Engine:

```bash
docker info
```

Проверить запуск контейнера на простом примере:

```bash
docker run hello-world
```

## Работа с контейнерами

Запустить контейнер из образа:

```bash
docker run nginx
```

Запустить контейнер в фоне:

```bash
docker run -d nginx
```

Запустить контейнер с именем:

```bash
docker run -d --name web nginx
```

Показать запущенные контейнеры:

```bash
docker ps
```

Показать все контейнеры, включая остановленные:

```bash
docker ps -a
```

Остановить контейнер:

```bash
docker stop web
```

Запустить остановленный контейнер:

```bash
docker start web
```

Перезапустить контейнер:

```bash
docker restart web
```

Удалить остановленный контейнер:

```bash
docker rm web
```

Принудительно удалить запущенный контейнер:

```bash
docker rm -f web
```

## Порты, переменные окружения и volume mount

Пробросить порт контейнера на локальную машину:

```bash
docker run -d --name web -p 8080:80 nginx
```

В этом примере порт `80` внутри контейнера будет доступен на `localhost:8080`.

Передать переменную окружения:

```bash
docker run -d --name app -e APP_ENV=dev nginx
```

Смонтировать локальный каталог внутрь контейнера:

```bash
docker run -d --name web -p 8080:80 -v "$PWD/html:/usr/share/nginx/html" nginx
```

Смонтировать именованный том:

```bash
docker run -d --name db -v pgdata:/var/lib/postgresql/data postgres
```

## Логи и вход внутрь контейнера

Показать логи контейнера:

```bash
docker logs web
```

Смотреть логи в реальном времени:

```bash
docker logs -f web
```

Показать последние строки логов:

```bash
docker logs --tail 100 web
```

Выполнить команду внутри контейнера:

```bash
docker exec web nginx -v
```

Открыть shell внутри контейнера:

```bash
docker exec -it web sh
```

Если в образе есть `bash`:

```bash
docker exec -it web bash
```

## Работа с образами

Скачать образ:

```bash
docker pull nginx
```

Скачать конкретную версию образа:

```bash
docker pull nginx:1.25
```

Показать локальные образы:

```bash
docker images
```

Собрать образ из текущего каталога:

```bash
docker build -t my-app:latest .
```

Запустить контейнер из собранного образа:

```bash
docker run -d --name my-app -p 8080:8080 my-app:latest
```

Удалить образ:

```bash
docker rmi nginx:1.25
```

Принудительно удалить образ:

```bash
docker rmi -f nginx:1.25
```

## Информация о контейнерах и образах

Показать подробную информацию о контейнере:

```bash
docker inspect web
```

Показать потребление ресурсов контейнерами:

```bash
docker stats
```

Показать процессы внутри контейнера:

```bash
docker top web
```

Показать историю слоев образа:

```bash
docker history nginx
```

## Docker networks

Показать сети:

```bash
docker network ls
```

Создать сеть:

```bash
docker network create app-net
```

Запустить контейнер в выбранной сети:

```bash
docker run -d --name web --network app-net nginx
```

Подключить существующий контейнер к сети:

```bash
docker network connect app-net web
```

Отключить контейнер от сети:

```bash
docker network disconnect app-net web
```

Удалить сеть:

```bash
docker network rm app-net
```

## Docker volumes

Показать тома:

```bash
docker volume ls
```

Создать том:

```bash
docker volume create pgdata
```

Показать подробную информацию о томе:

```bash
docker volume inspect pgdata
```

Удалить том:

```bash
docker volume rm pgdata
```

Использовать том при запуске контейнера:

```bash
docker run -d --name db -v pgdata:/var/lib/postgresql/data postgres
```

## Копирование файлов

Скопировать файл из контейнера на хост:

```bash
docker cp web:/etc/nginx/nginx.conf ./nginx.conf
```

Скопировать файл с хоста в контейнер:

```bash
docker cp ./index.html web:/usr/share/nginx/html/index.html
```

## Очистка ресурсов

Удалить все остановленные контейнеры:

```bash
docker container prune
```

Удалить неиспользуемые образы:

```bash
docker image prune
```

Удалить неиспользуемые сети:

```bash
docker network prune
```

Удалить неиспользуемые тома:

```bash
docker volume prune
```

Удалить все неиспользуемые ресурсы:

```bash
docker system prune
```

Удалить все неиспользуемые ресурсы вместе с неиспользуемыми образами:

```bash
docker system prune -a
```

## Практические примеры

Быстро запустить Nginx на локальном порту `8080`:

```bash
docker run -d --name web -p 8080:80 nginx
```

Запустить контейнер и удалить его после завершения:

```bash
docker run --rm alpine echo "hello"
```

Открыть интерактивный shell в Alpine:

```bash
docker run --rm -it alpine sh
```

Запустить PostgreSQL с паролем и томом:

```bash
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres
```

Остановить и удалить контейнер:

```bash
docker stop postgres
docker rm postgres
```

## Короткая памятка

```bash
docker --version
docker version
docker info
docker run hello-world
docker run -d --name web -p 8080:80 nginx
docker ps
docker ps -a
docker logs -f web
docker exec -it web sh
docker stop web
docker start web
docker restart web
docker rm web
docker pull nginx
docker images
docker build -t my-app:latest .
docker rmi nginx:1.25
docker network ls
docker network create app-net
docker volume ls
docker volume create pgdata
docker container prune
docker image prune
docker system prune
```
