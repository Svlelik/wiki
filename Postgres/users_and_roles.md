# Пользователи и роли в PostgreSQL

В PostgreSQL основной механизм управления доступом строится вокруг ролей. Отдельного технического объекта "пользователь" в повседневной работе почти нет: пользователь - это роль с правом входа в систему (`LOGIN`).

## Ключевая идея

- `ROLE` - сущность для объединения прав.
- `USER` - по сути удобная форма создания роли с атрибутом `LOGIN`.

На практике чаще используют команды:

```sql
CREATE ROLE app_readonly;
CREATE USER app_user WITH PASSWORD 'strong_password';
```

Команда `CREATE USER` эквивалентна созданию роли с `LOGIN`.

## Посмотреть существующие роли

В `psql`:

```sql
\du
```

Через системный каталог:

```sql
SELECT
    rolname,
    rolsuper,
    rolcreaterole,
    rolcreatedb,
    rolcanlogin
FROM pg_roles
ORDER BY rolname;
```

## Создание пользователя или роли

Создать роль без логина:

```sql
CREATE ROLE app_readonly;
```

Создать пользователя с логином и паролем:

```sql
CREATE ROLE app_user
WITH LOGIN
PASSWORD 'strong_password';
```

То же через короткую форму:

```sql
CREATE USER app_user WITH PASSWORD 'strong_password';
```

Создать пользователя с ограничением срока действия пароля:

```sql
CREATE ROLE app_user
WITH LOGIN
PASSWORD 'strong_password'
VALID UNTIL '2026-12-31 23:59:59';
```

## Изменение роли или пользователя

Сменить пароль:

```sql
ALTER ROLE app_user WITH PASSWORD 'new_strong_password';
```

Разрешить или запретить логин:

```sql
ALTER ROLE app_user LOGIN;
ALTER ROLE app_user NOLOGIN;
```

Выдать возможность создавать базы:

```sql
ALTER ROLE app_user CREATEDB;
```

Сделать роль суперпользователем стоит только в исключительных случаях:

```sql
ALTER ROLE admin_user SUPERUSER;
```

Отключить лишние привилегии:

```sql
ALTER ROLE app_user NOSUPERUSER NOCREATEDB NOCREATEROLE;
```

## Удаление пользователя или роли

Удалить роль:

```sql
DROP ROLE app_readonly;
```

Удалить пользователя:

```sql
DROP USER app_user;
```

Если роль еще владеет объектами или выдана другим ролям, сначала нужно:

- передать владение объектами;
- отозвать выданные права;
- убрать членство в других ролях.

## Выдача и отзыв прав

Выдать подключение к базе:

```sql
GRANT CONNECT ON DATABASE app_db TO app_user;
```

Выдать использование схемы:

```sql
GRANT USAGE ON SCHEMA public TO app_user;
```

Выдать чтение всех таблиц в схеме:

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_user;
```

Выдать доступ к последовательностям:

```sql
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
```

Выдать права на конкретную таблицу:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.orders
TO app_user;
```

Отозвать права:

```sql
REVOKE INSERT, UPDATE, DELETE
ON TABLE public.orders
FROM app_user;
```

Отозвать доступ к схеме:

```sql
REVOKE USAGE ON SCHEMA public FROM app_user;
```

## Права по умолчанию для новых объектов

Если в схеме регулярно создаются новые таблицы, полезно настроить default privileges:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO app_readonly;
```

Для последовательностей:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO app_readonly;
```

Это помогает не выдавать права вручную после каждой новой таблицы.

## Типовые роли

### Роль только для чтения

```sql
CREATE ROLE app_readonly;

GRANT CONNECT ON DATABASE app_db TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO app_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO app_readonly;
```

Выдать эти права конкретному пользователю:

```sql
CREATE USER analyst_user WITH PASSWORD 'strong_password';
GRANT app_readonly TO analyst_user;
```

### Роль для администрирования приложения

Пример роли с более широкими правами, но без `SUPERUSER`:

```sql
CREATE ROLE app_admin;

GRANT CONNECT ON DATABASE app_db TO app_admin;
GRANT USAGE, CREATE ON SCHEMA public TO app_admin;
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO app_admin;
GRANT USAGE, SELECT, UPDATE
ON ALL SEQUENCES IN SCHEMA public
TO app_admin;
```

Назначение пользователю:

```sql
CREATE USER deploy_user WITH PASSWORD 'strong_password';
GRANT app_admin TO deploy_user;
```

## Примеры прав на базу, схему и таблицы

### Доступ к базе

```sql
GRANT CONNECT ON DATABASE app_db TO report_user;
```

### Доступ к схеме

```sql
GRANT USAGE ON SCHEMA reporting TO report_user;
```

### Доступ к конкретной таблице

```sql
GRANT SELECT ON TABLE reporting.daily_sales TO report_user;
```

### Доступ ко всем таблицам в схеме

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO report_user;
```

## Проверка прав и членства

Посмотреть роли и атрибуты:

```sql
\du
```

Проверить права на таблицу:

```sql
\dp public.orders
```

Проверить, есть ли у роли право на таблицу:

```sql
SELECT has_table_privilege('app_user', 'public.orders', 'SELECT');
SELECT has_table_privilege('app_user', 'public.orders', 'INSERT');
```

Проверить доступ к схеме:

```sql
SELECT has_schema_privilege('app_user', 'public', 'USAGE');
```

Проверить доступ к базе:

```sql
SELECT has_database_privilege('app_user', 'app_db', 'CONNECT');
```

Посмотреть членство в ролях:

```sql
SELECT
    member.rolname AS member_name,
    parent.rolname AS granted_role
FROM pg_auth_members m
JOIN pg_roles parent ON parent.oid = m.roleid
JOIN pg_roles member ON member.oid = m.member
ORDER BY member.rolname, parent.rolname;
```

## Практический минимальный сценарий

Создать пользователя только для чтения в базе `app_db`:

```sql
CREATE ROLE app_readonly;
GRANT CONNECT ON DATABASE app_db TO app_readonly;

\c app_db

GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO app_readonly;

CREATE USER report_user WITH PASSWORD 'strong_password';
GRANT app_readonly TO report_user;
```

## На что обратить внимание

- Не выдавать `SUPERUSER`, если достаточно обычных `GRANT`.
- Права на базу, схему и таблицы - это разные уровни доступа.
- Для новых таблиц старые `GRANT ON ALL TABLES` не применяются автоматически без `ALTER DEFAULT PRIVILEGES`.
- Удобнее выдавать права не напрямую пользователям, а через промежуточные роли.

## Короткая памятка

```sql
CREATE ROLE app_readonly;
CREATE USER app_user WITH PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE app_db TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_user;
ALTER ROLE app_user WITH PASSWORD 'new_strong_password';
REVOKE INSERT ON TABLE public.orders FROM app_user;
DROP ROLE app_readonly;
```
