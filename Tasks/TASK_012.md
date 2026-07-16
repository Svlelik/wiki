# TASK_012

## Заголовок

Материалы по базовым командам Ansible

## Статус

`done`

## Кратко

Нужно подготовить несколько отдельных заметок в разделе `Ansible`: установка Ansible в Python venv, запуск playbook через `ansible-playbook` и диагностика типовой SSH-ошибки с `Host key verification failed` и `ssh_askpass`.

## Контекст

В wiki есть раздел `Ansible`, но он пока не наполнен практическими материалами. Из исходного текста нужно выделить команды и оформить их как отдельные статьи, чтобы быстро возвращаться к базовым сценариям: установка инструмента, запуск playbook и исправление проблем подключения к хостам.

## Цель

Создать набор практических заметок по Ansible с командами, пояснениями и минимальными примерами файлов, которые нужны для запуска playbook и диагностики SSH-подключения.

## Объем

- Создать отдельный материал про установку Ansible в Python virtual environment.
- Описать установку системных пакетов `python3-venv` и `python3-pip`.
- Показать создание и активацию `venv_ansible`.
- Показать обновление `pip`, установку `ansible`, проверку через `ansible --version` и выход через `deactivate`.
- Создать отдельный материал про запуск playbook через `ansible-playbook`.
- Добавить базовую команду запуска с inventory-файлом: `ansible-playbook -i hosts.ini site.yml`.
- Описать полезные флаги: `--syntax-check`, `--check`, `--ask-become-pass`, `--tags`, `--limit`.
- Добавить минимальные примеры `hosts.ini` и `site.yml`.
- Создать отдельный материал про диагностику SSH-ошибок при запуске Ansible.
- Разобрать ошибку `Host key verification failed`.
- Разобрать сообщение `ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or directory`.
- Показать быстрый способ с `ANSIBLE_HOST_KEY_CHECKING=False` для тестовой среды.
- Показать настройку `host_key_checking = False` в `ansible.cfg` с предупреждением о рисках.
- Показать безопасный способ через ручное добавление хоста в `known_hosts` командой `ssh user@host`.
- Показать настройку SSH-ключей через `ssh-copy-id`.
- Показать установку `ssh-askpass`, если действительно нужен интерактивный ввод пароля.
- Добавить отдельный пример `ansible.cfg` для проекта.
- Обновить `Ansible/README.md` ссылками на новые материалы.

## Вне объема

- Полный курс по Ansible.
- Подробное устройство inventory, group_vars, host_vars и ролей.
- Ansible Galaxy collections как отдельная большая тема.
- Настройка динамического inventory.
- Vault, шифрование секретов и secret management.
- CI/CD-запуск Ansible.
- Production-hardening SSH и централизованное управление ключами.

## Входные данные

- [TASK.md](../TASK.md)
- [Ansible/README.md](../Ansible/README.md)
- Исходный текст с командами установки Ansible, запуска playbook и диагностики SSH-ошибки
- Документация Ansible по installation, inventory и `ansible-playbook`

## Предлагаемые файлы

- `Ansible/install-venv.md` - установка Ansible в Python venv.
- `Ansible/run-playbook.md` - запуск playbook и полезные флаги `ansible-playbook`.
- `Ansible/ssh-troubleshooting.md` - диагностика SSH-подключения, host key checking, `known_hosts`, `ssh_askpass`, SSH-ключи.
- `Ansible/ansible.cfg.example` - пример проектного `ansible.cfg`.
- `Ansible/hosts.ini.example` - минимальный пример inventory.
- `Ansible/site.yml.example` - минимальный пример playbook.

## Шаги

1. Подготовить структуру будущих материалов в разделе `Ansible`.
2. Создать статью `Ansible/install-venv.md` с установкой Ansible в venv.
3. Создать статью `Ansible/run-playbook.md` с запуском playbook и флагами.
4. Создать статью `Ansible/ssh-troubleshooting.md` с разбором ошибки подключения по SSH.
5. Добавить примеры `ansible.cfg.example`, `hosts.ini.example` и `site.yml.example`.
6. Обновить `Ansible/README.md`, чтобы он ссылался на все новые файлы.
7. Обновить `TASK.md` и `LOG.md` после завершения.
8. После завершения перенести `TASK_012.md` в каталог `Tasks/`.

## Критерии готовности

- [x] Создан материал `Ansible/install-venv.md`.
- [x] В материале по установке есть команды `apt`, `python3 -m venv`, `source`, `pip install`, `ansible --version`, `deactivate`.
- [x] Создан материал `Ansible/run-playbook.md`.
- [x] В материале по запуску есть команда `ansible-playbook -i hosts.ini site.yml`.
- [x] Описаны флаги `--syntax-check`, `--check`, `--ask-become-pass`, `--tags`, `--limit`.
- [x] Создан материал `Ansible/ssh-troubleshooting.md`.
- [x] В диагностике разобраны `Host key verification failed` и `ssh_askpass`.
- [x] Описаны варианты с `ANSIBLE_HOST_KEY_CHECKING=False`, `ansible.cfg`, `known_hosts`, `ssh-copy-id` и `ssh-askpass`.
- [x] Добавлены примеры `ansible.cfg.example`, `hosts.ini.example` и `site.yml.example`.
- [x] `Ansible/README.md` обновлен ссылками на новые материалы.
- [x] В `TASK.md` и `LOG.md` отражен статус задачи.

## Вопросы

- Делать команды установки только для Ubuntu/Debian или добавить варианты для RHEL/CentOS?
- Нужен ли отдельный материал про структуру Ansible-проекта: `inventory`, `playbooks`, `roles`, `group_vars`?
- Стоит ли включить отдельный блок про `--ask-pass` и отличие SSH-пароля от become-пароля?
- Нужен ли пример подключения к хосту `pg-preprod-serv` или оставить нейтральные имена вроде `web-01`?

## Блокеры

- Нет

## Последнее состояние

Созданы материалы `Ansible/install-venv.md`, `Ansible/run-playbook.md`, `Ansible/ssh-troubleshooting.md`, а также примеры `Ansible/ansible.cfg.example`, `Ansible/hosts.ini.example`, `Ansible/site.yml.example`. `Ansible/README.md` обновлен ссылками. Задача завершена.

## Связанные записи лога

- `LOG.md`: 2026-07-16 10:47 - TASK_012 - done
- `LOG.md`: 2026-07-16 10:43 - TASK_012 - todo
