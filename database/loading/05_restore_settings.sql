-- =====================================================================
-- Phase 4 - restore durable settings after the bulk load.
--
-- 00_server_setup.sql relaxed redo-log durability to speed up loading.
-- That trade is only acceptable while loading reproducible static data.
-- Run this as soon as the load and verification are done.
-- =====================================================================

-- Back to full ACID durability: sync the redo log to disk on every commit.
SET GLOBAL innodb_flush_log_at_trx_commit = 1;

-- local_infile stays ON only if you intend to re-run loads. Turning it off is
-- the safer default, since it lets any client push local files to the server.
-- Uncomment when you are finished loading for good:
-- SET GLOBAL local_infile = 0;

-- The 2 GB buffer pool is worth KEEPING for the analytical phases (6-12).
-- Every roll-rate and vintage query scans multi-million-row panels, and a
-- 128 MB pool would send almost every page read to disk.
-- To make it permanent across restarts, add to
--   C:\ProgramData\MySQL\MySQL Server 8.0\my.ini   under [mysqld]:
--       innodb_buffer_pool_size=2G
-- and restart the MySQL80 service.

SELECT @@GLOBAL.innodb_flush_log_at_trx_commit AS flush_at_commit,
       @@GLOBAL.local_infile                   AS local_infile,
       @@GLOBAL.innodb_buffer_pool_size/1024/1024 AS buffer_pool_mb;
