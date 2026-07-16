# Диагностика SSH-подключения в Ansible

Ansible подключается к Linux-хостам по SSH. Поэтому ошибки на этапе `TASK [Gathering Facts]` часто связаны не с playbook, а с SSH-доступом, ключами хоста, пользователем или sudo.

Пример ошибки:

```text
TASK [Gathering Facts] ***********************************************************
[ERROR]: Task failed: Failed to connect to the host via ssh:
ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or directory
Host key verification failed.
fatal: [pg-preprod-serv]: UNREACHABLE! => {"changed": false, "unreachable": true}
```

В этом сообщении видны две разные проблемы:

- `Host key verification failed` - SSH не доверяет ключу целевого сервера.
- `ssh_askpass` - SSH попытался запросить пароль интерактивно, но не нашел программу для такого запроса.

## Проверить обычный SSH

Сначала проверьте подключение без Ansible:

```bash
ssh user@web-01
```

Если в inventory используется IP:

```bash
ssh user@192.0.2.10
```

Пока обычный SSH не работает стабильно, Ansible тоже не сможет подключиться.

## Host key verification failed

SSH хранит ключи известных серверов в `~/.ssh/known_hosts`. Если хоста там нет или ключ изменился, подключение может завершиться ошибкой.

Безопасный способ - один раз подключиться вручную и подтвердить ключ:

```bash
ssh user@web-01
```

SSH покажет fingerprint и спросит подтверждение. Если fingerprint ожидаемый, ответьте `yes`.

После этого повторите Ansible-команду:

```bash
ansible-playbook -i hosts.ini site.yml
```

## Быстрое отключение проверки host key

Для тестовой среды можно временно отключить проверку ключей:

```bash
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i hosts.ini site.yml
```

Это снижает безопасность: Ansible перестает проверять, что подключается именно к ожидаемому серверу. Для production такой режим лучше не использовать.

## Отключение проверки в ansible.cfg

Для локального тестового проекта можно добавить в `ansible.cfg`:

```ini
[defaults]
host_key_checking = False
```

После этого Ansible не будет требовать подтверждения SSH host key для запусков из этого проекта.

Если проект связан с production, лучше оставить `host_key_checking = True` и управлять `known_hosts` явно.

## ssh_askpass

Сообщение:

```text
ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or directory
```

означает, что SSH хотел запросить пароль, но не смог открыть helper-программу для ввода пароля.

Частые причины:

- используется SSH-пароль вместо ключа;
- запущен `ansible-playbook` с `-k` или `--ask-pass`;
- нет TTY или окружение не позволяет нормально спросить пароль;
- на машине не установлен `ssh-askpass`.

## Установить ssh-askpass

Если парольный ввод действительно нужен, установите пакет:

```bash
sudo apt update
sudo apt install ssh-askpass
```

После этого повторите запуск:

```bash
ansible-playbook -i hosts.ini site.yml --ask-pass
```

Для серверной автоматизации обычно удобнее и надежнее SSH-ключи.

## Настроить SSH-ключи

Создайте ключ, если его еще нет:

```bash
ssh-keygen -t ed25519 -C "ansible"
```

Скопируйте публичный ключ на хост:

```bash
ssh-copy-id user@web-01
```

Проверьте вход без пароля:

```bash
ssh user@web-01
```

После этого Ansible сможет подключаться без `--ask-pass`:

```bash
ansible-playbook -i hosts.ini site.yml
```

## Отличие SSH-пароля от become-пароля

SSH-пароль нужен для подключения к хосту:

```bash
ansible-playbook -i hosts.ini site.yml --ask-pass
```

Become-пароль нужен для `sudo`, если playbook использует `become: true`:

```bash
ansible-playbook -i hosts.ini site.yml --ask-become-pass
```

Можно использовать оба флага, но это обычно неудобно для регулярной автоматизации:

```bash
ansible-playbook -i hosts.ini site.yml --ask-pass --ask-become-pass
```

## Проверить доступ Ansible ad-hoc командой

До запуска большого playbook проверьте подключение:

```bash
ansible -i hosts.ini all -m ping
```

С конкретным пользователем:

```bash
ansible -i hosts.ini all -m ping -u ubuntu
```

С подробным SSH-выводом:

```bash
ansible -i hosts.ini all -m ping -vvv
```

## Что проверить в inventory

Пример:

```ini
[webservers]
web-01 ansible_host=192.0.2.10 ansible_user=ubuntu
```

Проверьте:

- `ansible_host` указывает на правильный DNS или IP.
- `ansible_user` существует на сервере.
- у пользователя есть доступ по SSH;
- если нужен `sudo`, пользователь имеет соответствующие права;
- локальный SSH-клиент доверяет host key сервера.

## Короткий порядок диагностики

1. Проверить `ssh user@host`.
2. Если host key не принят, добавить сервер в `known_hosts`.
3. Если нужен пароль, решить: временно использовать `--ask-pass` или перейти на SSH-ключи.
4. Проверить `ansible -i hosts.ini all -m ping -vvv`.
5. После успешного ping запускать `ansible-playbook`.
