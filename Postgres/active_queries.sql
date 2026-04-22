-- SQL-запросы для просмотра активных запросов в PostgreSQL.
-- Основной источник: системное представление pg_stat_activity.

-- 1. Все активные запросы, кроме текущей сессии.
SELECT
    pid,
    usename AS username,
    datname AS database_name,
    application_name,
    client_addr,
    backend_start,
    xact_start,
    query_start,
    now() - query_start AS query_duration,
    wait_event_type,
    wait_event,
    state,
    query
FROM pg_stat_activity
WHERE state = 'active'
  AND pid <> pg_backend_pid()
ORDER BY query_start ASC;

-- 2. Самые долгие активные запросы.
SELECT
    pid,
    usename AS username,
    datname AS database_name,
    application_name,
    client_addr,
    now() - query_start AS query_duration,
    wait_event_type,
    wait_event,
    state,
    query
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start IS NOT NULL
  AND pid <> pg_backend_pid()
ORDER BY query_duration DESC;

-- 3. Все сессии с краткой диагностикой состояния.
SELECT
    pid,
    usename AS username,
    datname AS database_name,
    application_name,
    client_addr,
    state,
    backend_start,
    xact_start,
    query_start,
    state_change,
    wait_event_type,
    wait_event,
    left(query, 300) AS query_preview
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY state, query_start NULLS LAST;

-- 4. Запросы, которые ждут ресурс.
SELECT
    pid,
    usename AS username,
    datname AS database_name,
    application_name,
    state,
    wait_event_type,
    wait_event,
    now() - query_start AS query_duration,
    query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND wait_event IS NOT NULL
ORDER BY query_start ASC NULLS LAST;

-- 5. Активные запросы вместе с блокирующими PID.
SELECT
    a.pid,
    a.usename AS username,
    a.datname AS database_name,
    a.application_name,
    a.client_addr,
    a.state,
    now() - a.query_start AS query_duration,
    pg_blocking_pids(a.pid) AS blocking_pids,
    a.query
FROM pg_stat_activity AS a
WHERE a.pid <> pg_backend_pid()
  AND a.state = 'active'
ORDER BY a.query_start ASC;
