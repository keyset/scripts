/**********************************************************************************************************
# create a manual snapshot
aws rds create-db-snapshot --db-instance-identifier XXXXXXXXXXXXXXXXX --db-snapshot-identifier XXXXXXXXXXXXXXXXX

# show all bastion hosts
aws ec2 describe-instances --filters 'Name=tag:Name,Values=*bastion*' 'Name=tag:foo,Values=bar' \
  --query 'Reservations[*].Instances[*].{Instance:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PrivateIP:NetworkInterfaces[0].PrivateIpAddress,Started:LaunchTime,AZ:Placement.AvailabilityZone}' \
  --output table

# show all clusters by endpoints
aws rds describe-db-clusters --query 'DBClusters[*].{Name:DatabaseName,Address:Endpoint,User:MasterUsername,Engine:Engine,Status:Status}' --output table

# show all XXXXXXXXXXXXXXXXX instances
aws rds describe-db-instances --filters 'Name=db-cluster-id,Values=XXXXXXXXXXXXXXXXX' \
  --query 'DBInstances[*].{Name:DBInstanceIdentifier,Address:Endpoint.Address,User:MasterUsername,Engine:Engine,Status:DBInstanceStatus}' --output table

# SSM into bastion host
aws ssm start-session --target XXXX_BASTION_HOST_INSTANCE_ID_XXXXX

# Port-forward from localhost thru bastion host
aws ssm start-session --target XXXX_BASTION_HOST_INSTANCE_ID_XXXXX \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters '{"host":["XXXX_CLUSTER_ENDPOINT_XXXX"],"portNumber":["5432"], "localPortNumber":["5432"]}'


# using screen for multiple and/or long-running instances of psql
screen --version
sudo apt update
sudo apt install screen
screen -S session_name

# You can detach from the screen session at any time by typing:
# Ctrl+a d

# list screen sessions
screen -ls

# resume screen
screen -r session_id

https://www.postgresql.org/docs/16/app-psql.html

--list all dbs
\l

--list all tables
\dt+ *.*

--show table schema
\d+ XXXXXXXXXXXXXXXXX

--print connnection info
\conninfo

--output to csv file
\copy (SELECT * FROM XXXXXXXXXXXXXXXXX LIMIT 10) TO '~/filename.csv' WITH CSV HEADER

--quit
\q

********************************************************************************/

--find blocked queries
SELECT relation::regclass, * FROM pg_locks WHERE NOT GRANTED;

--find running queries with given text
SELECT now()-query_start AS runtime, query_start, datname, usename, pid, application_name, client_addr, left(query,60)
FROM pg_stat_activity
WHERE state='active'
  --AND query LIKE '%XXXXXXXXXXXXXXXXX%'
  AND pid <> (SELECT pg_backend_pid())
  AND (now() - query_start) > interval '5 minutes'
ORDER BY query_start DESC;

--kill a certain pid
SELECT pg_terminate_backend(123456789);

--kill all queries with certain text
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND query LIKE '%XXXXXXXXXXXXXXXXX%'
  AND pid <> (SELECT pg_backend_pid());

--show recent vacuum statistics
SELECT
schemaname AS Schema
,relname AS TableName
,n_live_tup AS LiveTuples
,n_dead_tup AS DeadTuples
,last_autovacuum AS LastAutovacuum
,last_autoanalyze AS LastAutoanalyze
,last_vacuum AS LastVacuum
,last_analyze AS LastAnalyze
FROM pg_stat_user_tables
ORDER BY tablename;

-- which tables are due for autovacuum
WITH vbt AS (SELECT setting AS autovacuum_vacuum_threshold FROM 
pg_settings WHERE name = 'autovacuum_vacuum_threshold'),
vsf AS (SELECT setting AS autovacuum_vacuum_scale_factor FROM 
pg_settings WHERE name = 'autovacuum_vacuum_scale_factor'), 
fma AS (SELECT setting AS autovacuum_freeze_max_age FROM pg_settings WHERE name = 'autovacuum_freeze_max_age'),
sto AS (select opt_oid, split_part(setting, '=', 1) as param,
split_part(setting, '=', 2) as value from (select oid opt_oid, unnest(reloptions) setting from pg_class) opt)
SELECT '"'||ns.nspname||'"."'||c.relname||'"' as relation,
pg_size_pretty(pg_table_size(c.oid)) as table_size,
age(relfrozenxid) as xid_age,
coalesce(cfma.value::float, autovacuum_freeze_max_age::float) autovacuum_freeze_max_age,
(coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) +
coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * c.reltuples)
AS autovacuum_vacuum_tuples, n_dead_tup as dead_tuples FROM
pg_class c join pg_namespace ns on ns.oid = c.relnamespace 
join pg_stat_all_tables stat on stat.relid = c.oid join vbt on (1=1) join vsf on (1=1) join fma on (1=1)
left join sto cvbt on cvbt.param = 'autovacuum_vacuum_threshold' and c.oid = cvbt.opt_oid 
left join sto cvsf on cvsf.param = 'autovacuum_vacuum_scale_factor' and c.oid = cvsf.opt_oid
left join sto cfma on cfma.param = 'autovacuum_freeze_max_age' and c.oid = cfma.opt_oid
WHERE c.relkind = 'r' and nspname <> 'pg_catalog'
AND (age(relfrozenxid) >= coalesce(cfma.value::float, autovacuum_freeze_max_age::float)
OR coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) + 
coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * 
c.reltuples <= n_dead_tup)
ORDER BY age(relfrozenxid) DESC LIMIT 50;

