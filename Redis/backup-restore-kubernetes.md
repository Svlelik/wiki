# Резервное копирование и восстановление Redis в Kubernetes

Практическая инструкция для переноса данных из `redis-master-0` одного Kubernetes-кластера в одноименный pod другого кластера.

Пример окружения:

- источник: context `kubernetes-admin@dev`;
- назначение: context `kubernetes-admin@k8s-dev`;
- namespace: `mediascope`;
- StatefulSet: `redis-master`;
- pod: `redis-master-0`;
- PVC: `redis-data-redis-master-0`;
- Redis 7.4 из Bitnami-образа;
- persistence на целевом Redis: AOF.

Операция восстановления полностью заменяет данные целевого Redis и требует простоя. Перед началом проверьте имена объектов и согласуйте окно работ.

На целевом PVC должно хватать места одновременно для нового RDB, создаваемого AOF и каталога отката. Лимит памяти helper-pod и целевого Redis должен позволять загрузить весь набор данных из RDB.

## Почему недостаточно скопировать `dump.rdb`

Если в конфигурации целевого Redis указано `appendonly yes`, при старте Redis отдает приоритет AOF. Простая запись файла `/data/dump.rdb` и перезапуск pod могут привести к загрузке старого или пустого AOF, а не нового RDB.

Правильная последовательность:

1. Создать согласованный RDB на источнике.
2. Передать RDB на PVC назначения и проверить контрольную сумму.
3. Остановить целевой Redis.
4. Сохранить старый AOF для отката.
5. Загрузить RDB во временный экземпляр Redis.
6. Преобразовать загруженные данные в AOF.
7. Запустить штатный Redis и проверить число ключей.

## Переменные

Выполняйте команды в Bash или Zsh. Перед началом задайте значения:

```bash
SOURCE_CONTEXT=kubernetes-admin@dev
TARGET_CONTEXT=kubernetes-admin@k8s-dev
NAMESPACE=mediascope
STATEFULSET=redis-master
POD=redis-master-0
PVC=redis-data-redis-master-0

BACKUP_DIR="$HOME/Work/redis-backup-$(date +%Y%m%d-%H%M%S)"
LOCAL_RDB="$BACKUP_DIR/redis-master-0.rdb"
```

Не используйте переменные без проверки их значений перед изменяющими командами:

```bash
printf 'source=%s\ntarget=%s\nnamespace=%s\npod=%s\npvc=%s\nfile=%s\n' \
  "$SOURCE_CONTEXT" "$TARGET_CONTEXT" "$NAMESPACE" "$POD" "$PVC" "$LOCAL_RDB"
```

## 1. Создание RDB на источнике

Переключитесь на источник и проверьте pod:

```bash
kubectl config use-context "$SOURCE_CONTEXT"
kubectl config current-context
kubectl -n "$NAMESPACE" get pod "$POD" -o wide
kubectl -n "$NAMESPACE" exec "$POD" -- df -h /data
```

Узнайте количество ключей до резервного копирования:

```bash
kubectl -n "$NAMESPACE" exec "$POD" -- bash -lc '
cli=/opt/bitnami/redis/bin/redis-cli
if [[ -n ${REDIS_PASSWORD:-} ]]; then
  exec "$cli" -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE
else
  exec "$cli" DBSIZE
fi
'
```

Запустите `BGSAVE` и дождитесь его завершения:

```bash
kubectl -n "$NAMESPACE" exec "$POD" -- bash -lc '
set -e
cli=/opt/bitnami/redis/bin/redis-cli

run_cli() {
  if [[ -n ${REDIS_PASSWORD:-} ]]; then
    "$cli" -a "$REDIS_PASSWORD" --no-auth-warning "$@"
  else
    "$cli" "$@"
  fi
}

run_cli BGSAVE

for _ in {1..300}; do
  info=$(run_cli INFO persistence)
  progress=$(sed -n "s/^rdb_bgsave_in_progress:\([01]\).*/\1/p" <<< "$info" | tr -d "\r")
  status=$(sed -n "s/^rdb_last_bgsave_status:\(.*\)/\1/p" <<< "$info" | tr -d "\r")
  [[ $progress == 0 ]] && break
  sleep 1
done

[[ $progress == 0 && $status == ok ]]
stat -c "size=%s modified=%y" /data/dump.rdb
sha256sum /data/dump.rdb
/opt/bitnami/redis/bin/redis-check-rdb /data/dump.rdb
'
```

