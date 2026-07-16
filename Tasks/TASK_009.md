# TASK_009

## Заголовок

Описать устройство Docker и его основные компоненты

## Статус

`done`

## Кратко

Нужно подготовить материал о том, как Docker устроен внутри: из каких частей состоит Docker Engine, как взаимодействуют Docker CLI, Docker daemon, containerd, runc и shim, и что происходит при запуске контейнера.

## Контекст

В разделе `Docker` уже есть базовые команды, volumes и registry. Следующий логичный шаг - объяснить внутреннюю архитектуру Docker, чтобы команды воспринимались не как набор магии, а как работа конкретных компонентов Linux container stack.

## Цель

Создать отдельную заметку в каталоге `Docker`, которая простым языком объясняет архитектуру Docker и роль каждого основного компонента.

## Объем

- Объяснить, что такое Docker как платформа и что входит в Docker Engine.
- Описать роль Docker CLI и Docker daemon (`dockerd`).
- Объяснить, зачем нужен containerd и какие задачи он берет на себя.
- Описать runc как OCI runtime, который непосредственно создает контейнер.
- Объяснить, что такое containerd shim, зачем он нужен и почему контейнер может жить независимо от `dockerd`.
- Показать примерный путь команды `docker run` от CLI до запущенного процесса в контейнере.
- Кратко описать образы, layers, snapshots и storage driver.
- Кратко описать сети Docker: bridge, namespace, veth, iptables/nftables на концептуальном уровне.
- Кратко описать volumes и где они находятся в общей архитектуре.
- Добавить схему взаимодействия компонентов в текстовом виде или Mermaid.
- Добавить команды для просмотра компонентов на хосте: `ps`, `docker info`, `docker inspect`, `ctr`, `containerd`, `runc` при наличии.
- Отдельно отметить различия между Linux Docker Engine и Docker Desktop на macOS/Windows.

## Вне объема

- Подробное устройство Kubernetes CRI и kubelet.
- Глубокая настройка CNI, overlay-сетей и service mesh.
- Детальный разбор всех storage drivers.
- Написание собственного runtime или shim.
- Production-hardening Docker daemon и Docker host.
- Подробный разбор rootless Docker.

## Входные данные

- [TASK.md](../TASK.md)
- [TASK_TEMPLATE.md](../TASK_TEMPLATE.md)
- Каталог [Docker](../Docker)
- Базовая заметка [Docker/basic-commands.md](../Docker/basic-commands.md)
- Заметка по volumes [Docker/volumes.md](../Docker/volumes.md)
- Заметка по registry [Docker/registry.md](../Docker/registry.md)

## Шаги

1. Подготовить структуру материала об архитектуре Docker.
2. Создать отдельный файл в каталоге `Docker`, например `Docker/architecture.md`.
3. Описать компоненты Docker: CLI, `dockerd`, containerd, shim, runc, storage и network stack.
4. Добавить сценарий прохождения команды `docker run`.
5. Добавить схему взаимодействия компонентов.
6. Добавить диагностические команды для просмотра процессов и сведений о контейнерах.
7. Зафиксировать результат в `TASK.md` и `LOG.md`.

## Критерии готовности

- [x] Создан отдельный материал по устройству Docker.
- [x] Объяснены роли Docker CLI, `dockerd`, containerd, runc и shim.
- [x] Описано, что происходит при запуске контейнера через `docker run`.
- [x] Есть объяснение, зачем нужен shim и какую проблему он решает.
- [x] Есть краткое описание образов, layers, snapshots, сетей и volumes в архитектуре Docker.
- [x] Есть схема взаимодействия компонентов.
- [x] Есть практические команды для самостоятельной проверки на хосте.
- [x] В `TASK.md` и `LOG.md` отражен статус задачи.

## Вопросы

- Делать материал совсем вводным или добавить больше Linux-деталей про namespaces и cgroups?
- Нужна ли отдельная схема для Docker Desktop на macOS/Windows?
- Стоит ли вынести containerd, runc и OCI runtime spec в отдельную будущую задачу?

## Блокеры

- Нет

## Последнее состояние

Создан файл `Docker/architecture.md` с описанием архитектуры Docker: Docker CLI, `dockerd`, containerd, shim, runc, storage, network stack, volumes, путь команды `docker run`, схема компонентов и диагностические команды. Задача завершена.

## Связанные записи лога

- `LOG.md`: 2026-05-03 20:27 - TASK_009 - done
- `LOG.md`: 2026-05-03 00:00 - TASK_009 - todo
