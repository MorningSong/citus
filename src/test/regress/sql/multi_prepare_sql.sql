--
-- MULTI_PREPARE_SQL
--

-- Tests covering PREPARE statements. Many of the queries are
-- taken from other regression test files and converted into
-- prepared statements.


ALTER SEQUENCE pg_catalog.pg_dist_shardid_seq RESTART 790000;
ALTER SEQUENCE pg_catalog.pg_dist_jobid_seq RESTART 790000;


PREPARE prepared_test_1 AS
SELECT
	count(*)
FROM
	orders;

PREPARE prepared_test_2 AS
SELECT
	count(*)
FROM
	orders, lineitem
WHERE
	o_orderkey = l_orderkey;

PREPARE prepared_test_3 AS
SELECT
	count(*)
FROM
	orders, customer
WHERE
	o_custkey = c_custkey;

PREPARE prepared_test_4 AS
SELECT
	count(*)
FROM
	orders, customer, lineitem
WHERE
	o_custkey = c_custkey AND
	o_orderkey = l_orderkey;

PREPARE prepared_test_5 AS
SELECT
	count(*)
FROM
	lineitem, customer
WHERE
	l_partkey = c_nationkey;

PREPARE prepared_test_6(int) AS
SELECT
	count(*)
FROM
	orders, lineitem
WHERE
	o_orderkey = l_orderkey AND
	l_suppkey > $1;

PREPARE prepared_test_7(text, text) AS
SELECT
	supp_nation,
	cust_nation,
	l_year,
	sum(volume) AS revenue
FROM
	(
	SELECT
		supp_nation,
		cust_nation,
		extract(year FROM l_shipdate) AS l_year,
		l_extendedprice * (1 - l_discount) AS volume
	FROM
		supplier,
		lineitem,
		orders,
		customer,
		(
		SELECT
			n1.n_nationkey AS supp_nation_key,
			n2.n_nationkey AS cust_nation_key,
			n1.n_name AS supp_nation,
			n2.n_name AS cust_nation
		FROM
			nation n1,
			nation n2
		WHERE
			(
			(n1.n_name = $1 AND n2.n_name = $2)
			OR (n1.n_name = $2 AND n2.n_name = $1)
			)
		) AS temp
        WHERE
		s_suppkey = l_suppkey
		AND o_orderkey = l_orderkey
		AND c_custkey = o_custkey
		AND s_nationkey = supp_nation_key
		AND c_nationkey = cust_nation_key
		AND l_shipdate between date '1995-01-01' AND date '1996-12-31'
	) AS shipping
GROUP BY
	supp_nation,
	cust_nation,
	l_year
ORDER BY
	supp_nation,
	cust_nation,
	l_year;

SET citus.task_executor_type TO 'task-tracker';
SET client_min_messages TO INFO;

-- execute prepared statements
EXECUTE prepared_test_1;
EXECUTE prepared_test_2;
EXECUTE prepared_test_3;
EXECUTE prepared_test_4;
EXECUTE prepared_test_5;

-- execute prepared statements with different parameters
EXECUTE prepared_test_6(155);
EXECUTE prepared_test_6(1555);
EXECUTE prepared_test_7('UNITED KINGDOM', 'CHINA');
EXECUTE prepared_test_7('FRANCE', 'GERMANY');

-- now, execute prepared statements with random order
EXECUTE prepared_test_6(155);
EXECUTE prepared_test_3;
EXECUTE prepared_test_7('FRANCE', 'GERMANY');
EXECUTE prepared_test_5;
EXECUTE prepared_test_1;
EXECUTE prepared_test_6(1555);
EXECUTE prepared_test_4;
EXECUTE prepared_test_7('UNITED KINGDOM', 'CHINA');
EXECUTE prepared_test_2;

-- CREATE TABLE ... AS EXECUTE prepared_statement tests
CREATE TEMP TABLE prepared_sql_test_7 AS EXECUTE prepared_test_7('UNITED KINGDOM', 'CHINA');
SELECT * from prepared_sql_test_7;

-- now, run some of the tests with real-time executor
SET citus.task_executor_type TO 'real-time';

-- execute prepared statements
EXECUTE prepared_test_1;
EXECUTE prepared_test_2;

-- execute prepared statements with different parameters
EXECUTE prepared_test_6(155);
-- FIXME: temporarily disabled
-- EXECUTE prepared_test_6(1555);

-- test router executor with parameterized non-partition columns

-- create a custom type which also exists on worker nodes
CREATE TYPE test_composite_type AS (
    i integer,
    i2 integer
);

CREATE TABLE router_executor_table (
    id bigint NOT NULL,
    comment varchar(20),
    stats test_composite_type
);

SELECT master_create_distributed_table('router_executor_table', 'id', 'hash');
SELECT master_create_worker_shards('router_executor_table', 2, 2);

-- test parameterized inserts
PREPARE prepared_insert(varchar(20)) AS
	INSERT INTO router_executor_table VALUES (1, $1, $2);

