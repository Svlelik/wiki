# Запуск Ansible playbook

Для запуска playbook используется команда `ansible-playbook`. Обычно ей передают inventory-файл с хостами и YAML-файл playbook.

## Базовый запуск

Пример:

```bash
ansible-playbook -i hosts.ini site.yml
```

Где:

- `hosts.ini` - inventory с группами и хостами.
- `site.yml` - playbook со списком plays и tasks.

Если Ansible установлен в Python venv, сначала активируйте окружение:

```bash
source venv_ansible/bin/activate
```

## Проверка синтаксиса

Проверить YAML и структуру playbook без выполнения задач:

```bash
ansible-playbook -i hosts.ini site.yml --syntax-check
```

Эта команда не подключается к хостам для выполнения задач, а только проверяет, что playbook можно разобрать.

## Dry run

Показать, какие изменения Ansible планирует сделать, без фактического применения:

```bash
ansible-playbook -i hosts.ini site.yml --check
```

Не все модули полностью поддерживают check mode. Для критичных изменений результат `--check` стоит воспринимать как предварительную оценку.

## Запрос become-пароля

Если tasks используют `become: true` и на целевых хостах нужен пароль для `sudo`, добавьте:

```bash
ansible-playbook -i hosts.ini site.yml --ask-become-pass
```

Короткая форма:

```bash
ansible-playbook -i hosts.ini site.yml -K
```

`--ask-become-pass` спрашивает пароль для повышения привилегий, а не SSH-пароль для подключения.

## Запуск по тегам

Если в playbook настроены tags, можно выполнить только часть задач:

```bash
ansible-playbook -i hosts.ini site.yml --tags "nginx,packages"
```

Или пропустить задачи с определенными тегами:

```bash
ansible-playbook -i hosts.ini site.yml --skip-tags "restart"
```

## Ограничение по хостам

Запустить playbook только для группы или хоста из inventory:

```bash
ansible-playbook -i hosts.ini site.yml --limit "webservers"
ansible-playbook -i hosts.ini site.yml --limit "web-01"
```

Перед изменяющим запуском полезно проверить выборку:

```bash
ansible -i hosts.ini webservers --list-hosts
ansible -i hosts.ini all --limit "web-01" --list-hosts
```

## Повышенная подробность

Для диагностики добавьте `-v`, `-vv` или `-vvv`:

```bash
ansible-playbook -i hosts.ini site.yml -vv
```

`-vvv` часто полезен при SSH-проблемах, потому что показывает больше деталей подключения.

## Минимальный inventory

```ini
[webservers]
web-01 ansible_host=192.0.2.10 ansible_user=ubuntu
web-02 ansible_host=192.0.2.11 ansible_user=ubuntu
```

## Минимальный playbook

```yaml
---
- name: Check hosts
  hosts: webservers
  gather_facts: true

  tasks:
    - name: Ping host
      ansible.builtin.ping:
```

Запуск:

```bash
ansible-playbook -i hosts.ini site.yml
```

## Шпаргалка

| Действие | Команда |
| --- | --- |
| Запустить playbook | `ansible-playbook -i hosts.ini site.yml` |
| Проверить синтаксис | `ansible-playbook -i hosts.ini site.yml --syntax-check` |
| Dry run | `ansible-playbook -i hosts.ini site.yml --check` |
| Запросить become-пароль | `ansible-playbook -i hosts.ini site.yml --ask-become-pass` |
| Запустить теги | `ansible-playbook -i hosts.ini site.yml --tags "nginx,packages"` |
| Ограничить хосты | `ansible-playbook -i hosts.ini site.yml --limit "webservers"` |
| Включить подробный вывод | `ansible-playbook -i hosts.ini site.yml -vv` |
