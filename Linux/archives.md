# Работа с архивами в Linux

Архивы используют, чтобы собрать несколько файлов в один файл, сжать данные, перенести каталог или подготовить резервную копию.

В Linux чаще всего встречаются два подхода:

- `tar` собирает файлы и каталоги в один архив.
- `gzip`, `bzip2` и `xz` сжимают данные.

Поэтому форматы вроде `.tar.gz`, `.tar.bz2` и `.tar.xz` обычно означают: сначала файлы собрали через `tar`, потом сжали выбранным алгоритмом.

## Быстрая памятка по форматам

| Формат | Что это | Частая команда |
| --- | --- | --- |
| `.tar` | архив без сжатия | `tar -cf archive.tar dir/` |
| `.tar.gz`, `.tgz` | `tar` + `gzip` | `tar -czf archive.tar.gz dir/` |
| `.tar.bz2` | `tar` + `bzip2` | `tar -cjf archive.tar.bz2 dir/` |
| `.tar.xz` | `tar` + `xz` | `tar -cJf archive.tar.xz dir/` |
| `.zip` | zip-архив | `zip -r archive.zip dir/` |

## Основные опции tar

- `-c` - создать архив.
- `-x` - распаковать архив.
- `-t` - показать содержимое архива.
- `-f` - указать имя файла архива.
- `-v` - подробный вывод.
- `-z` - использовать `gzip`.
- `-j` - использовать `bzip2`.
- `-J` - использовать `xz`.
- `-C` - перейти в каталог перед распаковкой или добавлением файлов.

## Создание tar-архивов

Создать архив без сжатия:

```bash
tar -cf project.tar project/
```

Создать архив `.tar.gz`:

```bash
tar -czf project.tar.gz project/
```

Создать архив `.tgz`:

```bash
tar -czf project.tgz project/
```

Создать архив `.tar.bz2`:

```bash
tar -cjf project.tar.bz2 project/
```

Создать архив `.tar.xz`:

```bash
tar -cJf project.tar.xz project/
```

Добавить подробный вывод:

```bash
tar -czvf project.tar.gz project/
```

## Просмотр содержимого архива

Посмотреть содержимое `.tar`:

```bash
tar -tf project.tar
```

Посмотреть содержимое `.tar.gz`:

```bash
tar -tzf project.tar.gz
```

Посмотреть содержимое `.tar.bz2`:

```bash
tar -tjf project.tar.bz2
```

Посмотреть содержимое `.tar.xz`:

```bash
tar -tJf project.tar.xz
```

С подробной информацией:

```bash
tar -tvf project.tar
```

## Распаковка tar-архивов

Распаковать `.tar` в текущий каталог:

```bash
tar -xf project.tar
```

Распаковать `.tar.gz` или `.tgz`:

```bash
tar -xzf project.tar.gz
tar -xzf project.tgz
```

Распаковать `.tar.bz2`:

```bash
tar -xjf project.tar.bz2
```

Распаковать `.tar.xz`:

```bash
tar -xJf project.tar.xz
```

Распаковать в отдельную директорию:

```bash
mkdir -p /tmp/project
tar -xzf project.tar.gz -C /tmp/project
```

## Исключение файлов из архива

Исключить один каталог:

```bash
tar -czf project.tar.gz project/ --exclude="project/node_modules"
```

Исключить временные файлы по маске:

```bash
tar -czf project.tar.gz project/ --exclude="*.tmp"
```

Исключить несколько путей:

```bash
tar -czf project.tar.gz project/ \
  --exclude="project/.git" \
  --exclude="project/node_modules" \
  --exclude="project/tmp"
```

## Сжатие отдельных файлов

`gzip`, `bzip2` и `xz` обычно сжимают один файл. По умолчанию исходный файл заменяется сжатым.

Сжать файл через `gzip`:

```bash
gzip access.log
```

Распаковать:

```bash
gunzip access.log.gz
```

Оставить исходный файл при сжатии:

```bash
gzip -k access.log
```

Сжать файл через `bzip2`:

```bash
bzip2 dump.sql
```

Распаковать:

```bash
bunzip2 dump.sql.bz2
```

Сжать файл через `xz`:

```bash
xz dump.sql
```

Распаковать:

```bash
unxz dump.sql.xz
```

## Просмотр сжатых файлов без распаковки

Показать содержимое `.gz`:

```bash
zcat access.log.gz
```

Прочитать `.gz` через `less`:

```bash
zless access.log.gz
```

Показать содержимое `.bz2`:

```bash
bzcat dump.sql.bz2
```

Показать содержимое `.xz`:

```bash
xzcat dump.sql.xz
```

## Работа с zip-архивами

Создать zip-архив из файла:

```bash
zip notes.zip notes.txt
```

Создать zip-архив из каталога:

```bash
zip -r project.zip project/
```

Посмотреть содержимое zip-архива:

```bash
unzip -l project.zip
```

Распаковать zip-архив:

```bash
unzip project.zip
```

Распаковать в отдельную директорию:

```bash
unzip project.zip -d /tmp/project
```

Исключить каталог при создании zip-архива:

```bash
zip -r project.zip project/ -x "project/node_modules/*"
```

## Практические примеры

Заархивировать каталог с конфигурацией:

```bash
tar -czf etc-backup.tar.gz /etc
```

Заархивировать проект без `.git` и зависимостей:

```bash
tar -czf project.tar.gz project/ \
  --exclude="project/.git" \
  --exclude="project/node_modules"
```

Распаковать скачанный архив в `/opt/app`:

```bash
mkdir -p /opt/app
tar -xzf app.tar.gz -C /opt/app
```

Проверить, что лежит в архиве перед распаковкой:

```bash
tar -tzf app.tar.gz
```

Сжать SQL-дамп:

```bash
gzip -k dump.sql
```

Распаковать zip-архив в отдельный каталог:

```bash
unzip release.zip -d release
```

## Проверка целостности

Для архивов `gzip`, `bzip2` и `xz` можно проверить, читается ли сжатый файл.

Проверить `.gz`:

```bash
gzip -t access.log.gz
```

Проверить `.bz2`:

```bash
bzip2 -t dump.sql.bz2
```

Проверить `.xz`:

```bash
xz -t dump.sql.xz
```

Для zip-архива:

```bash
unzip -t project.zip
```

## Права и владельцы при распаковке

Обычный пользователь распаковывает файлы с доступными ему правами. Владелец файлов обычно становится текущим пользователем.

При распаковке от `root` можно сохранить владельцев из архива:

```bash
sudo tar -xpf backup.tar -C /
```

Опция `-p` просит `tar` сохранить права доступа. Использовать ее стоит аккуратно, особенно если архив получен из недоверенного источника.

## Короткая памятка

```bash
tar -cf archive.tar dir/
tar -czf archive.tar.gz dir/
tar -cjf archive.tar.bz2 dir/
tar -cJf archive.tar.xz dir/
tar -tf archive.tar
tar -tzf archive.tar.gz
tar -xf archive.tar
tar -xzf archive.tar.gz
tar -xzf archive.tar.gz -C /tmp/extract
tar -czf archive.tar.gz dir/ --exclude="dir/tmp"
gzip file.log
gunzip file.log.gz
bzip2 file.sql
bunzip2 file.sql.bz2
xz file.sql
unxz file.sql.xz
zip -r archive.zip dir/
unzip -l archive.zip
unzip archive.zip -d /tmp/extract
```