Не создавайте большой snapshot командой `redis-cli --rdb /tmp/file.rdb`. `/tmp` часто размещен в `emptyDir` и ограничен лимитом `ephemeral-storage`. При превышении лимита Kubernetes может эвакуировать работающий Redis-pod. `BGSAVE` сохраняет `/data/dump.rdb` непосредственно на PVC.

## 2. Копирование RDB на рабочую машину

Создайте локальную директорию и попробуйте штатное копирование:

```bash
mkdir -p "$BACKUP_DIR"
kubectl -n "$NAMESPACE" cp "$POD:/data/dump.rdb" "$LOCAL_RDB"
```

Получите контрольные суммы на обеих сторонах:

```bash
REMOTE_SHA=$(kubectl -n "$NAMESPACE" exec "$POD" -- sha256sum /data/dump.rdb | awk '{print $1}')
LOCAL_SHA=$(shasum -a 256 "$LOCAL_RDB" | awk '{print $1}')

printf 'remote=%s\nlocal=%s\n' "$REMOTE_SHA" "$LOCAL_SHA"
[[ $REMOTE_SHA == "$LOCAL_SHA" ]]
```

Сохраните checksum рядом с бэкапом:

```bash
(
  cd "$BACKUP_DIR"
  shasum -a 256 redis-master-0.rdb > SHA256SUMS
)
chmod 600 "$LOCAL_RDB" "$BACKUP_DIR/SHA256SUMS"
```

Если `kubectl cp` завершился сообщением `unexpected EOF`, локальный файл неполный, даже если он выглядит большим. Не используйте его до совпадения размера и SHA-256. При нестабильном API-канале копируйте файл небольшими блоками и проверяйте размер каждого блока либо используйте разрешенное внутреннее объектное хранилище.

## 3. Проверка назначения

Переключитесь на целевой кластер:

```bash
kubectl config use-context "$TARGET_CONTEXT"
kubectl config current-context
kubectl -n "$NAMESPACE" get pod "$POD" -o wide
kubectl -n "$NAMESPACE" get statefulset "$STATEFULSET"
kubectl -n "$NAMESPACE" get pvc "$PVC"
kubectl -n "$NAMESPACE" exec "$POD" -- df -h /data
```

Проверьте настройки persistence и текущее количество ключей:

```bash
kubectl -n "$NAMESPACE" exec "$POD" -- bash -lc '
cli=/opt/bitnami/redis/bin/redis-cli
if [[ -n ${REDIS_PASSWORD:-} ]]; then
  auth=(-a "$REDIS_PASSWORD" --no-auth-warning)
else
  auth=()
fi

"$cli" "${auth[@]}" DBSIZE
"$cli" "${auth[@]}" CONFIG GET dir
"$cli" "${auth[@]}" CONFIG GET dbfilename
"$cli" "${auth[@]}" CONFIG GET appendonly
"$cli" "${auth[@]}" CONFIG GET appenddirname
'
```

Дальнейшая последовательность рассчитана на:

```text
dir               /data
dbfilename        dump.rdb
appendonly        yes
appenddirname     appendonlydir
```

Если значения отличаются, скорректируйте пути до начала восстановления.

## 4. Загрузка RDB на PVC назначения

Загружайте файл под временным именем. Пока checksum не совпал, не останавливайте Redis и не заменяйте рабочие файлы.

Сначала попробуйте `kubectl cp`:

```bash
kubectl -n "$NAMESPACE" cp "$LOCAL_RDB" "$POD:/data/.redis-master-0.rdb.restore"
```

Проверьте файл:

```bash
LOCAL_SHA=$(shasum -a 256 "$LOCAL_RDB" | awk '{print $1}')
REMOTE_SHA=$(kubectl -n "$NAMESPACE" exec "$POD" -- \
  sha256sum /data/.redis-master-0.rdb.restore | awk '{print $1}')

printf 'local=%s\nremote=%s\n' "$LOCAL_SHA" "$REMOTE_SHA"
[[ $LOCAL_SHA == "$REMOTE_SHA" ]]

kubectl -n "$NAMESPACE" exec "$POD" -- \
  /opt/bitnami/redis/bin/redis-check-rdb /data/.redis-master-0.rdb.restore
```

### Обход нестабильного `kubectl cp`

В некоторых кластерах API-сервер обрывает большие потоки `kubectl exec -i`/`kubectl cp`. Если pod может подключиться к рабочей машине по VPN, файл можно временно отдать через HTTP.

