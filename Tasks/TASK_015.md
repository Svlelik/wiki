# TASK_015

## Заголовок

Инструкция по смене Cilium Gateway VIP и hostname Argo CD

## Статус

`done`

## Кратко

Нужно зафиксировать в разделе `Kubernetes` воспроизводимый runbook выполненного переключения кластера `kubernetes-admin@k8s-dev`: VIP Gateway `192.168.215.9 -> 192.168.215.18`, hostname Argo CD `argocd-talos-dev.oro.moscow -> argocd-dev.oro.moscow`, а также диагностику и исправление зависания `argocd-repo-server` в `Init` на скачивании `kubectl` с `dl.k8s.io`.

## Контекст

Cilium как CNI и адрес ноды `192.168.215.17` не менялись. Внешний VIP — это LoadBalancer-адрес Gateway `cilium-gateway/ingress`, который задаётся `CiliumLoadBalancerIPPool` и полем `spec.addresses` у Gateway. L2-анонс идёт на `ens192` для всех LB IP, без жёсткой привязки к конкретному адресу.

После смены VIP и hostname `helm upgrade` Argo CD пересоздал `argocd-repo-server`. Init-контейнер `download-tools` завис на `wget` бинарника `kubectl` с `dl.k8s.io` (Fastly): GitHub для helm-secrets и sops был доступен, а `dl.k8s.io` отвечал таймаутом. Init исправлен: `kubectl` берётся из Alpine, у `wget` заданы timeout и retries.

## Цель

Создать безопасную русскоязычную инструкцию, по которой можно:

- понять, какие объекты задают VIP Gateway и hostname Argo CD;
- пересадить VIP без переустановки Cilium;
- сменить hostname HTTPRoute и `configs.cm.url` Argo CD;
- проверить новый VIP и Host, а также убедиться, что старые адрес и имя больше не обслуживаются;
- диагностировать зависание `argocd-repo-server` в `Init:1/2`;
- убрать зависимость init от `dl.k8s.io`;
- не забыть DNS и redirect URI Keycloak.

## Объем

- Описать, что меняется и что трогать не нужно.
- Зафиксировать файлы инфраструктурного репозитория `talos-dev`.
- Описать порядок смены пула и Gateway при допустимом downtime.
- Описать смену HTTPRoute и Helm-релиза Argo CD.
- Добавить проверки Gateway, Service, HTTP/HTTPS и ConfigMap `url`.
- Описать внешние шаги: DNS A-запись и Keycloak redirect URI.
- Разобрать зависание `download-tools` на `dl.k8s.io`.
- Показать исправленный init без публикации секретов из `argocd/values.yaml`.
- Обновить индекс раздела `Kubernetes`.

## Вне объема

- Повторное выполнение cutover на живом кластере.
- Изменение DNS и клиента Keycloak из этой wiki-задачи.
- Переустановка Cilium, смена node IP и `k8sServiceHost`.
- Публикация паролей, OIDC client secret и прочих credential из Helm values.
- Обновление исторического runbook `talos-cilium-1.20-grpc-web-migration.md` целиком; допустима только ссылка на актуальные VIP и hostname.

## Входные данные

- Выполненный cutover кластера `kubernetes-admin@k8s-dev` 2026-08-17.
- Инфраструктурный репозиторий `talos-dev`.
- [Kubernetes/README.md](../Kubernetes/README.md).
- [Kubernetes/talos-cilium-1.20-grpc-web-migration.md](../Kubernetes/talos-cilium-1.20-grpc-web-migration.md).
- [TASK.md](../TASK.md).
- [LOG.md](../LOG.md).

## Предлагаемые файлы

- `Kubernetes/cilium-vip-and-argocd-hostname.md` - основной runbook.
- `Kubernetes/README.md` - ссылка на новый материал.
- `TASK.md` - состояние задачи.
- `LOG.md` - журнал начала и завершения.

## Шаги

1. Зафиксировать задачу и стартовую запись в `LOG.md`.
2. Подготовить структуру runbook и безопасные переменные окружения.
3. Описать смену VIP: пул, Gateway, проверки, отказ старого адреса.
4. Описать смену hostname: HTTPRoute, Helm values, проверки Host.
5. Описать DNS и Keycloak как обязательные внешние шаги.
6. Описать диагностику `Init` у `argocd-repo-server` и исправление `download-tools`.
7. Добавить rollback и фактические результаты 2026-08-17.
8. Обновить индекс Kubernetes, задачу и журнал.
9. После завершения перенести задачу в `Tasks/`.

## Критерии готовности

- [x] Создан русскоязычный runbook в разделе `Kubernetes`.
- [x] Все команды используют placeholders или переменные окружения.
- [x] Реальные secret values и credential отсутствуют.
- [x] Изменяющие команды явно помечены.
- [x] Описаны VIP cutover и hostname cutover.
- [x] Описаны DNS и Keycloak как внешние зависимости.
- [x] Описаны зависание `download-tools` и исправление без `dl.k8s.io`.
- [x] Добавлены фактические результаты проверки.
- [x] Обновлены `Kubernetes/README.md`, `TASK.md` и `LOG.md`.

## Вопросы

- Переведена ли A-запись `argocd-dev.oro.moscow` на `192.168.215.18`?
- Обновлён ли redirect URI клиента Keycloak `argocd-dev`?

## Блокеры

- Нет.

## Последнее состояние

Создан `Kubernetes/cilium-vip-and-argocd-hostname.md` с runbook смены VIP
Gateway, hostname Argo CD, внешних шагов DNS/Keycloak, диагностики Init
`argocd-repo-server` и исправления `download-tools` без `dl.k8s.io`. В
исторический runbook миграции Cilium 1.20 добавлена ссылка на актуальные VIP
и hostname. Индекс Kubernetes обновлён. Задача завершена и перенесена в
`Tasks/`.

## Связанные записи лога

- `LOG.md`: 2026-08-17 16:29 - TASK_015 - in_progress
- `LOG.md`: 2026-08-17 16:36 - TASK_015 - done