-- show vacuum settings
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE ('%vacuum%');


-- see status of vacuum
SELECT stat.pid, stat.datname, c.relname,
    stat.phase, stat.heap_blks_total, stat.heap_blks_scanned,
    stat.heap_blks_vacuumed, stat.index_vacuum_count,
    stat.max_dead_tuples, stat.num_dead_tuples,
    c.relfrozenxid, c.relminmxid
FROM pg_stat_progress_vacuum stat
JOIN pg_class c ON stat.relid = c.oid;

-- wait stats of running queries
      SELECT a.pid, 
            a.usename,
            a.client_addr,
            a.current_query,
            a.query_start,
            a.current_wait_type, 
            a.current_wait_event, 
            a.current_state, 
            wt.type_name AS wait_type, 
            we.event_name AS wait_event, 
            a.waits, 
            a.wait_time
        FROM (SELECT pid, 
                     usename, 
                     client_addr,
                     coalesce(wait_event_type,'CPU') AS current_wait_type,
                     coalesce(wait_event,'CPU') AS current_wait_event, 
                     state AS current_state,
                     left(query,60) as current_query,
                     query_start,
                     (aurora_stat_backend_waits(pid)).*
                FROM pg_stat_activity 
               WHERE pid <> pg_backend_pid()
                 AND usename<>'rdsadmin') a
NATURAL JOIN aurora_stat_wait_type() wt 
NATURAL JOIN aurora_stat_wait_event() we
WHERE 
  -- current_wait_event <> 'ClientRead'
  -- AND
a.current_state <> 'Idle'
  --AND
  -- a.current_query like '%XXXXXXXXXXXXXXXXX%'
AND (now() - a.query_start) > interval '5 minutes'
    ORDER BY a.query_start;

SELECT * FROM aurora_stat_backend_waits(123456789);

