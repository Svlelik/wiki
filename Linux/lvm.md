# Работа с LVM в Linux

LVM (`Logical Volume Manager`) позволяет гибко управлять дисками и файловыми системами: объединять физические диски в группы, создавать логические тома, увеличивать размер разделов и переносить данные между носителями.

Основные сущности LVM:

- `PV` (`Physical Volume`) - физический том, обычно диск или раздел.
- `VG` (`Volume Group`) - группа томов, объединяющая один или несколько `PV`.
- `LV` (`Logical Volume`) - логический том, который используется как обычный блочный девайс.

## Базовая схема

```text
Disk/Partition -> PV -> VG -> LV -> Filesystem -> Mount point
```

## Проверка текущего состояния

Показать блочные устройства:

```bash
lsblk
```

Показать физические тома:

```bash
pvs
pvdisplay
```

Показать группы томов:

```bash
vgs
vgdisplay
```

Показать логические тома:

```bash
lvs
lvdisplay
```

## Создание LVM с нуля

Допустим, есть диск `/dev/sdb`, который нужно отдать под LVM.

### 1. Создать физический том

```bash
sudo pvcreate /dev/sdb
```

### 2. Создать группу томов

```bash
sudo vgcreate vg_data /dev/sdb
```

### 3. Создать логический том

Пример создания тома размером 20 ГБ:

```bash
sudo lvcreate -L 20G -n lv_data vg_data
```

Пример создания тома на все свободное место:

```bash
sudo lvcreate -l 100%FREE -n lv_data vg_data
```

### 4. Создать файловую систему

Для `ext4`:

```bash
sudo mkfs.ext4 /dev/vg_data/lv_data
```

Для `xfs`:

```bash
sudo mkfs.xfs /dev/vg_data/lv_data
```

### 5. Смонтировать том

```bash
sudo mkdir -p /data
sudo mount /dev/vg_data/lv_data /data
```

Проверка:

```bash
df -h
```

## Автомонтирование через `/etc/fstab`

Получить UUID:

```bash
sudo blkid /dev/vg_data/lv_data
```

Пример записи в `/etc/fstab`:

```fstab
UUID=<uuid> /data ext4 defaults 0 2
```

После изменения проверить:

```bash
sudo mount -a
```

## Увеличение размера логического тома

### 1. Проверить свободное место в группе

```bash
vgs
```

### 2. Увеличить логический том

Добавить 10 ГБ:

```bash
sudo lvextend -L +10G /dev/vg_data/lv_data
```

Использовать все свободное место:

```bash
sudo lvextend -l +100%FREE /dev/vg_data/lv_data
```

### 3. Расширить файловую систему

Для `ext4`:

```bash
sudo resize2fs /dev/vg_data/lv_data
```

Для `xfs`:

```bash
sudo xfs_growfs /data
```

Удобный вариант для `ext4`:

```bash
sudo lvextend -r -L +10G /dev/vg_data/lv_data
```

Опция `-r` сразу расширяет файловую систему после увеличения тома.

## Добавление нового диска в существующую группу

Создать новый `PV`:

```bash
sudo pvcreate /dev/sdc
```

Добавить его в группу:

```bash
sudo vgextend vg_data /dev/sdc
```

Проверить:

```bash
vgs
pvs
```

## Уменьшение размера LVM

С уменьшением нужно быть осторожным: ошибка здесь приводит к потере данных.

Для `xfs` уменьшение файловой системы не поддерживается. Для `ext4` общий порядок такой:

1. Размонтировать файловую систему.
2. Проверить файловую систему.
3. Уменьшить файловую систему.
4. Уменьшить логический том.

Пример для `ext4`:

```bash
sudo umount /data
sudo e2fsck -f /dev/vg_data/lv_data
sudo resize2fs /dev/vg_data/lv_data 15G
sudo lvreduce -L 15G /dev/vg_data/lv_data
sudo mount /dev/vg_data/lv_data /data
```

Без полной уверенности такие операции лучше не выполнять.

## Удаление логического тома

Сначала размонтировать:

```bash
sudo umount /data
```

Удалить логический том:

```bash
sudo lvremove /dev/vg_data/lv_data
```

Если нужно удалить группу томов:

```bash
sudo vgremove vg_data
```

Если нужно удалить физический том:

```bash
sudo pvremove /dev/sdb
```

## Перенос данных с одного физического тома на другой

Если в `VG` несколько физических томов, можно переместить экстенты:

```bash
sudo pvmove /dev/sdb /dev/sdc
```

После переноса можно убрать диск из группы:

```bash
sudo vgreduce vg_data /dev/sdb
```

## Полезные команды

- `lsblk` - показать диски и точки монтирования.
- `pvs`, `vgs`, `lvs` - краткая информация по LVM.
- `pvdisplay`, `vgdisplay`, `lvdisplay` - подробная информация.
- `lvextend` - увеличить логический том.
- `lvreduce` - уменьшить логический том.
- `vgextend` - добавить новый `PV` в группу.
- `pvmove` - перенести данные между физическими томами.

## Практические примеры

Создать том 50 ГБ:

```bash
sudo lvcreate -L 50G -n lv_backup vg_data
```

Создать том на весь свободный объем:

```bash
sudo lvcreate -l 100%FREE -n lv_archive vg_data
```

Увеличить том и файловую систему:

```bash
sudo lvextend -r -L +20G /dev/vg_data/lv_backup
```

Найти информацию по всем томам:

```bash
sudo lvs -a -o +devices
```

## Короткая памятка

```bash
sudo pvcreate /dev/sdb
sudo vgcreate vg_data /dev/sdb
sudo lvcreate -L 20G -n lv_data vg_data
sudo mkfs.ext4 /dev/vg_data/lv_data
sudo mount /dev/vg_data/lv_data /data
sudo lvextend -r -L +10G /dev/vg_data/lv_data
sudo vgextend vg_data /dev/sdc
sudo lvs
sudo vgs
sudo pvs
```