Определите IP рабочей машины, доступный из pod. В примере это `10.8.2.117`. Не используйте пример вслепую.

Запустите сервер из каталога с бэкапом:

```bash
cd "$BACKUP_DIR"
python3 -m http.server 18765 --bind 10.8.2.117
```

В другом терминале скачайте файл средствами Bash, даже если в образе нет `curl` и `wget`:

```bash
WORKSTATION_IP=10.8.2.117

kubectl -n "$NAMESPACE" exec "$POD" -- \
  env WORKSTATION_IP="$WORKSTATION_IP" bash -lc '
set -e
exec 3<>"/dev/tcp/${WORKSTATION_IP}/18765"
printf "GET /redis-master-0.rdb HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n" \
  "$WORKSTATION_IP" >&3

IFS= read -r status <&3
[[ $status == $'"'"'HTTP/1.0 200 OK\r'"'"' ]]

while IFS= read -r line <&3; do
  [[ $line == $'"'"'\r'"'"' ]] && break
done

cat <&3 > /data/.redis-master-0.rdb.restore
stat -c "size=%s" /data/.redis-master-0.rdb.restore
sha256sum /data/.redis-master-0.rdb.restore
'
```

После передачи остановите HTTP-сервер сочетанием `Ctrl+C`. Этот способ используйте только в доверенной сети: простой HTTP не шифрует данные и не требует аутентификации. Ограничьте bind конкретным VPN-адресом и время работы сервера.

Еще раз сравните SHA-256 и выполните `redis-check-rdb` перед продолжением.

## 5. Подготовка окна восстановления

Если StatefulSet управляется Argo CD, временно отключите автоматическую синхронизацию приложения Redis либо настройте sync window. Иначе Argo CD может вернуть `replicas: 1` во время конвертации, и основной Redis запустится раньше готовности AOF.

После отключения автосинхронизации остановите Redis:

```bash
kubectl -n "$NAMESPACE" scale statefulset "$STATEFULSET" --replicas=0
kubectl -n "$NAMESPACE" wait --for=delete "pod/$POD" --timeout=120s
kubectl -n "$NAMESPACE" get pod "$POD" 2>&1 || true
```

Последняя команда должна вернуть `NotFound`. Если pod появляется снова, не продолжайте: контроллер GitOps уже вернул реплику.

## 6. Временный pod для работы с PVC

Создайте helper-pod, который монтирует тот же PVC:

```bash
REDIS_IMAGE=$(kubectl -n "$NAMESPACE" get statefulset "$STATEFULSET" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')

kubectl -n "$NAMESPACE" run redis-restore-helper \
  --image="$REDIS_IMAGE" \
  --restart=Never \
  --overrides="$(printf '%s' '
{
  "spec": {
    "securityContext": {
      "fsGroup": 1001,
      "seccompProfile": {"type": "RuntimeDefault"}
    },
    "containers": [{
      "name": "redis-restore-helper",
      "image": "REPLACE_IMAGE",
      "command": ["/bin/bash", "-lc", "sleep 3600"],
      "securityContext": {
        "runAsUser": 1001,
        "runAsGroup": 1001,
        "runAsNonRoot": true,
        "allowPrivilegeEscalation": false,
        "capabilities": {"drop": ["ALL"]}
      },
      "volumeMounts": [{"name": "redis-data", "mountPath": "/data"}]
    }],
    "volumes": [{
      "name": "redis-data",
      "persistentVolumeClaim": {"claimName": "REPLACE_PVC"}
    }]
  }
}' | sed "s|REPLACE_IMAGE|$REDIS_IMAGE|; s|REPLACE_PVC|$PVC|")"

kubectl -n "$NAMESPACE" wait \
  --for=condition=Ready pod/redis-restore-helper --timeout=120s
```

Talos Linux на узлах не мешает этому способу: запись выполняется из pod в Kubernetes PVC, а не напрямую в файловую систему узла.

## 7. Сохранение старых данных и установка RDB

Задайте уникальный каталог отката:

```bash
ROLLBACK_DIR="/data/pre-restore-$(date +%Y%m%d-%H%M%S)"
```

Переместите текущие файлы и установите новый RDB:

```bash
kubectl -n "$NAMESPACE" exec redis-restore-helper -- \
  env ROLLBACK_DIR="$ROLLBACK_DIR" bash -lc '
set -e
mkdir "$ROLLBACK_DIR"

[[ ! -e /data/appendonlydir ]] || mv /data/appendonlydir "$ROLLBACK_DIR/appendonlydir"
[[ ! -e /data/dump.rdb ]] || mv /data/dump.rdb "$ROLLBACK_DIR/dump.rdb"

mv /data/.redis-master-0.rdb.restore /data/dump.rdb
chmod 600 /data/dump.rdb

stat -c "file=%n size=%s mode=%a" /data/dump.rdb
sha256sum /data/dump.rdb
'
```

Запишите значение `ROLLBACK_DIR`: оно понадобится для отката.

## 8. Преобразование RDB в AOF

Запустите внутри helper-pod изолированный Redis на порту 6380. Он прочитает RDB, после чего `CONFIG SET appendonly yes` создаст AOF для штатного экземпляра:

```bash
EXPECTED_KEYS=2001306

kubectl -n "$NAMESPACE" exec redis-restore-helper -- \
  env EXPECTED_KEYS="$EXPECTED_KEYS" bash -lc '
set -e

redis_server=/opt/bitnami/redis/bin/redis-server
redis_cli=/opt/bitnami/redis/bin/redis-cli

"$redis_server" \
  --daemonize yes \
  --port 6380 \
  --bind 127.0.0.1 \
  --protected-mode no \
  --dir /data \
  --dbfilename dump.rdb \
  --appendonly no \
  --save "" \
  --logfile /data/restore-convert.log

for _ in {1..120}; do
  [[ $("$redis_cli" -p 6380 PING 2>/dev/null) == PONG ]] && break
  sleep 1
done

keys=$("$redis_cli" -p 6380 DBSIZE)
printf "loaded_keys=%s\n" "$keys"
[[ $keys == "$EXPECTED_KEYS" ]]

"$redis_cli" -p 6380 CONFIG SET appendonly yes

for _ in {1..300}; do
  info=$("$redis_cli" -p 6380 INFO persistence)
  progress=$(sed -n "s/^aof_rewrite_in_progress:\([01]\).*/\1/p" <<< "$info" | tr -d "\r")
  status=$(sed -n "s/^aof_last_bgrewrite_status:\(.*\)/\1/p" <<< "$info" | tr -d "\r")

  if [[ $progress == 0 && $status == ok && \
        -f /data/appendonlydir/appendonly.aof.manifest ]]; then
    break
  fi
  sleep 1
done

[[ $progress == 0 && $status == ok ]]
"$redis_cli" -p 6380 SHUTDOWN NOSAVE || true
sleep 2

/opt/bitnami/redis/bin/redis-check-rdb \
  /data/appendonlydir/appendonly.aof.1.base.rdb
find /data/appendonlydir -maxdepth 1 -type f -printf "%p %s\n"
cat /data/appendonlydir/appendonly.aof.manifest
'
```

Не запускайте основной StatefulSet, пока `redis-check-rdb` не выведет `RDB looks OK` и ожидаемое количество ключей.

## 9. Запуск штатного Redis

Удалите helper-pod и верните одну реплику:

```bash
kubectl -n "$NAMESPACE" delete pod redis-restore-helper --wait=true
kubectl -n "$NAMESPACE" scale statefulset "$STATEFULSET" --replicas=1
kubectl -n "$NAMESPACE" wait \
  --for=condition=Ready "pod/$POD" --timeout=300s
kubectl -n "$NAMESPACE" get pod "$POD" -o wide
```

Проверьте журнал загрузки:

```bash
kubectl -n "$NAMESPACE" logs "$POD" --tail=100
```

В корректном журнале должны присутствовать строки наподобие:

```text
Reading RDB base file on AOF loading...
Done loading RDB, keys loaded: 2001306, keys expired: 0.
DB loaded from append only file
Ready to accept connections tcp
```

## 10. Финальная проверка

```bash
EXPECTED_KEYS=2001306

kubectl -n "$NAMESPACE" exec "$POD" -- \
  env EXPECTED_KEYS="$EXPECTED_KEYS" bash -lc '
set -e
cli=/opt/bitnami/redis/bin/redis-cli

if [[ -n ${REDIS_PASSWORD:-} ]]; then
  auth=(-a "$REDIS_PASSWORD" --no-auth-warning)
else
  auth=()
fi

keys=$("$cli" "${auth[@]}" DBSIZE)
printf "dbsize=%s\n" "$keys"
[[ $keys == "$EXPECTED_KEYS" ]]

"$cli" "${auth[@]}" INFO persistence | grep -E \
  "^(loading|rdb_last_load_keys_expired|rdb_last_load_keys_loaded|aof_enabled|aof_rewrite_in_progress|aof_last_bgrewrite_status|aof_current_size):"
'

kubectl -n "$NAMESPACE" get statefulset "$STATEFULSET"
kubectl -n "$NAMESPACE" get pod "$POD" -o wide
kubectl config current-context
```

