# TASK_014

## Заголовок

Инструкция по миграции Talos/Kubernetes/Cilium и исправлению gRPC-web для Argo CD

## Статус

`done`

## Кратко

Нужно зафиксировать в разделе `Kubernetes` воспроизводимый runbook выполненной миграции кластера `kubernetes-admin@k8s-dev`: Kubernetes `1.32.3 -> 1.35.7`, Cilium `1.19.6 -> 1.20.0`, Gateway API `v1.6.1`, отключение преобразования gRPC-web и возврат к общему HTTPS listener с `HTTPRoute` для Argo CD.

## Контекст

Argo CD `v3.5.0` был опубликован через Cilium Gateway. На Cilium `1.19.6` Gateway завершал TLS и преобразовывал gRPC-web в native gRPC, тогда как Argo CD на HTTP-порту ожидал gRPC-web. В результате UI и REST работали, но запрос `/session.SessionService/Create` возвращал `404`.

Временное решение с TLS passthrough потребовало отдельного `TLSRoute` и hostname-scoped HTTPS listeners из-за `ProtocolConflict`. Целевая миграция обновила Kubernetes и Cilium, отключила gRPC-web translation через `CiliumGatewayClassConfig` и вернула один общий HTTPS listener.

Прямой Talos API `192.168.215.17:50000` был недоступен с рабочей станции. Для выполнения preflight, snapshot и обновления использовался временный host-network pod с краткоживущим Kubernetes Secret, содержащим расшифрованный `talosconfig`. В инструкции этот процесс должен быть обезличен и сопровождаться предупреждениями и обязательным cleanup.

## Цель

Создать безопасную русскоязычную инструкцию, по которой можно:

- понять причину исходного `404` для gRPC-web;
- подготовить rollback и etcd snapshot;
- выполнить последовательное обновление Kubernetes на Talos;
- обновить Gateway API и Cilium;
- отключить gRPC-web translation;
- упростить Gateway и вернуть Argo CD на HTTP backend;
- проверить результат и удалить временные административные ресурсы.

## Объем

- Описать preflight, backup и точки остановки.
- Описать обход недоступного Talos API через временный host-network pod без публикации credential.
- Добавить команды snapshot, сжатия, копирования и проверки.
- Добавить dry-run и upgrade для `1.33.13`, `1.34.10`, `1.35.7`.
- Зафиксировать обновление Kubernetes image pins в Git.
- Описать Gateway API experimental bundle `v1.6.1`.
- Описать Cilium preflight и upgrade `1.19.6 -> 1.20.0` с `upgradeCompatibility: "1.19"`.
- Добавить `CiliumGatewayClassConfig` и `GatewayClass.parametersRef`.
- Описать переход с TLS passthrough и hostname-scoped listeners на общий HTTPS listener и `HTTPRoute`.
- Описать Argo CD `server.insecure: true` и согласованное переключение с rollback.
- Добавить проверки Kubernetes, Cilium, Gateway, routes, HTTPS endpoints и gRPC-web.
- Описать cleanup временных pod/Secret и сохранение `argocd-server-tls` как rollback-ресурса.
- Обновить индекс раздела `Kubernetes`.

## Вне объема

- Повторное выполнение миграции на живом кластере.
- Изменение firewall или маршрутизации для прямого доступа к Talos API.
- Публикация реального `talosconfig`, ключей, токенов, паролей или содержимого etcd snapshot.
- Удаление `argocd-server-tls`.
- Изменение CI/CD репозитория с образом Argo CD CLI.

## Входные данные

- Выполненная миграция кластера `kubernetes-admin@k8s-dev`.
- Инфраструктурный репозиторий `talos-dev`.
- [Kubernetes/README.md](../Kubernetes/README.md).
- [TASK.md](../TASK.md).
- [LOG.md](../LOG.md).

## Предлагаемые файлы

- `Kubernetes/talos-cilium-1.20-grpc-web-migration.md` - основной runbook.
- `Kubernetes/README.md` - ссылка на новый материал.
- `TASK.md` - состояние задачи.
- `LOG.md` - журнал начала и завершения.

## Шаги

1. Зафиксировать задачу и стартовую запись в `LOG.md`.
2. Подготовить структуру runbook и безопасные переменные окружения.
3. Описать диагностику исходной ошибки.
4. Описать preflight, rollback и etcd snapshot.
5. Описать временный доступ к Talos API и его cleanup.
6. Описать последовательные Kubernetes upgrades и проверки.
7. Описать Gateway API и Cilium upgrade.
8. Описать конфигурацию отключения gRPC-web translation.
9. Описать переключение Gateway и Argo CD с rollback.
10. Добавить итоговые проверки и наблюдавшиеся результаты.
11. Обновить индекс Kubernetes, задачу и журнал.
12. После завершения перенести задачу в `Tasks/`.

## Критерии готовности

- [x] Создан русскоязычный runbook в разделе `Kubernetes`.
- [x] Все команды используют placeholders или переменные окружения.
- [x] Реальные secret values и credential отсутствуют.
- [x] Высокорисковые и изменяющие команды явно помечены.
- [x] Описан временный host-network pod и обязательный cleanup.
- [x] Описан и проверен etcd snapshot.
- [x] Описаны все три Kubernetes minor hops.
- [x] Описаны Gateway API `v1.6.1` и Cilium `1.20.0`.
- [x] Описано отключение gRPC-web translation.
- [x] Описан переход на общий HTTPS listener и Argo CD HTTPRoute.
- [x] Добавлена согласованная rollback-стратегия.
- [x] Добавлены фактические результаты итоговой проверки.
- [x] Обновлены `Kubernetes/README.md`, `TASK.md` и `LOG.md`.

## Вопросы

- Нужно ли отдельно восстанавливать прямой доступ рабочей станции к Talos API `:50000` через firewall/VPN?
- Где должен храниться долговременный зашифрованный etcd backup после временной проверки в `/tmp`?

## Блокеры

- Нет.

## Последнее состояние

Создан `Kubernetes/talos-cilium-1.20-grpc-web-migration.md` с полным
безопасным runbook выполненной миграции: preflight, временный доступ к Talos
API, etcd snapshot, последовательные Kubernetes upgrades, Gateway API и Cilium
upgrade, отключение gRPC-web translation, переключение Argo CD, rollback,
проверки и cleanup. Индекс Kubernetes обновлен, Markdown основного материала
проверен. Задача завершена.

## Связанные записи лога

- `LOG.md`: 2026-08-14 16:08 - TASK_014 - in_progress
- `LOG.md`: 2026-08-14 16:12 - TASK_014 - done
