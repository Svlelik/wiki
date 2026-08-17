# Администрирование Talos Linux с помощью talosctl

Практическое руководство по повседневной работе с Talos Linux `v1.13.x`.
Команды и флаги сверены с `talosctl v1.13.5`.

Talos — минимальная API-управляемая операционная система для Kubernetes. В ней
нет SSH, интерактивного shell и привычного `systemd`. Штатный интерфейс
администратора — Talos API на TCP/50000, а основной клиент — `talosctl`.

> **Важно:** примеры изменения конфигурации, состава etcd, reboot, upgrade и
> очистки нельзя выполнять механически. Сначала проверьте адрес, роль ноды,
> кворум, snapshot и план отката. Control-plane обслуживайте строго по одной
> ноде.

## Содержание

1. [Схема тестового кластера](#схема-тестового-кластера)
2. [Подготовка talosctl](#подготовка-talosctl)
3. [Как устроен talosconfig](#как-устроен-talosconfig)
4. [Endpoints, nodes и Kubernetes VIP](#endpoints-nodes-и-kubernetes-vip)
5. [Управление контекстами](#управление-контекстами)
6. [Ежедневная диагностика](#ежедневная-диагностика)
7. [Machine configuration](#machine-configuration)
8. [Правильная генерация конфигов нод](#правильная-генерация-конфигов-нод)
9. [Исправление ошибочной роли worker](#исправление-ошибочной-роли-worker)
10. [Обслуживание etcd](#обслуживание-etcd)
11. [Диски и файловые системы](#диски-и-файловые-системы)
12. [Сеть и Ethernet offload](#сеть-и-ethernet-offload)
13. [Логи, процессы и контейнеры](#логи-процессы-и-контейнеры)
14. [Kubernetes-доступ](#kubernetes-доступ)
15. [Нехватка места на EPHEMERAL](#нехватка-места-на-ephemeral)
16. [Reboot, shutdown, upgrade и rollback](#reboot-shutdown-upgrade-и-rollback)
17. [Support bundle](#support-bundle)
18. [Опасные операции](#опасные-операции)
19. [Ежедневная шпаргалка](#ежедневная-шпаргалка)

## Схема тестового кластера

В примерах используется Talos Linux `v1.13.5`:

| Назначение | Имя | Адрес |
| --- | --- | --- |
| Kubernetes API VIP | `k8s-api` | `192.168.2.210:6443` |
| Control plane | `k8s-master-01` | `192.168.2.211` |
| Control plane | `k8s-master-02` | `192.168.2.212` |
| Control plane | `k8s-master-03` | `192.168.2.213` |
| Worker | `k8s-worker-01` | `192.168.2.214` |
| Worker | `k8s-worker-02` | `192.168.2.215` |

Порты выполняют разные задачи:

- TCP/6443 — Kubernetes API;
- TCP/50000 — Talos API;
- TCP/2379–2380 — etcd между control-plane-нодами;
- TCP/10250 — kubelet API.

VIP `192.168.2.210:6443` обслуживает Kubernetes API. Он не является адресом
Talos API и не должен попадать в `talosconfig.endpoints`. Отдельный
балансировщик, специально настроенный для Talos API TCP/50000, может быть
endpoint, но это другой listener и другая роль.

## Подготовка talosctl

Версия клиента должна быть совместима с версией нод. Для этого руководства
проверена версия `v1.13.5`.

```bash
talosctl version --client
```

Задайте путь к локальному `talosconfig`. Это исключает случайное чтение
`~/.talos/config`:

```bash
export TALOSCONFIG="$PWD/talosconfig"
test -r "$TALOSCONFIG"
talosctl config contexts
talosctl config info
```

Тот же вызов без переменной:

```bash
talosctl --talosconfig "$PWD/talosconfig" config info
```

Права на файл должны запрещать чтение другим пользователям:

```bash
chmod 600 "$TALOSCONFIG"
```

Не добавляйте `talosconfig` в Git. Он содержит клиентский сертификат и private
key, которые дают административный доступ к Talos API.

Проверьте доступность API без вывода секретов:

```bash
talosctl version -n 192.168.2.211
talosctl version -n 192.168.2.214
```

Если команда пытается открыть `~/.talos/config`, переменная `TALOSCONFIG` не
экспортирована или указана только для другого terminal session.

## Как устроен talosconfig

`talosconfig` содержит:

- имя активного context;
- набор именованных contexts;
- Talos API endpoints;
- необязательные default nodes;
- CA, клиентский сертификат и private key.

Секретные поля нельзя печатать в журнал, issue или wiki. Для диагностики
используйте безопасные команды:

```bash
talosctl config contexts
talosctl config info
```

Проверить срок действия клиентского сертификата можно локально, не публикуя
сам сертификат:

```bash
talosctl config info
```

В выводе `config info` проверьте:

- `Current context`;
- `Endpoints`;
- `Nodes`;
- `Roles`;
- срок действия сертификата.

Если context `my-cluster` существует, но `Endpoints` и `Nodes` пусты,
аутентификационные данные сами по себе недостаточны: клиент не знает, куда
подключаться и какую ноду сделать целью.

## Endpoints, nodes и Kubernetes VIP

Это три разные сущности.

### Endpoints

`endpoints` — адреса Talos API, к которым клиент подключается напрямую.
Рекомендуется указывать адреса control-plane-нод:

```bash
talosctl config endpoint \
  192.168.2.211 \
  192.168.2.212 \
  192.168.2.213
```

Несколько endpoints дают failover. Endpoint проксирует запрос к target node,
поэтому worker не обязан быть endpoint.

### Target node

Target node — нода, на которой должна выполниться команда. Ее лучше указывать
явно:

```bash
talosctl get members -n 192.168.2.211
talosctl dashboard -n 192.168.2.214
```

Можно сохранить default node:

```bash
talosctl config node 192.168.2.211
```

Но официальная документация рекомендует обычно использовать явный `-n`. Так
меньше риск выполнить изменяющую команду не на той машине.

### Почему вывод повторяется пять раз

Если сохранить все пять адресов как default nodes:

```bash
talosctl config node \
  192.168.2.211 \
  192.168.2.212 \
  192.168.2.213 \
  192.168.2.214 \
  192.168.2.215
```

то команда без `-n` выполняется для каждой цели. Поэтому `get members` вернет
один и тот же cluster-wide список пять раз. Это не пять кластеров и не
дублирование members — это пять одинаковых запросов.

Верните один безопасный default target:

```bash
talosctl config node 192.168.2.211
talosctl config info
```

Или всегда указывайте `-n`, что предпочтительнее для runbook.

## Управление контекстами

Посмотреть и выбрать context:

```bash
talosctl config contexts
talosctl config context my-cluster
talosctl config info
```

Настроить `my-cluster`:

```bash
talosctl config context my-cluster
talosctl config endpoint \
  192.168.2.211 \
  192.168.2.212 \
  192.168.2.213
talosctl config node 192.168.2.211
talosctl config info
```

При merge одинаково названных contexts `talosctl` по умолчанию не
перезаписывает существующий context, а добавляет числовой суффикс. Так могли
появиться `talos-default`, `talos-default-1` и похожие записи.

Перед удалением лишнего context выполните dry-run:

```bash
talosctl config remove talos-default --dry-run
```

После проверки удалите только подтвержденный context:

```bash
talosctl config remove talos-default
talosctl config contexts
```

Не удаляйте текущий или единственный исправный context, пока не проверена
резервная копия `talosconfig`.

Проверить ошибочный endpoint `10.5.0.2` безопасно можно через:

```bash
talosctl config contexts
talosctl config context talos-default
talosctl config info
talosctl config context my-cluster
```

## Ежедневная диагностика

### Версии и здоровье

```bash
talosctl version -n 192.168.2.211
talosctl health -n 192.168.2.211
```

`health` проверяет Talos, etcd и Kubernetes-компоненты. Не продолжайте
обслуживание, если cluster health уже нарушен.

### Состав кластера

```bash
talosctl get members -n 192.168.2.211
```

Смотрите:

- hostname;
- machine type;
- адреса;
- operating system/version;
- статус members.

`get members` показывает discovery membership, а не только etcd. Состав etcd
проверяется отдельной командой:

```bash
talosctl etcd members -n 192.168.2.211
talosctl etcd status -n 192.168.2.211,192.168.2.212,192.168.2.213
```

Worker не должен присутствовать в `etcd members`.

### Интерактивный dashboard

```bash
talosctl dashboard -n 192.168.2.214
```

Dashboard показывает services, CPU, memory, load, network и логи в реальном
времени. Выход — `q` или `Ctrl+C`.

### Доступные ресурсы

```bash
talosctl get rd -n 192.168.2.214
```

`rd` — resource definitions. После этого нужный ресурс можно получить через
`talosctl get <type>`.

## Machine configuration

Machine configuration полностью определяет состояние Talos-ноды. Она содержит
секреты кластера, поэтому полный вывод нельзя публиковать.

### Offline validation

Проверка файла для bare metal или VM:

```bash
talosctl validate \
  --config k8s-worker-01.yaml \
  --mode metal \
  --strict
```

Для container-based Talos используется `--mode container`, для cloud —
`--mode cloud`.

Проверка `machine.type` через `yq`:

```bash
yq '.machine.type' k8s-worker-01.yaml
```

Ожидается:

```text
worker
```

Для control-plane-конфига:

```bash
yq '.machine.type' k8s-master-01.yaml
```

Ожидается `controlplane`.

### Проверка полного файла перед применением

Read-only dry-run:

```bash
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --dry-run
```

Dry-run показывает способ применения и изменения, но не заменяет review
самого файла.

После проверки конфигурация применяется изменяющей командой:

```bash
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --mode auto
```

После применения:

```bash
talosctl version -n 192.168.2.214
talosctl get members -n 192.168.2.211
kubectl get node k8s-worker-01 -o wide
```

### Patch текущей конфигурации

Проверьте patch без применения:

```bash
talosctl patch machineconfig \
  -n 192.168.2.214 \
  --patch @worker-runtime.patch.yaml \
  --dry-run
```

Применение:

```bash
talosctl patch machineconfig \
  -n 192.168.2.214 \
  --patch @worker-runtime.patch.yaml \
  --mode auto
```

Для рискованного изменения, которое Talos может откатить по timeout:

```bash
talosctl patch machineconfig \
  -n 192.168.2.214 \
  --patch @network.patch.yaml \
  --mode try \
  --timeout 2m
```

`try` подходит не для каждого изменения. Следуйте change summary из dry-run.

### Интерактивное редактирование

Read-only preview через редактор:

```bash
TALOS_EDITOR=vi talosctl edit machineconfig \
  -n 192.168.2.214 \
  --dry-run
```

Изменяющий вариант:

```bash
TALOS_EDITOR=vi talosctl edit machineconfig \
  -n 192.168.2.214 \
  --mode auto
```

Для воспроизводимых инфраструктурных изменений лучше хранить обезличенный
patch в Git, а не редактировать ноду вручную.

## Правильная генерация конфигов нод

`talosctl gen config` создает как минимум:

- `controlplane.yaml` с `machine.type: controlplane`;
- `worker.yaml` с `machine.type: worker`;
- `talosconfig`.

Node-specific patch меняет hostname, адрес, interface, install disk и другие
параметры, но не превращает исходный control-plane-конфиг в worker.

### Ошибочный вариант

```bash
# Ошибка: результат сохранит machine.type: controlplane
talosctl machineconfig patch controlplane.yaml \
  --patch @k8s-worker-01.patch \
  --output k8s-worker-01.yaml
```

Такая нода запустит control-plane-компоненты и может присоединиться к etcd.

### Правильный вариант

```bash
talosctl machineconfig patch worker.yaml \
  --patch @k8s-worker-01.patch \
  --output k8s-worker-01.yaml

talosctl machineconfig patch worker.yaml \
  --patch @k8s-worker-02.patch \
  --output k8s-worker-02.yaml
```

Обязательные проверки:

```bash
yq '.machine.type' k8s-worker-01.yaml
yq '.machine.network.hostname' k8s-worker-01.yaml
talosctl validate --config k8s-worker-01.yaml --mode metal --strict
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --dry-run
```

Проверьте также install disk и IP, чтобы конфиг одной ноды не применился к
другой.

## Исправление ошибочной роли worker

Сценарий: `192.168.2.214` или `192.168.2.215` был создан из
`controlplane.yaml`, получил `machine.type: controlplane` и вошел в etcd.

> **Высокий риск:** ошибка может нарушить quorum etcd или доступность
> Kubernetes API. Работайте только с одной ошибочной нодой за раз. Не
> выполняйте команды ниже автоматически.

Официально документированный консервативный путь смены роли — graceful
`talosctl reset`, удаление Kubernetes Node и повторное provisioning с
worker-конфигурацией. `reset` стирает данные ноды и может сделать VM
незагрузочной, поэтому он исключен из автоматического сценария этой задачи.

Последовательность `etcd leave` и применения полного worker-конфига ниже
собрана из документированной семантики отдельных команд, но не опубликована
Talos `v1.13` как отдельная процедура конвертации роли. Используйте ее только
в согласованное окно, после проверки в аналогичном тестовом окружении и с
доступом к консоли/гипервизору.

### 1. Подготовьте правильный worker-конфиг

```bash
talosctl machineconfig patch worker.yaml \
  --patch @k8s-worker-01.patch \
  --output k8s-worker-01.yaml

yq '.machine.type' k8s-worker-01.yaml
talosctl validate --config k8s-worker-01.yaml --mode metal --strict
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --dry-run
```

### 2. Проверьте исходное состояние

```bash
talosctl health -n 192.168.2.211
talosctl get members -n 192.168.2.211
talosctl etcd members -n 192.168.2.211
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213,192.168.2.214
kubectl get nodes -o wide
```

Запишите member ID и убедитесь, что после удаления ошибочного участника
останется quorum. Для обычного трехчленного etcd нужны как минимум два
доступных участника.

### 3. Создайте snapshot

Snapshot содержит Kubernetes Secrets. Храните его с правами `0600` в
зашифрованном хранилище:

```bash
SNAPSHOT="etcd-before-worker-role-fix-$(date +%Y%m%d-%H%M%S).snapshot"
talosctl etcd snapshot "$SNAPSHOT" -n 192.168.2.211
chmod 600 "$SNAPSHOT"
shasum -a 256 "$SNAPSHOT" > "$SNAPSHOT.sha256"
```

### 4. При необходимости освободите workload

```bash
kubectl cordon k8s-worker-01
kubectl drain k8s-worker-01 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=10m
```

`--delete-emptydir-data` удаляет временные данные pod'ов. Перед drain
убедитесь, что это допустимо.

### 5. Попросите доступную ноду выйти из etcd

```bash
talosctl etcd leave -n 192.168.2.214
```

`etcd leave` предпочтительнее `remove-member`, пока нода доступна: запрос
выполняется на самой ноде, которая корректно покидает кластер. Команда
`remove-member` предназначена прежде всего для недоступного/потерянного
участника и требует особенно точной идентификации member.

Аварийный синтаксис для уже недоступного member:

```bash
talosctl etcd remove-member MEMBER_ID -n 192.168.2.211
```

Эта команда выполняется через здоровую control-plane-ноду. Не используйте ее,
если target способен выполнить `etcd leave`, и не удаляйте member без расчета
оставшегося quorum.

Сразу проверьте оставшийся etcd:

```bash
talosctl etcd members -n 192.168.2.211
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
```

### 6. Примените worker-конфиг

```bash
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --mode reboot
```

Дождитесь возврата:

```bash
talosctl version -n 192.168.2.214
talosctl get members -n 192.168.2.211
talosctl etcd members -n 192.168.2.211
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
kubectl get node k8s-worker-01 -o wide
kubectl wait \
  --for=condition=Ready \
  node/k8s-worker-01 \
  --timeout=10m
```

Worker должен исчезнуть из `etcd members`, остаться в Talos discovery members
как worker и вернуться в Kubernetes.

Разрешите планирование:

```bash
kubectl uncordon k8s-worker-01
```

Только после полной проверки повторяйте процедуру для второй ошибочной ноды.

## Обслуживание etcd

Команды `talosctl etcd` работают на control-plane-нодах.

### Members, status и alarms

```bash
talosctl etcd members -n 192.168.2.211
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
talosctl etcd alarm list -n 192.168.2.211
```

В `status` сравните:

- `DB SIZE`;
- `IN USE`;
- leader;
- raft indexes;
- `ERRORS`.

Большая разница между `DB SIZE` и `IN USE` означает фрагментацию. `NOSPACE`
означает, что etcd превысил quota и остановил операции записи.

### Snapshot

```bash
SNAPSHOT="etcd-$(date +%Y%m%d-%H%M%S).snapshot"
talosctl etcd snapshot "$SNAPSHOT" -n 192.168.2.211
chmod 600 "$SNAPSHOT"
shasum -a 256 "$SNAPSHOT" > "$SNAPSHOT.sha256"
```

Snapshot можно снять с любой здоровой control-plane-ноды. Регулярно переносите
его в одобренное зашифрованное хранилище и проверяйте retention.

### Defrag

> **Высокий риск:** defrag блокирует чтение и запись на обрабатываемом member
> и создает нагрузку. Выполняйте по одной ноде, после snapshot.

Сначала status:

```bash
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
```

Обработайте одну ноду:

```bash
talosctl etcd defrag -n 192.168.2.211
talosctl etcd status -n 192.168.2.211
```

Убедитесь, что нода здорова и raft index догнал кластер. Затем по очереди:

```bash
talosctl etcd defrag -n 192.168.2.212
talosctl etcd status -n 192.168.2.212

talosctl etcd defrag -n 192.168.2.213
talosctl etcd status -n 192.168.2.213
```

После устранения причины `NOSPACE` и проверки status снимите alarm:

```bash
talosctl etcd alarm disarm -n 192.168.2.211
talosctl etcd alarm list -n 192.168.2.211
```

Не disarm'ьте alarm до освобождения места, defrag или корректировки quota.

## Диски и файловые системы

Talos использует системные volumes:

- `EFI`/`BIOS` и `BOOT` — загрузка;
- `META` — metadata;
- `STATE` — machine configuration и состояние Talos;
- `EPHEMERAL` — `/var`, container images, writable layers, logs, kubelet data
  и etcd на control-plane.

### Read-only диагностика

```bash
talosctl get disks -n 192.168.2.214
talosctl get volumestatuses -n 192.168.2.214
talosctl mounts -n 192.168.2.214
talosctl usage /var \
  -n 192.168.2.214 \
  --humanize \
  --depth 2
```

Дополнительно:

```bash
talosctl list /var -n 192.168.2.214
talosctl read /proc/meminfo -n 192.168.2.214
```

Talos API дает ограниченный доступ к файловой системе. Это не замена SSH и не
разрешение вручную удалять внутренние файлы из `/var`.

### VolumeConfig для EPHEMERAL

По умолчанию в Talos `v1.13` EPHEMERAL:

- находится на system disk;
- имеет минимум `2GiB`;
- использует `grow: true`;
- при отсутствии `maxSize` расширяется в доступное пространство после volume.

`VolumeConfig` применяется при provisioning volume. Добавление нового
документа не переразмечает уже созданный EPHEMERAL задним числом. Для
существующего стандартного volume автоматическое расширение после увеличения
диска обеспечивается его исходным `grow: true`.

Явный документ:

```yaml
---
apiVersion: v1alpha1
kind: VolumeConfig
name: EPHEMERAL
provisioning:
  diskSelector:
    match: system_disk
  minSize: 2GiB
  grow: true
```

Перед добавлением VolumeConfig проверьте текущую machine configuration,
разметку диска и dry-run. Не задавайте `maxSize`, не понимая будущую схему
разделов.

## Сеть и Ethernet offload

### Интерфейсы, адреса и маршруты

```bash
talosctl get links -n 192.168.2.214
talosctl get addresses -n 192.168.2.214
talosctl get routes -n 192.168.2.214
talosctl get resolvers -n 192.168.2.214
talosctl netstat -n 192.168.2.214
```

Проверьте конкретный интерфейс:

```bash
talosctl get ethernetstatus enp0s1 \
  -n 192.168.2.214 \
  -o yaml
```

### Packet capture

Короткий capture:

```bash
talosctl pcap \
  -n 192.168.2.214 \
  --interface enp0s1 \
  --duration 30s \
  --output enp0s1.pcap
```

PCAP может содержать чувствительный трафик. Храните и передавайте его как
диагностический секрет. При длинном capture исключайте TCP/50000, чтобы не
захватывать собственный Talos API stream.

### Ethernet offload

Текущее состояние находится в `EthernetStatus`. Пример:

```bash
talosctl get ethernetstatus enp0s1 \
  -n 192.168.2.214 \
  -o yaml
```

Если драйвер позволяет изменять функции, используется отдельный config
document:

```yaml
---
apiVersion: v1alpha1
kind: EthernetConfig
name: enp0s1
features:
  tx-udp_tnl-segmentation: false
  tx-udp_tnl-csum-segmentation: false
```

Сначала добавьте документ к копии machine configuration и выполните:

```bash
talosctl validate --config k8s-worker-01.yaml --mode metal --strict
talosctl apply-config \
  -n 192.168.2.214 \
  --file k8s-worker-01.yaml \
  --dry-run
```

`off [fixed]` означает, что функция уже выключена, а драйвер не разрешает
изменять ее состояние. На всех пяти нодах рассматриваемого кластера
`tx-udp_tnl-segmentation` и `tx-udp_tnl-csum-segmentation` наблюдались как
`off [fixed]`; применять EthernetConfig там не требуется.

## Логи, процессы и контейнеры

### Services

```bash
talosctl service -n 192.168.2.214
talosctl service kubelet -n 192.168.2.214
```

Изменение состояния service:

```bash
talosctl service kubelet restart -n 192.168.2.214
```

Restart используйте только после просмотра logs и понимания причины.

### Logs и kernel messages

```bash
talosctl logs kubelet \
  -n 192.168.2.214 \
  --tail 100

talosctl logs kubelet \
  -n 192.168.2.214 \
  --follow

talosctl dmesg -n 192.168.2.214
talosctl dmesg -n 192.168.2.214 --follow --tail
```

### Processes и ресурсы

```bash
talosctl processes -n 192.168.2.214
talosctl memory -n 192.168.2.214
talosctl cgroups -n 192.168.2.214
talosctl containers -n 192.168.2.214
talosctl containers -n 192.168.2.214 --kubernetes
talosctl stats -n 192.168.2.214
talosctl stats -n 192.168.2.214 --kubernetes
```

Без `--kubernetes` показывается system containerd namespace, с
`--kubernetes` — workload namespace `k8s.io`.

### Runtime images

```bash
talosctl image list -n 192.168.2.214 --namespace cri
talosctl image list -n 192.168.2.214 --namespace system
```

Не удаляйте system images. Удаление CRI image допустимо только после проверки,
что он не используется и может быть повторно скачан:

```bash
talosctl image remove \
  registry.example.invalid/demo/app:old \
  -n 192.168.2.214 \
  --namespace cri
```

Это точечная изменяющая команда, а не безопасный общий prune.

## Kubernetes-доступ

Получить отдельный kubeconfig без merge:

```bash
talosctl kubeconfig ./kubeconfig-my-cluster \
  -n 192.168.2.211 \
  --merge=false

chmod 600 ./kubeconfig-my-cluster
export KUBECONFIG="$PWD/kubeconfig-my-cluster"
kubectl config current-context
kubectl get nodes -o wide
```

По умолчанию `talosctl kubeconfig` merge'ит context в `~/.kube/config`.
Отдельный файл безопаснее для runbook и снижает риск работы не с тем кластером.

Базовые проверки:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
kubectl get events -A --sort-by=.lastTimestamp
```

Kubernetes kubeconfig и `talosconfig` — разные credential для разных API.

## Нехватка места на EPHEMERAL

`EPHEMERAL` смонтирован в `/var`. Здесь находятся CRI data, images, logs,
kubelet state и etcd data на control-plane.

### 1. Подтвердите проблему

```bash
talosctl mounts -n 192.168.2.214
talosctl get volumestatuses -n 192.168.2.214
talosctl usage /var \
  -n 192.168.2.214 \
  --humanize \
  --depth 2

kubectl describe node k8s-worker-01
kubectl get node k8s-worker-01 \
  -o jsonpath='{range .status.conditions[?(@.type=="DiskPressure")]}{.type}={.status}{" reason="}{.reason}{"\n"}{end}'
```

В `describe node` найдите condition `DiskPressure` и events.

### 2. Проверьте images и workload

```bash
talosctl image list -n 192.168.2.214 --namespace cri
talosctl image list -n 192.168.2.214 --namespace system
kubectl get pods -A \
  --field-selector=status.phase==Failed
kubectl get pods -A \
  --field-selector=status.phase==Succeeded
```

Завершенные pod'ы удаляйте через Kubernetes API и только после проверки
controller/Job history:

```bash
kubectl delete pod POD_NAME -n NAMESPACE
```

Не удаляйте вручную каталоги containerd/kubelet из `/var`.

### 3. На control-plane проверьте etcd

```bash
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
talosctl etcd alarm list -n 192.168.2.211
```

Если `DB SIZE` намного больше `IN USE`, после snapshot выполните defrag по
одной ноде. Если `IN USE` само близко к quota, defrag недостаточно: нужно
уменьшить количество объектов или обоснованно изменить
`cluster.etcd.extraArgs.quota-backend-bytes`. Официально рекомендуемый максимум
quota — `8GiB`.

### 4. Предпочтительный путь для VM — увеличить диск

1. Создайте backup/snapshot VM согласно правилам гипервизора.
2. Увеличьте виртуальный диск.
3. Перезагрузите только одну Talos-ноду.
4. Проверьте disk и VolumeStatus.

```bash
talosctl reboot -n 192.168.2.214 --wait
talosctl get disks -n 192.168.2.214
talosctl get volumestatuses -n 192.168.2.214
talosctl usage /var \
  -n 192.168.2.214 \
  --humanize \
  --depth 1
```

При стандартном `EPHEMERAL` с `grow: true`, без ограничивающего `maxSize` и
при наличии свободного непрерывного пространства после volume Talos расширит
его на последующем boot. Если этого не произошло, проверьте VolumeConfig и
фактическую разметку; не применяйте `wipe`.

### 5. Worker: cordon/drain и пересоздание

Если диск нельзя расширить, worker можно пересоздать после drain:

```bash
kubectl cordon k8s-worker-01
kubectl drain k8s-worker-01 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=10m
```

Дальнейший reset/reinstall — отдельная разрушительная операция и не входит в
этот runbook.

`reset` и `wipe` нельзя использовать как обычную очистку диска.

## Reboot, shutdown, upgrade и rollback

### Общие preflight

Перед обслуживанием:

```bash
talosctl health -n 192.168.2.211
kubectl get nodes
kubectl get pods -A
```

Для control-plane дополнительно:

```bash
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
talosctl etcd snapshot \
  "etcd-pre-maintenance-$(date +%Y%m%d-%H%M%S).snapshot" \
  -n 192.168.2.211
```

### Reboot

Worker с drain:

```bash
talosctl reboot \
  -n 192.168.2.214 \
  --drain \
  --drain-timeout 10m \
  --wait
```

Control-plane обрабатывайте по одной ноде:

```bash
talosctl reboot -n 192.168.2.211 --wait
talosctl version -n 192.168.2.211
talosctl etcd status -n 192.168.2.211
kubectl wait \
  --for=condition=Ready \
  node/k8s-master-01 \
  --timeout=10m
```

### Shutdown

```bash
talosctl shutdown -n 192.168.2.214 --wait
```

Не используйте `--force`, кроме аварийного сценария: он пропускает обычный
cordon/drain.

### Upgrade

> **Высокий риск:** заранее проверьте release notes, совместимость extensions,
> installer image и upgrade path. Обновляйте по одной ноде.

Пример для заранее выбранной версии:

```bash
TARGET_TALOS=v1.13.7
talosctl upgrade \
  -n 192.168.2.214 \
  --image "ghcr.io/siderolabs/installer:${TARGET_TALOS}" \
  --wait
```

После каждой ноды:

```bash
talosctl version -n 192.168.2.214
kubectl get node k8s-worker-01 -o wide
```

Для control-plane также проверьте etcd и cluster health до перехода к
следующей ноде.

### Rollback

Talos использует A/B scheme и сохраняет предыдущую установку. Ручной rollback
переключает boot reference и перезагружает ноду:

```bash
talosctl rollback -n 192.168.2.214
```

После возврата:

```bash
talosctl version -n 192.168.2.214
kubectl get node k8s-worker-01 -o wide
```

Rollback OS не откатывает автоматически machine configuration или Kubernetes
объекты. План отката должен учитывать их отдельно.

## Support bundle

Support bundle собирает kernel/service logs, Talos resources без secrets,
processes, pressure, mounts, версии и часть Kubernetes-диагностики.

Для одной ноды:

```bash
talosctl support \
  -n 192.168.2.214 \
  --output "support-k8s-worker-01-$(date +%Y%m%d-%H%M%S).zip"
```

Для кластера:

```bash
talosctl support \
  -n 192.168.2.211,192.168.2.212,192.168.2.213,192.168.2.214,192.168.2.215 \
  --output "support-my-cluster-$(date +%Y%m%d-%H%M%S).zip"
```

Несмотря на фильтрацию secrets, bundle содержит внутренние адреса, имена,
логи и конфигурационную metadata. Передавайте его только по одобренному
каналу и удаляйте по retention policy.

## Опасные операции

Следующие команды не являются обычным обслуживанием:

- `talosctl reset` — удаляет ноду из Kubernetes/etcd, стирает данные и
  выключает или перезагружает машину;
- `talosctl wipe` — стирает block device или volume;
- `talosctl bootstrap` — первичная инициализация etcd; повторный запуск может
  разрушить кластер;
- `talosctl bootstrap --recover-from` — disaster recovery всего etcd;
- `talosctl rotate-ca` — ротация CA;
- `talosctl etcd remove-member` — принудительное удаление etcd member;
- `talosctl apply-config --insecure` — доступ к maintenance API без обычной
  client authentication.

Не запускайте их без отдельного runbook, backup и подтверждения.

### Аварийный чек-лист перед изменением

1. Правильны ли `TALOSCONFIG`, context, endpoint и `-n`?
2. Известна ли роль выбранной ноды?
3. Здоровы ли Kubernetes и etcd до изменения?
4. Сохранен ли свежий etcd snapshot с checksum?
5. Не обрабатывается ли другая control-plane-нода?
6. Есть ли доступ к гипервизору/консоли при потере Talos API?
7. Есть ли проверенный rollback?
8. Записаны ли критерии остановки?

## Ежедневная шпаргалка

```bash
# Явно выбрать credential
export TALOSCONFIG="$PWD/talosconfig"

# Проверить context и endpoints
talosctl config contexts
talosctl config info

# Версия и здоровье
talosctl version -n 192.168.2.211
talosctl health -n 192.168.2.211

# Discovery и etcd
talosctl get members -n 192.168.2.211
talosctl etcd members -n 192.168.2.211
talosctl etcd status \
  -n 192.168.2.211,192.168.2.212,192.168.2.213
talosctl etcd alarm list -n 192.168.2.211

# Сервисы и логи
talosctl service -n 192.168.2.214
talosctl logs kubelet -n 192.168.2.214 --tail 100
talosctl dmesg -n 192.168.2.214
talosctl dashboard -n 192.168.2.214

# Диски
talosctl get disks -n 192.168.2.214
talosctl get volumestatuses -n 192.168.2.214
talosctl mounts -n 192.168.2.214
talosctl usage /var -n 192.168.2.214 --humanize --depth 2

# Сеть
talosctl get links -n 192.168.2.214
talosctl get addresses -n 192.168.2.214
talosctl get routes -n 192.168.2.214
talosctl get ethernetstatus enp0s1 \
  -n 192.168.2.214 \
  -o yaml
talosctl netstat -n 192.168.2.214

# Runtime
talosctl processes -n 192.168.2.214
talosctl memory -n 192.168.2.214
talosctl containers -n 192.168.2.214 --kubernetes
talosctl stats -n 192.168.2.214 --kubernetes
```

## Официальная документация

- [talosctl: configuration, endpoints и nodes](https://docs.siderolabs.com/talos/v1.13/learn-more/talosctl)
- [Формат talosconfig](https://docs.siderolabs.com/talos/v1.13/reference/talosconfig)
- [Talos для Linux-администраторов](https://docs.siderolabs.com/talos/v1.13/learn-more/talos-for-linux-admins)
- [Редактирование machine configuration](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/system-configuration/editing-machine-configuration)
- [Ethernet configuration](https://docs.siderolabs.com/talos/v1.13/networking/advanced/ethernet-config)
- [System volumes и EPHEMERAL](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/storage-and-disk-management/disk-management/system)
- [Etcd maintenance](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance)
- [Disaster recovery и etcd snapshot](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery)
- [Удаление нод из кластера](https://docs.siderolabs.com/talos/v1.13/deploy-and-manage-workloads/scaling-down)
- [Разрушительный reset ноды](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/resetting-a-machine)
- [Upgrade Talos](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
- [CLI reference](https://docs.siderolabs.com/talos/v1.13/reference/cli)