Ожидаемый результат:

- `DBSIZE` совпадает с источником;
- `loading:0`;
- `rdb_last_load_keys_loaded` совпадает с ожидаемым числом ключей;
- `aof_enabled:1`;
- StatefulSet имеет одну готовую реплику;
- pod находится в состоянии `1/1 Running`.

После проверки включите автоматическую синхронизацию Argo CD обратно.

## Откат

Если финальная проверка не прошла, не удаляйте каталог `pre-restore-*`.

1. Снова отключите автоматическую синхронизацию Argo CD.
2. Остановите StatefulSet и дождитесь удаления pod.
3. Создайте `redis-restore-helper` по инструкции выше.
4. Переместите неудачные `/data/appendonlydir` и `/data/dump.rdb` в отдельный диагностический каталог.
5. Верните сохраненные файлы из `$ROLLBACK_DIR` на прежние места.
6. Удалите helper-pod, запустите StatefulSet и проверьте `DBSIZE`.

Пример возврата файлов внутри helper-pod:

```bash
ROLLBACK_DIR=/data/pre-restore-YYYYMMDD-HHMMSS

kubectl -n "$NAMESPACE" exec redis-restore-helper -- \
  env ROLLBACK_DIR="$ROLLBACK_DIR" bash -lc '
set -e
failed=/data/failed-restore-$(date +%Y%m%d-%H%M%S)
mkdir "$failed"

[[ ! -e /data/appendonlydir ]] || mv /data/appendonlydir "$failed/appendonlydir"
[[ ! -e /data/dump.rdb ]] || mv /data/dump.rdb "$failed/dump.rdb"

[[ ! -e "$ROLLBACK_DIR/appendonlydir" ]] || \
  mv "$ROLLBACK_DIR/appendonlydir" /data/appendonlydir
[[ ! -e "$ROLLBACK_DIR/dump.rdb" ]] || \
  mv "$ROLLBACK_DIR/dump.rdb" /data/dump.rdb
'
```

## Типовые проблемы

### `kubectl cp`: `unexpected EOF`

API-сервер или прокси оборвал поток. Считайте локальный или удаленный файл поврежденным до проверки SHA-256. Повторите передачу другим способом.

### Pod получил `Evicted` из-за `ephemeral local storage`

Snapshot был записан в `/tmp` или другой `emptyDir`. Удалите завершенный pod, дождитесь пересоздания StatefulSet и используйте `BGSAVE` в `/data`.

### После подмены RDB `DBSIZE` равен нулю

Скорее всего, включен AOF и Redis загрузил пустой `appendonlydir`. Преобразуйте RDB в AOF через временный Redis, как описано выше.

### На диске AOF содержит ключи, а работающий Redis пуст

Основной Redis стартовал до завершения конвертации и держит открытым старый пустой AOF. Проверьте AOF с помощью `redis-check-rdb`, затем штатно пересоздайте pod:

```bash
kubectl -n "$NAMESPACE" delete pod "$POD" --wait=true
kubectl -n "$NAMESPACE" wait \
  --for=condition=Ready "pod/$POD" --timeout=300s
```

Перед этим убедитесь, что валидный AOF уже полностью создан.

### StatefulSet сам возвращается к одной реплике

Это работа Argo CD или другого GitOps-контроллера. Временно отключите автоматическую синхронизацию для приложения Redis и повторите операцию. Не выполняйте конвертацию параллельно с работающим основным Redis.

### В контейнере нет `redis-cli` в `PATH`

Для Bitnami-образа используйте полный путь:

```text
/opt/bitnami/redis/bin/redis-cli
/opt/bitnami/redis/bin/redis-server
/opt/bitnami/redis/bin/redis-check-rdb
```

## Что сохранить после успешного восстановления

- локальный `redis-master-0.rdb`;
- файл `SHA256SUMS`;
- дату и время восстановления;
- исходный и целевой Kubernetes contexts;
- количество ключей на источнике и назначении;
- путь к каталогу отката `/data/pre-restore-*`;
- журналы запуска Redis, подтверждающие загрузку AOF.

Каталог отката удаляйте только после отдельного согласования и завершения периода наблюдения.