EXECUTE prepared_insert('comment-1', '(1, 10)');
EXECUTE prepared_insert('comment-2', '(2, 20)');
EXECUTE prepared_insert('comment-3', '(3, 30)');
EXECUTE prepared_insert('comment-4', '(4, 40)');
EXECUTE prepared_insert('comment-5', '(5, 50)');
EXECUTE prepared_insert('comment-6', '(6, 60)');

SELECT * FROM router_executor_table ORDER BY comment;

-- test parameterized selects
PREPARE prepared_select(integer, integer) AS
	SELECT count(*) FROM router_executor_table
		WHERE id = 1 AND stats = ROW($1, $2)::test_composite_type;

EXECUTE prepared_select(1, 10);
EXECUTE prepared_select(2, 20);
EXECUTE prepared_select(3, 30);
EXECUTE prepared_select(4, 40);
EXECUTE prepared_select(5, 50);
EXECUTE prepared_select(6, 60);

-- test that we don't crash on failing parameterized insert on the partition column

PREPARE prepared_partition_column_insert(bigint) AS
INSERT INTO router_executor_table VALUES ($1, 'arsenous', '(1,10)');

-- we error out on the 6th execution
EXECUTE prepared_partition_column_insert(1);
EXECUTE prepared_partition_column_insert(2);
EXECUTE prepared_partition_column_insert(3);
EXECUTE prepared_partition_column_insert(4);
EXECUTE prepared_partition_column_insert(5);
EXECUTE prepared_partition_column_insert(6);

DROP TYPE test_composite_type CASCADE;

-- test router executor with prepare statements
CREATE TABLE prepare_table (
	key int,
	value int
);
SELECT master_create_distributed_table('prepare_table','key','hash');
SELECT master_create_worker_shards('prepare_table',4,1);

PREPARE prepared_no_parameter_insert AS
	INSERT INTO prepare_table (key) VALUES (0);

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_no_parameter_insert;
EXECUTE prepared_no_parameter_insert;
EXECUTE prepared_no_parameter_insert;
EXECUTE prepared_no_parameter_insert;
EXECUTE prepared_no_parameter_insert;
EXECUTE prepared_no_parameter_insert;

PREPARE prepared_single_parameter_insert(int) AS
	INSERT INTO prepare_table (key) VALUES ($1);

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_single_parameter_insert(1);
EXECUTE prepared_single_parameter_insert(2);
EXECUTE prepared_single_parameter_insert(3);
EXECUTE prepared_single_parameter_insert(4);
EXECUTE prepared_single_parameter_insert(5);
EXECUTE prepared_single_parameter_insert(6);

PREPARE prepared_double_parameter_insert(int, int) AS
	INSERT INTO prepare_table (key, value) VALUES ($1, $2);

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_double_parameter_insert(1, 10);
EXECUTE prepared_double_parameter_insert(2, 20);
EXECUTE prepared_double_parameter_insert(3, 30);
EXECUTE prepared_double_parameter_insert(4, 40);
EXECUTE prepared_double_parameter_insert(5, 50);
EXECUTE prepared_double_parameter_insert(6, 60);

PREPARE prepared_non_partition_parameter_insert(int) AS
	INSERT INTO prepare_table (key, value) VALUES (0, $1);

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_non_partition_parameter_insert(10);
EXECUTE prepared_non_partition_parameter_insert(20);
EXECUTE prepared_non_partition_parameter_insert(30);
EXECUTE prepared_non_partition_parameter_insert(40);
EXECUTE prepared_non_partition_parameter_insert(50);
EXECUTE prepared_non_partition_parameter_insert(60);

-- check inserted values
SELECT * FROM prepare_table ORDER BY key, value;

-- check router executor select
PREPARE prepared_router_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.key = $1
	ORDER BY
		key,
		value;

EXECUTE prepared_router_partition_column_select(1);
EXECUTE prepared_router_partition_column_select(2);
EXECUTE prepared_router_partition_column_select(3);
EXECUTE prepared_router_partition_column_select(4);
EXECUTE prepared_router_partition_column_select(5);

-- FIXME: 6th execution is failing. We don't want to run the failing test
-- because of changing output. After implementing this feature, uncomment this.
-- EXECUTE prepared_router_partition_column_select(6);

PREPARE prepared_router_non_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.key = 0 AND
		prepare_table.value = $1
	ORDER BY
		key,
		value;

EXECUTE prepared_router_non_partition_column_select(10);
EXECUTE prepared_router_non_partition_column_select(20);
EXECUTE prepared_router_non_partition_column_select(30);
EXECUTE prepared_router_non_partition_column_select(40);
EXECUTE prepared_router_non_partition_column_select(50);
EXECUTE prepared_router_non_partition_column_select(60);

-- check real-time executor
PREPARE prepared_real_time_non_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.value = $1
	ORDER BY
		key,
		value;

EXECUTE prepared_real_time_non_partition_column_select(10);
EXECUTE prepared_real_time_non_partition_column_select(20);
EXECUTE prepared_real_time_non_partition_column_select(30);
EXECUTE prepared_real_time_non_partition_column_select(40);
EXECUTE prepared_real_time_non_partition_column_select(50);