WITH RECURSIVE
     c(requested, current) AS
       ( VALUES
         ('AccessShareLock'::text, 'AccessExclusiveLock'::text),
         ('RowShareLock'::text, 'ExclusiveLock'::text),
         ('RowShareLock'::text, 'AccessExclusiveLock'::text),
         ('RowExclusiveLock'::text, 'ShareLock'::text),
         ('RowExclusiveLock'::text, 'ShareRowExclusiveLock'::text),
         ('RowExclusiveLock'::text, 'ExclusiveLock'::text),
         ('RowExclusiveLock'::text, 'AccessExclusiveLock'::text),
         ('ShareUpdateExclusiveLock'::text, 'ShareUpdateExclusiveLock'::text),
         ('ShareUpdateExclusiveLock'::text, 'ShareLock'::text),
         ('ShareUpdateExclusiveLock'::text, 'ShareRowExclusiveLock'::text),
         ('ShareUpdateExclusiveLock'::text, 'ExclusiveLock'::text),
         ('ShareUpdateExclusiveLock'::text, 'AccessExclusiveLock'::text),
         ('ShareLock'::text, 'RowExclusiveLock'::text),
         ('ShareLock'::text, 'ShareUpdateExclusiveLock'::text),
         ('ShareLock'::text, 'ShareRowExclusiveLock'::text),
         ('ShareLock'::text, 'ExclusiveLock'::text),
         ('ShareLock'::text, 'AccessExclusiveLock'::text),
         ('ShareRowExclusiveLock'::text, 'RowExclusiveLock'::text),
         ('ShareRowExclusiveLock'::text, 'ShareUpdateExclusiveLock'::text),
         ('ShareRowExclusiveLock'::text, 'ShareLock'::text),
         ('ShareRowExclusiveLock'::text, 'ShareRowExclusiveLock'::text),
         ('ShareRowExclusiveLock'::text, 'ExclusiveLock'::text),
         ('ShareRowExclusiveLock'::text, 'AccessExclusiveLock'::text),
         ('ExclusiveLock'::text, 'RowShareLock'::text),
         ('ExclusiveLock'::text, 'RowExclusiveLock'::text),
         ('ExclusiveLock'::text, 'ShareUpdateExclusiveLock'::text),
         ('ExclusiveLock'::text, 'ShareLock'::text),
         ('ExclusiveLock'::text, 'ShareRowExclusiveLock'::text),
         ('ExclusiveLock'::text, 'ExclusiveLock'::text),
         ('ExclusiveLock'::text, 'AccessExclusiveLock'::text),
         ('AccessExclusiveLock'::text, 'AccessShareLock'::text),
         ('AccessExclusiveLock'::text, 'RowShareLock'::text),
         ('AccessExclusiveLock'::text, 'RowExclusiveLock'::text),
         ('AccessExclusiveLock'::text, 'ShareUpdateExclusiveLock'::text),
         ('AccessExclusiveLock'::text, 'ShareLock'::text),
         ('AccessExclusiveLock'::text, 'ShareRowExclusiveLock'::text),
         ('AccessExclusiveLock'::text, 'ExclusiveLock'::text),
         ('AccessExclusiveLock'::text, 'AccessExclusiveLock'::text)
       ),
     l AS
       (
         SELECT
             (locktype,DATABASE,relation::regclass::text,page,tuple,virtualxid,transactionid,classid,objid,objsubid) AS target,
             virtualtransaction,
             pid,
             mode,
             granted
           FROM pg_catalog.pg_locks
       ),
     t AS
       (
         SELECT
             blocker.target  AS blocker_target,
             blocker.pid     AS blocker_pid,
             blocker.mode    AS blocker_mode,
             blocked.target  AS target,
             blocked.pid     AS pid,
             blocked.mode    AS mode
           FROM l blocker
           JOIN l blocked
             ON ( NOT blocked.granted
              AND blocker.granted
              AND blocked.pid != blocker.pid
              AND blocked.target IS NOT DISTINCT FROM blocker.target)
           JOIN c ON (c.requested = blocked.mode AND c.current = blocker.mode)
       ),
     r AS
       (
         SELECT
             blocker_target,
             blocker_pid,
             blocker_mode,
             '1'::int        AS depth,
             target,
             pid,
             mode,
             blocker_pid::text || ',' || pid::text AS seq
           FROM t
         UNION ALL
         SELECT
             blocker.blocker_target,
             blocker.blocker_pid,
             blocker.blocker_mode,
             blocker.depth + 1,
             blocked.target,
             blocked.pid,
             blocked.mode,
             blocker.seq || ',' || blocked.pid::text
           FROM r blocker
           JOIN t blocked
             ON (blocked.blocker_pid = blocker.pid)
           WHERE blocker.depth < 1000
       )
SELECT
  r.*,
  pgs.usename,
  pgs.query_start,
  left(pgs.query,40)
FROM r
JOIN pg_stat_activity pgs ON r.pid = pgs.pid
  ORDER BY pgs.query_start;


SELECT 
    waiting.locktype           AS waiting_locktype,
    waiting.relation::regclass AS waiting_table,
    left(waiting_stm.query,60)          AS waiting_query,
    waiting_stm.query_start    AS waiting_starttime,
    waiting.mode               AS waiting_mode,
    waiting.pid                AS waiting_pid,
    other.locktype             AS other_locktype,
    other.relation::regclass   AS other_table,
    left(other_stm.query,60)            AS other_query,
    other_stm.query_start      AS other_starttime,
    other.mode                 AS other_mode,
    other.pid                  AS other_pid,
    other.granted              AS other_granted
FROM
    pg_catalog.pg_locks AS waiting
JOIN
    pg_catalog.pg_stat_activity AS waiting_stm
    ON (
        waiting_stm.pid = waiting.pid
    )
JOIN
    pg_catalog.pg_locks AS other
    ON (
        (
            waiting."database" = other."database"
        AND waiting.relation  = other.relation
        )
        OR waiting.transactionid = other.transactionid
    )
JOIN
    pg_catalog.pg_stat_activity AS other_stm
    ON (
        other_stm.pid = other.pid
    )
WHERE
    NOT waiting.granted
AND
    waiting.pid <> other.pid
ORDER BY waiting_stm.query_start ASC
LIMIT 100;
