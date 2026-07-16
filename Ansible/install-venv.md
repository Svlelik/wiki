# Установка Ansible в Python venv

Установка Ansible в виртуальное окружение Python помогает изолировать зависимости проекта от системных пакетов. Это удобно, когда для разных проектов нужны разные версии Ansible или Python-библиотек.

## Установка системных пакетов

Для Ubuntu/Debian установите пакеты для `venv` и `pip`:

```bash
sudo apt update
sudo apt install python3-venv python3-pip
```

## Создание виртуального окружения

Перейдите в директорию проекта и создайте окружение:

```bash
python3 -m venv venv_ansible
```

Активируйте его:

```bash
source venv_ansible/bin/activate
```

После активации команды `python`, `pip`, `ansible` и `ansible-playbook` будут использовать пакеты из `venv_ansible`.

## Установка Ansible

Обновите `pip`:

```bash
pip install --upgrade pip
```

Установите Ansible:

```bash
pip install ansible
```

Проверьте установку:

```bash
ansible --version
ansible-playbook --version
```

## Выход из окружения

Когда работа закончена, отключите виртуальное окружение:

```bash
deactivate
```

## Фиксация зависимостей

Если проект нужно воспроизводимо запускать на другой машине, сохраните зависимости:

```bash
pip freeze > requirements.txt
```

Установка из такого файла:

```bash
pip install -r requirements.txt
```

## Типовой порядок команд

```bash
sudo apt update
sudo apt install python3-venv python3-pip

python3 -m venv venv_ansible
source venv_ansible/bin/activate

pip install --upgrade pip
pip install ansible

ansible --version
deactivate
```
