# TASK_018

## Заголовок

Практическая документация по администрированию Talos Linux и работе с `talosctl`

## Статус

`done`

## Кратко

Нужно подготовить подробный русскоязычный материал в разделе `Kubernetes`, который систематизирует практическую работу с Talos Linux и `talosctl`: подключение к кластеру, устройство `talosconfig`, диагностику нод, исправление ролей машин, обслуживание etcd, работу с дисками и сетью, просмотр логов, изменение machine configuration и действия при нехватке дискового пространства.

Материал должен быть оформлен как воспроизводимая инструкция администратора с безопасными командами, пояснением ожидаемого результата и отдельными предупреждениями перед потенциально опасными операциями.

## Контекст

В тестовом кластере используется Talos Linux `v1.13.5` со следующей схемой адресов:

| Назначение | Имя | Адрес |
| --- | --- | --- |
| Kubernetes API VIP | `k8s-api` | `192.168.2.210:6443` |
| Control plane | `k8s-master-01` | `192.168.2.211` |
| Control plane | `k8s-master-02` | `192.168.2.212` |
| Control plane | `k8s-master-03` | `192.168.2.213` |
| Worker | `k8s-worker-01` | `192.168.2.214` |
| Worker | `k8s-worker-02` | `192.168.2.215` |

В ходе настройки были выявлены типовые ошибки, которые нужно разобрать в документации:

- `talosctl` без явного `--talosconfig` пытался открыть `~/.talos/config`;
- активный контекст `my-cluster` не имел `endpoints` и `nodes`;
- в `talosconfig` накопились лишние контексты `talos-default*` с неправильным адресом `10.5.0.2`;
- задание всех пяти адресов в `nodes` приводило к пятикратному повторению результата `get members`;
- worker-конфиги были ошибочно построены patch-командой на основе `controlplane.yaml`, из-за чего worker-ноды получили `machine.type: controlplane` и вошли в etcd;
- возникли вопросы о назначении Kubernetes VIP, Talos API endpoints, сетевых offload-параметрах и освобождении дискового пространства.

Документация должна объяснять причины такого поведения, а не только перечислять команды.

## Цель

Создать практическое руководство, по которому администратор сможет:

- правильно подключаться к Talos-кластеру через локальный `talosconfig`;
- понимать разницу между `endpoints`, `nodes` и Kubernetes API VIP;
- просматривать и безопасно исправлять контексты `talosconfig`;
- получать сведения о составе кластера, дисках, сетевых интерфейсах, маршрутах, сервисах, процессах и контейнерах;
- использовать интерактивный dashboard, логи сервисов и сообщения ядра;
- проверять и применять machine configuration;
- правильно генерировать node-specific конфиги из `controlplane.yaml` и `worker.yaml`;
- безопасно исправить ошибочную роль worker-ноды, уже добавленной в etcd;
- диагностировать Ethernet offload features через `EthernetStatus` и настраивать их через `EthernetConfig`;
- диагностировать нехватку места на `EPHEMERAL` и выбрать между очисткой, обслуживанием etcd и расширением диска;
- собирать support bundle и выполнять базовые операции обслуживания;
- понимать, какие команды являются разрушительными и требуют отдельного подтверждения.

## Объем

- Создать основной материал `Kubernetes/talos-administration.md`.
- Обновить `Kubernetes/README.md` ссылкой на новый материал.
- Ориентировать команды на Talos Linux `v1.13.x`, отдельно отметить проверенную версию `v1.13.5`.
- Использовать `my-cluster` как пример имени контекста.
- Показать как полный синтаксис с `--talosconfig`, так и вариант с переменной `TALOSCONFIG`.
- Для команд, выполняемых на конкретной ноде, явно указывать `-n`.
- Для каждой изменяющей операции сначала давать read-only проверку или `--dry-run`, если он поддерживается.
- Для операций с etcd требовать snapshot, последовательную обработку нод и проверку кворума.
- Для reboot, upgrade, смены роли и обслуживания control-plane требовать выполнение по одной ноде.
- Ссылаться на официальную документацию Sidero Labs/Talos соответствующей версии.
- Не включать содержимое сертификатов, CA private keys, bootstrap tokens, secret values и полный вывод machine configuration.
- Обновить `TASK.md` и `LOG.md` при фактическом выполнении задачи.

## Вне объема

- Первичная установка Talos на bare metal или VM с нуля.
- Полная установка Kubernetes, Cilium, CSI, ingress controller или Argo CD.
- Проектирование production PKI и ротация CA.
- Автоматизация через Terraform, Ansible или GitOps.
- Выполнение `reset`, `wipe`, повторного `bootstrap`, `rotate-ca` или иных разрушительных операций на живом кластере.
- Фактическое изменение ролей нод, состава etcd, размеров дисков или версии Talos без отдельного задания и подтверждения.
- Публикация реального `talosconfig`, machine secrets или kubeconfig.

## Предварительные требования

