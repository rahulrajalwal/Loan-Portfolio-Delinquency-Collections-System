-- =====================================================================
-- Phase 4 - server preparation.  Run ONCE, as root, before loading.
--
-- Every setting here is DYNAMIC in MySQL 8.0 - no service restart needed.
-- These are session-of-the-server settings: they revert when MySQL restarts,
-- which is deliberate. We are tuning for a one-off bulk load, not permanently
-- reconfiguring the user's server.
-- =====================================================================

-- 1. Allow client-side LOAD DATA LOCAL INFILE.
--    Needed because secure-file-priv restricts server-side LOAD DATA INFILE to
--    C:/ProgramData/MySQL/MySQL Server 8.0/Uploads, and our CSVs live in the
--    project folder. LOCAL sends the file from the client instead.
--    The client ALSO needs --local-infile=1 on its command line.
SET GLOBAL local_infile = 1;

-- 2. Raise the InnoDB buffer pool from the installer default of 128 MB.
--    This is the single biggest lever on load and query speed: it is the cache
--    for data and index pages. At 128 MB almost every page read hits disk.
--    2 GB on a 7.3 GB machine leaves ample headroom for the OS and client.
--    MySQL 8 resizes this online; it may take a few seconds to complete.
SET GLOBAL innodb_buffer_pool_size = 2147483648;   -- 2 GiB

-- 3. Relax redo-log durability for the load only.
--    1 = flush+sync to disk on every commit (crash-safe, slow)
--    2 = write to OS cache each commit, sync once per second (much faster)
--    Safe here: this is a reload of static public CSVs. If the machine lost
--    power mid-load we would simply re-run it.
--    !! RESTORED TO 1 in 05_restore_settings.sql once loading is done. !!
SET GLOBAL innodb_flush_log_at_trx_commit = 2;

-- 4. Confirm strict mode is active so bad data ERRORS instead of being silently
--    coerced. This is what protects the Phase 3 type choices: without it, a DPD
--    of 4231 written to a too-small column would be truncated with a warning
--    nobody reads. Expect STRICT_TRANS_TABLES in the output.
SELECT @@GLOBAL.sql_mode AS sql_mode;

-- 5. Report the settings actually in force.
SELECT @@GLOBAL.local_infile                 AS local_infile,
       @@GLOBAL.innodb_buffer_pool_size/1024/1024 AS buffer_pool_mb,
       @@GLOBAL.innodb_flush_log_at_trx_commit    AS flush_at_commit,
       @@GLOBAL.secure_file_priv             AS secure_file_priv;