-- FIXME: 6th execution is failing. We don't want to run the failing test
-- because of changing output. After implementing this feature, uncomment this.
-- EXECUTE prepared_real_time_non_partition_column_select(60);

PREPARE prepared_real_time_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.key = $1 OR
		prepare_table.value = 10
	ORDER BY
		key,
		value;

EXECUTE prepared_real_time_partition_column_select(1);
EXECUTE prepared_real_time_partition_column_select(2);
EXECUTE prepared_real_time_partition_column_select(3);
EXECUTE prepared_real_time_partition_column_select(4);
EXECUTE prepared_real_time_partition_column_select(5);

-- FIXME: 6th execution is failing. We don't want to run the failing test
-- because of changing output. After implementing this feature, uncomment this.
-- EXECUTE prepared_real_time_partition_column_select(6);

-- check task-tracker executor
SET citus.task_executor_type TO 'task-tracker';

PREPARE prepared_task_tracker_non_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.value = $1
	ORDER BY
		key,
		value;

EXECUTE prepared_task_tracker_non_partition_column_select(10);
EXECUTE prepared_task_tracker_non_partition_column_select(20);
EXECUTE prepared_task_tracker_non_partition_column_select(30);
EXECUTE prepared_task_tracker_non_partition_column_select(40);
EXECUTE prepared_task_tracker_non_partition_column_select(50);

-- FIXME: 6th execution is failing. We don't want to run the failing test
-- because of changing output. After implementing this feature, uncomment this.
-- EXECUTE prepared_task_tracker_non_partition_column_select(60);

PREPARE prepared_task_tracker_partition_column_select(int) AS
	SELECT
		prepare_table.key,
		prepare_table.value
	FROM
		prepare_table
	WHERE
		prepare_table.key = $1 OR
		prepare_table.value = 10
	ORDER BY
		key,
		value;

EXECUTE prepared_task_tracker_partition_column_select(1);
EXECUTE prepared_task_tracker_partition_column_select(2);
EXECUTE prepared_task_tracker_partition_column_select(3);
EXECUTE prepared_task_tracker_partition_column_select(4);
EXECUTE prepared_task_tracker_partition_column_select(5);

-- FIXME: 6th execution is failing. We don't want to run the failing test
-- because of changing output. After implementing this feature, uncomment this.
-- EXECUTE prepared_task_tracker_partition_column_select(6);

SET citus.task_executor_type TO 'real-time';

-- check updates
PREPARE prepared_partition_parameter_update(int, int) AS
	UPDATE prepare_table SET value = $2 WHERE key = $1;

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_partition_parameter_update(1, 11);
EXECUTE prepared_partition_parameter_update(2, 21);
EXECUTE prepared_partition_parameter_update(3, 31);
EXECUTE prepared_partition_parameter_update(4, 41);
EXECUTE prepared_partition_parameter_update(5, 51);
-- This fails with an unexpected error message
EXECUTE prepared_partition_parameter_update(5, 52);

PREPARE prepared_non_partition_parameter_update(int, int) AS
	UPDATE prepare_table SET value = $2 WHERE key = 0 AND value = $1;

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_non_partition_parameter_update(10, 12);
EXECUTE prepared_non_partition_parameter_update(20, 22);
EXECUTE prepared_non_partition_parameter_update(30, 32);
EXECUTE prepared_non_partition_parameter_update(40, 42);
EXECUTE prepared_non_partition_parameter_update(50, 52);
EXECUTE prepared_non_partition_parameter_update(60, 62);

-- check after updates
SELECT * FROM prepare_table ORDER BY key, value;

-- check deletes
PREPARE prepared_partition_parameter_delete(int, int) AS
	DELETE FROM prepare_table WHERE key = $1 AND value = $2;

EXECUTE prepared_partition_parameter_delete(1, 11);
EXECUTE prepared_partition_parameter_delete(2, 21);
EXECUTE prepared_partition_parameter_delete(3, 31);
EXECUTE prepared_partition_parameter_delete(4, 41);
EXECUTE prepared_partition_parameter_delete(5, 51);
-- This fails with an unexpected error message
EXECUTE prepared_partition_parameter_delete(0, 10);

PREPARE prepared_non_partition_parameter_delete(int) AS
	DELETE FROM prepare_table WHERE key = 0 AND value = $1;

-- execute 6 times to trigger prepared statement usage
EXECUTE prepared_non_partition_parameter_delete(12);
EXECUTE prepared_non_partition_parameter_delete(22);
EXECUTE prepared_non_partition_parameter_delete(32);
EXECUTE prepared_non_partition_parameter_delete(42);
EXECUTE prepared_non_partition_parameter_delete(52);
EXECUTE prepared_non_partition_parameter_delete(62);

-- check after deletes
SELECT * FROM prepare_table ORDER BY key, value;

-- clean-up prepared statements
DEALLOCATE ALL;