- Установлен `talosctl`, совместимый с версией Talos на нодах.
- Есть локальный `talosconfig`, соответствующий нужному кластеру.
- Talos API на TCP/50000 доступен с рабочей станции.
- Для Kubernetes-проверок установлен `kubectl` и получен корректный kubeconfig.
- Администратор знает реальные IP control-plane и worker-нод.
- Перед операциями с etcd доступно место для snapshot.

## Предлагаемые файлы

- `Kubernetes/talos-administration.md` — основное руководство и эксплуатационный runbook.
- `Kubernetes/README.md` — ссылка на новый материал.
- `TASK.md` — текущее состояние задачи при выполнении.
- `LOG.md` — записи начала и завершения работы.

## Предлагаемая структура материала

1. Что такое Talos Linux и почему в нём нет SSH/shell.
2. Схема тестового кластера: VIP, control plane, workers и используемые порты.
3. Подготовка окружения: `TALOSCONFIG`, выбор context и проверка версии.
4. Устройство `talosconfig`: contexts, endpoints, nodes, роли сертификата и срок действия.
5. Разница между Talos endpoint, target node и Kubernetes API endpoint.
6. Почему Kubernetes VIP нельзя использовать как Talos API endpoint.
7. Просмотр, добавление, переключение и удаление контекстов.
8. Исправление пустых endpoints/nodes и проверка `config info`.
9. Почему несколько default nodes размножают вывод команды и когда указывать несколько `-n` осознанно.
10. Состав кластера: `get members`, интерпретация столбцов и проверка ролей.
11. Machine configuration: `validate`, `machineconfig patch`, `apply-config --dry-run`, `patch machineconfig --dry-run`, `edit machineconfig`.
12. Правильная генерация индивидуальных control-plane и worker-конфигов.
13. Исправление worker-ноды, ошибочно настроенной как control plane.
14. Безопасная работа с etcd: members, status, alarms, snapshot, leave, defrag.
15. Диски, volumes, mounts, filesystem usage и чтение файлов через Talos API.
16. Сеть: links, addresses, routes, resolvers, EthernetStatus, netstat и pcap.
17. Ethernet offload: изменяемые значения и значения с пометкой `[fixed]`.
18. Интерактивная консоль: dashboard, service logs, dmesg и отсутствие SSH.
19. Процессы, memory, cgroups, containers, stats и runtime images.
20. Kubernetes-доступ: получение kubeconfig и базовые проверки через `kubectl`.
21. Диагностика нехватки места на `EPHEMERAL` (`/var`).
22. Очистка неиспользуемых образов и завершённых pod'ов с оговорками по безопасности.
23. Обслуживание и дефрагментация etcd при `NOSPACE`.
24. Расширение виртуального диска и автоматический grow `EPHEMERAL`.
25. Reboot, shutdown, upgrade и rollback: порядок и ограничения.
26. Формирование support bundle.
27. Опасные команды и аварийный чек-лист.
28. Краткая шпаргалка ежедневных команд администратора.

## Обязательные примеры

### Подключение и настройка контекста

Показать команды:

```bash
export TALOSCONFIG="$PWD/talosconfig"

talosctl config contexts
talosctl config info
talosctl config context my-cluster

talosctl config endpoint \
  192.168.2.211 \
  192.168.2.212 \
  192.168.2.213

talosctl config node 192.168.2.211
```

Объяснить, что endpoints — реальные control-plane-адреса Talos API, а node — цель команды по умолчанию. VIP `192.168.2.210:6443` относится только к Kubernetes API.

### Базовая диагностика

Включить и пояснить:

```bash
talosctl get members
talosctl health
talosctl dashboard -n 192.168.2.214
talosctl service -n 192.168.2.214
talosctl logs kubelet -n 192.168.2.214 --tail 100
talosctl logs kubelet -n 192.168.2.214 --follow
talosctl dmesg -n 192.168.2.214
talosctl get rd
```

### Диски и сеть

Включить:

```bash
talosctl get disks -n 192.168.2.214
talosctl get volumestatuses -n 192.168.2.214
talosctl mounts -n 192.168.2.214
talosctl usage /var -n 192.168.2.214 --humanize --depth 2

talosctl get links -n 192.168.2.214
talosctl get addresses -n 192.168.2.214
talosctl get routes -n 192.168.2.214
talosctl get ethernetstatus enp0s1 -n 192.168.2.214 -o yaml
talosctl netstat -n 192.168.2.214
```

### Правильная генерация worker-конфигов

Показать ошибочный и правильный варианты:

```bash
# Ошибка: результат сохранит machine.type: controlplane
talosctl machineconfig patch controlplane.yaml \
  --patch @k8s-worker-01.patch \
  --output k8s-worker-01.yaml

# Правильно
talosctl machineconfig patch worker.yaml \
  --patch @k8s-worker-01.patch \
  --output k8s-worker-01.yaml
```

Добавить проверку `machine.type`, `validate` и `apply-config --dry-run`.

### Исправление ошибочной роли worker-ноды

Описать безопасную последовательность без автоматического выполнения:

1. Перегенерировать worker-конфиг из `worker.yaml`.
2. Проверить конфиг и dry-run.
3. Создать snapshot etcd.
4. Убедиться, что все участники etcd здоровы.
5. Обрабатывать только одну ошибочную worker-ноду за раз.
6. Выполнить для доступной ноды `talosctl etcd leave`.
7. Сразу применить правильный worker-конфиг с подходящим mode/reboot.
8. Дождаться возврата ноды и проверить `get members`, `etcd members`, `etcd status` и Kubernetes Node.
9. Только после успешной проверки переходить ко второй ноде.

Отдельно объяснить, почему `etcd leave` предпочтительнее `remove-member`, пока нода доступна.

### Ethernet offload

Показать документ:

```yaml
---
apiVersion: v1alpha1
kind: EthernetConfig
name: enp0s1
features:
  tx-udp_tnl-segmentation: false
  tx-udp_tnl-csum-segmentation: false
```

Объяснить, что `off [fixed]` означает уже выключенную функцию, состояние которой драйвер не позволяет изменить. Зафиксировать, что на всех пяти нодах тестового кластера оба параметра наблюдались как `off [fixed]`, поэтому применение документа там не требуется.

### Нехватка места

Добавить runbook:

1. Проверить mounts, volumes и usage `/var`.
2. Проверить `DiskPressure` в Kubernetes.
3. Просмотреть CRI/system images.
4. Найти завершённые и failed pod'ы и большие workload-данные.
5. На control-plane проверить размер, фактическое использование и alarms etcd.
6. Делать defrag только по одной etcd-ноде и после snapshot.
7. Для VM предпочитать увеличение виртуального диска; объяснить `EPHEMERAL` и `grow: true`.
8. Для worker при необходимости использовать cordon/drain и пересоздание.
9. Не использовать `reset` или `wipe` как способ обычной очистки.

## Требования к стилю

- Писать по-русски, простым инженерным языком.
- Сначала объяснять назначение команды, затем показывать копируемый пример.
- После изменяющих команд указывать проверку результата.
- Явно различать read-only, изменяющие и разрушительные операции.
- Для опасных шагов использовать заметные предупреждения.
- Не создавать впечатление, что `nodes` всегда должен содержать все ноды кластера.
- Не использовать VIP как Talos API endpoint даже если TCP/50000 технически отвечает.
- Не рекомендовать SSH: у Talos штатный административный интерфейс — Talos API.
- Не предлагать ручное удаление файлов из `/var` через debug container как стандартный способ очистки.
- Не показывать секретные поля machine configuration и `talosconfig`.
- Команды должны быть совместимы с Talos `v1.13.x` и сверены с `talosctl --help` и официальной документацией.

## Критерии готовности

- [x] Создан `Kubernetes/talos-administration.md`.
- [x] Описана схема тестового кластера и роли всех адресов.
- [x] Объяснена разница между Kubernetes VIP, Talos endpoints и target nodes.
- [x] Покрыта настройка и очистка контекстов `talosconfig`.
- [x] Объяснена причина повторяющегося вывода при нескольких default nodes.
- [x] Добавлена ежедневная шпаргалка администратора.
- [x] Покрыты сервисы, логи, dashboard, ресурсы, процессы и контейнеры.
- [x] Покрыты диски, volumes, сеть, EthernetStatus, netstat и pcap.
- [x] Добавлены безопасные процедуры machine configuration и dry-run.
- [x] Разобрана ошибка генерации worker-конфига из `controlplane.yaml`.
- [x] Добавлен безопасный runbook перевода ошибочного control-plane member в worker.
- [x] Добавлены snapshot, status, alarms, leave и defrag для etcd.
- [x] Добавлен runbook при заполнении `EPHEMERAL`.
- [x] Все опасные команды снабжены предупреждениями.
- [x] В материале отсутствуют private keys, tokens и другие секреты.
- [x] Все внешние ссылки ведут на официальную документацию Talos/Sidero Labs.
- [x] `Kubernetes/README.md` обновлён ссылкой на материал.
- [x] `TASK.md` и `LOG.md` обновлены при выполнении.

## Вопросы

- Материал оставлен одной связной страницей с оглавлением. При дальнейшем росте его можно разделить на `talosctl-basics.md`, `talos-etcd-runbook.md` и `talos-storage-runbook.md`.
- Команды сверены с локальным `talosctl v1.13.5`, его встроенной справкой и официальной документацией Talos `v1.13`. На тестовом кластере команды не выполнялись, так как доступ и отдельное разрешение на живые операции в задаче не предоставлены.

## Блокеры

- Нет.

## Последнее состояние

Создан `Kubernetes/talos-administration.md` с практическим руководством по Talos Linux `v1.13.x` и `talosctl`: подключение, contexts, endpoints/nodes, диагностика, machine configuration, исправление ошибочной роли worker, etcd, disks, network, Ethernet offload, logs, runtime, `EPHEMERAL`, lifecycle и support bundle. Индекс Kubernetes и служебные файлы обновлены. Задача завершена без выполнения изменяющих команд на кластере.

## Связанные записи лога

- `LOG.md`: 2026-08-17 20:16 - TASK_018 - in_progress
- `LOG.md`: 2026-08-17 20:16 - TASK_018 - done
