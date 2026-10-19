--
-- PostgreSQL database dump
--

\restrict rEmIeaVWrP0n5roECT4gTrCQXSUvlhAy3vxiSjrZBTluL9GQ0wiLXiOhG3byoki

-- Dumped from database version 18.6 (Ubuntu 18.6-1.pgdg26.04+2)
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-1.pgdg26.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: check_indexes(character varying, character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_indexes(v_schema_name character varying DEFAULT NULL::character varying, v_table_name character varying DEFAULT NULL::character varying, v_warning_format character varying DEFAULT 'rows'::character varying, v_debug_level integer DEFAULT 0) RETURNS TABLE(schema_name text, table_name text, index_name text, index_type character varying, index_definition character varying, size_kb integer, estimated_tuples integer, estimated_tuples_as_of timestamp with time zone, dead_tuples integer, last_autovacuum timestamp with time zone, last_manual_nonfull_vacuum timestamp with time zone, fill_factor integer, is_unique boolean, is_primary boolean, table_oid integer, index_oid integer, priority integer, warning_summary character varying, warning_details character varying, url character varying, reloptions text[], drop_object_command character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    sql_to_execute TEXT;
BEGIN


	/* check_indexes from Smart Postgres Box of Tricks
	 * v0.1, 2025-08-29
	 * 
	 * For documentation, help, contributions:
	 * 		https://github.com/SmartPostgres/Box-of-Tricks/
	 * 		https://SmartPostgres.com
	 *
	 * Open source, MIT license
	 * 
	 * Parameters:
	 * v_schema_name: lets you filter results to just one schema (null = all)
	 * v_table_name: lets you filter results to just one table (null = all)
	 * v_warning_level: for future use, not implemented yet
	 * v_debug_level: 0 = no messages, 1 = critical messages, 2 = all messages 
	 */

    SET lock_timeout = '5s';

    CREATE TEMPORARY TABLE ci_indexes
    (
        schema_name VARCHAR,
        table_name VARCHAR,
        index_name VARCHAR,
        index_type VARCHAR,
        index_definition VARCHAR,
        size_kb INTEGER,
        estimated_tuples INTEGER,
        estimated_tuples_as_of TIMESTAMPTZ,
		dead_tuples INTEGER,
        is_unique BOOLEAN,
        is_primary BOOLEAN,
        table_oid INTEGER,
        index_oid INTEGER,
        relkind CHAR,
		reltoastrelid INTEGER,
		n_mod_since_analyze BIGINT,
		n_ins_since_vacuum BIGINT,
		last_autovacuum TIMESTAMPTZ,
		last_manual_nonfull_vacuum TIMESTAMPTZ,
		last_analyze TIMESTAMPTZ,
		last_autoanalyze TIMESTAMPTZ,
		reloptions TEXT[],
		drop_object_command VARCHAR,
		fill_factor INTEGER,
		relfrozenxid XID
    );

	CREATE TEMPORARY TABLE ci_indexes_warnings
	(
		table_oid INTEGER,
		index_oid INTEGER,
		priority INTEGER,
		warning_summary VARCHAR,
		warning_details VARCHAR,
		url VARCHAR
	);




    -- Build SQL for Tables & Materialized Views
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Build SQL for Tables & Materialized Views';
	END IF;

    sql_to_execute := '
    INSERT INTO ci_indexes (schema_name, table_name, index_name, index_type, index_definition, estimated_tuples, estimated_tuples_as_of, 
		dead_tuples, is_unique, is_primary, table_oid, index_oid, relkind, reltoastrelid, 
		last_manual_nonfull_vacuum, last_autovacuum, last_analyze, last_autoanalyze, reloptions,
		n_mod_since_analyze, n_ins_since_vacuum, fill_factor, relfrozenxid)
    SELECT
        nm.nspname AS schema_name,
        c_tbl.relname AS table_name,
        NULL AS index_name,
        CASE c_tbl.relkind
            WHEN ''r'' THEN ''ordinary table''
            WHEN ''S'' THEN ''sequence''
            WHEN ''t'' THEN ''TOAST table''
            WHEN ''v'' THEN ''view'' 
            WHEN ''m'' THEN ''materialized view'' 
            WHEN ''c'' THEN ''composite type'' 
            WHEN ''f'' THEN ''foreign table'' 
            WHEN ''p'' THEN ''partitioned table''
            ELSE ''unknown''
        END AS index_type,
        NULL AS index_definition,
        GREATEST(c_tbl.reltuples, 0) AS estimated_tuples,
        GREATEST(stat.last_vacuum, stat.last_autovacuum, stat.last_analyze, stat.last_autoanalyze) AS estimated_tuples_as_of,
        stat.n_dead_tup AS dead_tuples,
		CAST(NULL AS BOOLEAN) AS is_unique,
        CAST(NULL AS BOOLEAN) AS is_primary,
        c_tbl.oid AS table_oid,
        CAST(NULL AS INTEGER) AS index_oid,
		c_tbl.relkind,
        c_tbl.reltoastrelid,
		 stat.last_vacuum, stat.last_autovacuum, stat.last_analyze, stat.last_autoanalyze,
		c_tbl.reloptions, '
		|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
				        WHERE c.table_schema = 'pg_catalog'
				          AND c.table_name = 'pg_stat_user_tables'
				          AND c.column_name = 'n_mod_since_analyze')
				THEN ' stat.n_mod_since_analyze, '
				ELSE ' NULL, ' END
		|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
				        WHERE c.table_schema = 'pg_catalog'
				          AND c.table_name = 'pg_stat_user_tables'
				          AND c.column_name = 'n_ins_since_vacuum')
				THEN ' stat.n_ins_since_vacuum '
				ELSE ' NULL ' END || ',
		COALESCE(
            NULLIF((regexp_match(c_tbl.reloptions::text, ''fillfactor=(\d+)''))[1], '''')::int,
            -- Default fillfactor for indexes and tables
            100
        ) AS fillfactor,
		c_tbl.relfrozenxid
    FROM
        pg_catalog.pg_class c_tbl
    JOIN pg_catalog.pg_namespace nm ON
        c_tbl.relnamespace = nm.oid
    LEFT JOIN
        pg_catalog.pg_stat_user_tables stat ON
        stat.relid = c_tbl.oid
    WHERE
        (nm.nspname = ' || COALESCE(quote_literal(v_schema_name), 'nm.nspname') || ')
        AND (c_tbl.relname = ' || COALESCE(quote_literal(v_table_name), 'c_tbl.relname') || ')
        AND c_tbl.relkind NOT IN (''i'', ''I'', ''t'');';

	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'sql_to_execute: %', sql_to_execute;
	END IF;

    EXECUTE sql_to_execute;


    -- Build SQL for TOAST Tables
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Build SQL for TOAST Tables';
	END IF;

    sql_to_execute := '
    INSERT INTO ci_indexes (schema_name, table_name, index_name, index_type, index_definition, estimated_tuples, estimated_tuples_as_of, 
							dead_tuples, is_unique, is_primary, table_oid, index_oid, relkind, reloptions, relfrozenxid)
    SELECT
        c_tbl.schema_name AS schema_name,
        c_tbl.table_name AS table_name,
        c_toast_tbl.relname AS index_name,
        ''toast'' AS index_type,
        NULL AS index_definition,
        NULL AS estimated_tuples,
        NULL AS estimated_tuples_as_of,
		NULL AS dead_tuples,
        NULL AS is_unique,
        NULL AS is_primary,
        c_tbl.table_oid AS table_oid,
        c_toast_tbl.oid AS index_oid,
        c_toast_tbl.relkind AS relkind,
		c_tbl.reloptions,
		c_toast_tbl.relfrozenxid
    FROM
        ci_indexes c_tbl
    JOIN 
        pg_catalog.pg_class c_toast_tbl
        ON c_tbl.reltoastrelid = c_toast_tbl.oid
	WHERE c_tbl.relkind NOT IN (''i'', ''I'', ''t'');';

	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'sql_to_execute: %', sql_to_execute;
	END IF;

    EXECUTE sql_to_execute;


    -- Build SQL for the underlying ordinary tables of the partitioned tables
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Build SQL for the underlying ordinary tables of the partitioned tables';
	END IF;

    sql_to_execute := '
    INSERT INTO ci_indexes (schema_name, table_name, index_name, index_type, index_definition, estimated_tuples, estimated_tuples_as_of, dead_tuples, 
		is_unique, is_primary, table_oid, index_oid, relkind, reltoastrelid, last_manual_nonfull_vacuum, last_autovacuum, last_analyze, 
		last_autoanalyze, reloptions, n_mod_since_analyze, n_ins_since_vacuum, fill_factor, relfrozenxid)
    SELECT
        nm.nspname AS schema_name,
        c_tbl.relname AS table_name,
        NULL AS index_name,
        CASE c_tbl.relkind
            WHEN ''r'' THEN ''ordinary table''
            WHEN ''S'' THEN ''sequence''
            WHEN ''t'' THEN ''TOAST table''
            WHEN ''v'' THEN ''view'' 
            WHEN ''m'' THEN ''materialized view'' 
            WHEN ''c'' THEN ''composite type'' 
            WHEN ''f'' THEN ''foreign table'' 
            WHEN ''p'' THEN ''partitioned table''
            ELSE ''unknown''
        END AS index_type,
        NULL AS index_definition,
        GREATEST(c_tbl.reltuples, 0) AS estimated_tuples,
        GREATEST(stat.last_vacuum, stat.last_autovacuum, stat.last_analyze, stat.last_autoanalyze) AS estimated_tuples_as_of,
        stat.n_dead_tup AS dead_tuples,
        CAST(NULL AS BOOLEAN) AS is_unique,
        CAST(NULL AS BOOLEAN) AS is_primary,
        c_tbl.oid AS table_oid,
        CAST(NULL AS INTEGER) AS index_oid,
		c_tbl.relkind,
        c_tbl.reltoastrelid,
		stat.last_vacuum, stat.last_autovacuum, stat.last_analyze, stat.last_autoanalyze,
		c_tbl.reloptions, '
		|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
				        WHERE c.table_schema = 'pg_catalog'
				          AND c.table_name = 'pg_stat_user_tables'
				          AND c.column_name = 'n_mod_since_analyze')
				THEN ' stat.n_mod_since_analyze, '
				ELSE ' NULL, ' END
		|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
				        WHERE c.table_schema = 'pg_catalog'
				          AND c.table_name = 'pg_stat_user_tables'
				          AND c.column_name = 'n_ins_since_vacuum')
				THEN ' stat.n_ins_since_vacuum '
				ELSE ' NULL ' END || ',
		COALESCE(
            NULLIF((regexp_match(c_tbl.reloptions::text, ''fillfactor=(\d+)''))[1], '''')::int,
            -- Default fillfactor for indexes and tables
            100
        ) AS fillfactor,
		c_tbl.relfrozenxid
    FROM pg_catalog.pg_inherits inh 
    JOIN pg_catalog.pg_class c_tbl ON inh.inhrelid = c_tbl.oid
    JOIN pg_catalog.pg_namespace nm ON
        c_tbl.relnamespace = nm.oid
    LEFT JOIN
        pg_catalog.pg_stat_user_tables stat ON
        stat.relid = c_tbl.oid
	WHERE c_tbl.relkind NOT IN (''i'', ''I'', ''t'')
    AND EXISTS (SELECT 1 FROM ci_indexes WHERE inhparent = table_oid)         --Only add in the inheritents of a table you are looking at already
    AND NOT EXISTS (SELECT 1 FROM ci_indexes WHERE c_tbl.oid = table_oid);';  --Don't add it in twice if you asked for null and got all tables above

	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'sql_to_execute: %', sql_to_execute;
	END IF;

    EXECUTE sql_to_execute;




    -- Build SQL for Indexes
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Build SQL for Indexes';
	END IF;
    sql_to_execute := '
    INSERT INTO ci_indexes (schema_name, table_name, index_name, index_type, estimated_tuples, estimated_tuples_as_of, 
		dead_tuples, last_autovacuum, last_manual_nonfull_vacuum, is_unique, is_primary, table_oid, index_oid, relkind, reloptions,
		fill_factor)
    SELECT
        c_tbl.schema_name AS schema_name,
        c_tbl.table_name AS table_name,
        c_ix.relname AS index_name,
        am.amname AS index_type,
        GREATEST(COALESCE(c_ix.reltuples, c_tbl.estimated_tuples, 0), 0) AS estimated_tuples,
        GREATEST(stat.last_vacuum, stat.last_autovacuum, stat.last_analyze, stat.last_autoanalyze) AS estimated_tuples_as_of,
        c_tbl.dead_tuples,
		stat.last_autovacuum,
		stat.last_vacuum,
        indisunique AS is_unique,
        indisprimary AS is_primary,
        c_tbl.table_oid AS table_oid,
        c_ix.oid AS index_oid,
        c_ix.relkind,
		c_ix.reloptions,
		COALESCE(
            NULLIF((regexp_match(c_ix.reloptions::text, ''fillfactor=(\d+)''))[1], '''')::int,
            -- Default fillfactor for indexes and tables
            90
        ) AS fillfactor
    FROM
        ci_indexes c_tbl
    JOIN 
        pg_catalog.pg_index i ON
        c_tbl.table_oid = i.indrelid
    JOIN
        pg_catalog.pg_class c_ix ON
        i.indexrelid = c_ix.oid
    LEFT JOIN
        pg_catalog.pg_am am ON
        am.oid = c_ix.relam
    LEFT JOIN
        pg_catalog.pg_stat_all_indexes psai ON
        psai.indexrelid = i.indexrelid
    LEFT JOIN
        pg_catalog.pg_stat_user_tables stat ON
        stat.relid = i.indrelid
	WHERE c_tbl.relkind NOT IN (''i'', ''I'', ''t'');';

	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'sql_to_execute: %', sql_to_execute;
	END IF;

    EXECUTE sql_to_execute;


	-- Get Object Sizes Except Stuff Being Vacuumed
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Get Object Sizes Except Stuff Being Vacuumed';
	END IF;
	UPDATE ci_indexes tbl
		SET size_kb = pg_relation_size(COALESCE(tbl.index_oid, tbl.table_oid)) / 1024.0,
			index_definition = pg_get_indexdef(tbl.index_oid) || ';'
		WHERE COALESCE(tbl.index_oid, tbl.table_oid) IS NOT NULL
		AND tbl.table_oid NOT IN (SELECT relid FROM pg_catalog.pg_stat_progress_cluster);


	-- Update partitioned index data to include all child indexes and tables
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Update partitioned index data to include all child indexes and tables';
	END IF;

	UPDATE ci_indexes tbl
		SET size_kb = child.size_kb,
			estimated_tuples = CASE WHEN tbl.estimated_tuples <= 0
			                                                THEN child.reltuples
			                                                ELSE tbl.estimated_tuples END,
			dead_tuples = CASE WHEN tbl.dead_tuples <= 0
			                                                THEN child.dead_tuples
			                                                ELSE tbl.dead_tuples END
	FROM (SELECT inh.inhparent, SUM(pg_relation_size(child.oid) / 1024.0) AS size_kb,
			SUM(GREATEST(COALESCE(child.reltuples, 0), 0)) AS reltuples,
			SUM(COALESCE(stat.n_dead_tup, 0)) AS dead_tuples
		FROM pg_catalog.pg_inherits inh 
		JOIN pg_catalog.pg_class child ON inh.inhrelid = child.oid
		LEFT OUTER JOIN pg_catalog.pg_stat_user_tables stat ON inh.inhrelid = stat.relid
		GROUP BY inh.inhparent
		) child
	WHERE tbl.relkind IN ('p', 'I')
	  AND tbl.size_kb = 0
	  AND COALESCE(tbl.index_oid, tbl.table_oid) = child.inhparent;

	-- Update partitioned indexes if necessary to match the table's dead_tuples:
	UPDATE ci_indexes ix
		SET dead_tuples = COALESCE(tbl_stats.dead_tuples, 0)
	FROM (SELECT tbl.table_oid, SUM(COALESCE(tbl.dead_tuples, 0)) AS dead_tuples
		FROM ci_indexes tbl
		WHERE tbl.relkind = 'p'
		GROUP BY tbl.table_oid) tbl_stats
	WHERE ix.relkind = 'I'
	  AND ix.table_oid = tbl_stats.table_oid
	  AND ix.dead_tuples <= 0;


	-- Set the drop_object_command column contents
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Set the drop_object_command column contents';
	END IF;

	UPDATE ci_indexes ix
		SET drop_object_command = CASE
		    WHEN ix.index_type = 'ordinary table' THEN 'DROP TABLE IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'sequence' THEN 'DROP SEQUENCE IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'view' THEN 'DROP VIEW IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'materialized view' THEN 'DROP MATERIALIZED VIEW IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'composite type' THEN 'DROP TYPE IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'foreign table' THEN 'DROP FOREIGN TABLE IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type = 'partitioned table' THEN 'DROP TABLE IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.table_name) || '; -- CASCADE ' 
		    WHEN ix.index_type IN ('brin', 'btree', 'gin', 'gist', 'hash', 'spgist')
		        			THEN 'DROP INDEX IF EXISTS ' || quote_ident(ix.schema_name) || '.' || quote_ident(ix.index_name) || '; -- CASCADE ' 
		    ELSE '' -- Not dropping TOAST tables or unknown types
	END;


	-- Process warnings.

	--1: Vacuum Full or Cluster Running Now
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '1: Vacuum Full or Cluster Running Now';
	END IF;

	INSERT INTO ci_indexes_warnings (table_oid, index_oid, priority, warning_summary, warning_details, url)
	SELECT i.table_oid, i.index_oid, 1, 
		'Vacuum Full or Cluster Running Now' AS warning_summary,
		'The table is offline right now for maintenance. '
			|| ' Command: ' || prog.command 
			|| ' Phase: ' || prog.phase 
			|| ' heap_tuples_scanned: ' || prog.heap_tuples_scanned 
			|| ' heap_tuples_written: ' || prog.heap_tuples_written
			|| ' heap_blks_total: ' || prog.heap_blks_total
			|| ' heap_blks_scanned: ' || prog.heap_blks_scanned
			|| ' index_rebuild_count: ' || prog.index_rebuild_count
			 AS warning_details,
	'https://smartpostgres.com/problems/vacuum-running-now' AS url
	FROM ci_indexes i
		JOIN pg_catalog.pg_stat_progress_cluster prog
			on i.table_oid = prog.relid;


	--10: Transaction ID Wraparound Risk
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '10: Transaction ID Wraparound Risk';
	END IF;

	WITH table_freeze_settings AS (
	    SELECT 
	        c.table_oid, c.index_oid,
	        greatest(age(c.relfrozenxid), age(t.relfrozenxid)) AS greatest_age,
	        COALESCE(freeze_params.freeze_max_age, s.setting::int) AS freeze_max_age,
			s.setting::int AS server_default_freeze_max_age
	    FROM ci_indexes c
	    LEFT JOIN ci_indexes t ON c.reltoastrelid = t.table_oid
	    JOIN pg_settings s ON s.name = 'autovacuum_freeze_max_age'
	    LEFT JOIN LATERAL (
	        SELECT (regexp_match(unnest(c.reloptions), 'autovacuum_freeze_max_age=(\d+)'))[1]::int AS freeze_max_age
	        WHERE EXISTS (SELECT 1 FROM unnest(c.reloptions) opt WHERE opt LIKE 'autovacuum_freeze_max_age=%')
	    ) freeze_params ON TRUE
	    WHERE c.relkind IN ('r', 'm')
	)
	INSERT INTO ci_indexes_warnings (table_oid, index_oid, priority, warning_summary, warning_details, url)
	SELECT tfs.table_oid, tfs.index_oid, 10, 
		'Transaction ID Wraparound Risk' AS warning_summary,
		'Autovacuum was supposed to kick in by now to prevent transaction ID wraparounds, but it has not. '
			|| ' Transaction age (int, qty of transactions, not date) from relfrozenxid: ' || tfs.greatest_age::varchar
			|| ' autovacuum_freeze_max_age (also int, qty of transactions) '
			|| CASE WHEN freeze_max_age = server_default_freeze_max_age THEN ' from server default: '
				ELSE ' set by table-level override in reloptions: ' END
			|| tfs.freeze_max_age::varchar
			 AS warning_details,
	'https://smartpostgres.com/problems/transaction-id-wraparound' AS url
	FROM table_freeze_settings tfs
	WHERE greatest_age >= freeze_max_age;




	--50: Autovacuum Not Keeping Up
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '50: Autovacuum Not Keeping Up';
	END IF;

	WITH settings AS (
	    -- Get the default autovacuum settings from the server
	    SELECT 
	        (SELECT setting::integer FROM pg_settings WHERE name = 'autovacuum_vacuum_threshold') AS vacuum_threshold,
	        (SELECT setting::float FROM pg_settings WHERE name = 'autovacuum_vacuum_scale_factor') AS vacuum_scale_factor,
	        (SELECT setting::boolean FROM pg_settings WHERE name = 'autovacuum') AS autovacuum_enabled
	),
	table_vacuum_settings AS (
	    -- Calculate the autovacuum thresholds per table
	    SELECT 
	        c_tbl.table_oid,
	        psut.n_dead_tup,
	        COALESCE((
	            SELECT substring(option FROM 'autovacuum_vacuum_threshold=([0-9]+)')::integer
	            FROM unnest(c_tbl.reloptions) AS option
	            WHERE option LIKE 'autovacuum_vacuum_threshold%'
	        ), settings.vacuum_threshold) AS autovacuum_vacuum_threshold,
	        COALESCE((
	            SELECT substring(option FROM 'autovacuum_vacuum_scale_factor=([0-9\.]+)')::float
	            FROM unnest(c_tbl.reloptions) AS option
	            WHERE option LIKE 'autovacuum_vacuum_scale_factor%'
	        ), settings.vacuum_scale_factor) AS autovacuum_vacuum_scale_factor,
	        COALESCE((
	            SELECT split_part(option, '=', 2)::boolean
	            FROM unnest(c_tbl.reloptions) AS option
	            WHERE option LIKE 'autovacuum_enabled%'
	        ), settings.autovacuum_enabled) AS autovacuum_enabled,
	        c_tbl.estimated_tuples
	    FROM 
			ci_indexes c_tbl
		JOIN
	        pg_stat_user_tables psut ON c_tbl.table_oid = psut.relid
	    CROSS JOIN settings
		WHERE c_tbl.index_oid IS NULL
	)
	INSERT INTO ci_indexes_warnings (table_oid, priority, warning_summary, warning_details, url)
	SELECT 
	    tvs.table_oid, 
		50 as priority, 'Autovacuum Not Keeping Up' as warning_summary,
		'Vacuum threshold for this object: '
			|| (tvs.autovacuum_vacuum_threshold + (tvs.autovacuum_vacuum_scale_factor * tvs.estimated_tuples))::varchar
			|| ' tuples.' as warning_details,
		'https://smartpostgres.com/problems/autovacuum-not-keeping-up' AS url
	FROM 
	    table_vacuum_settings tvs
	WHERE 
	    -- Show tables where dead tuples exceed the effective autovacuum threshold
	    tvs.n_dead_tup > (tvs.autovacuum_vacuum_threshold + (tvs.autovacuum_vacuum_scale_factor * tvs.estimated_tuples)) * 1.1
		AND tvs.autovacuum_enabled <> false;





	--100: Outdated Statistics
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '100: Outdated Statistics';
	END IF;

	INSERT INTO ci_indexes_warnings (table_oid, index_oid, priority, warning_summary, warning_details, url)
	SELECT i.table_oid, i.index_oid, 100, 
		'Outdated Statistics' AS warning_summary,
		'Query plans may have invalid estimates. ' 
			|| i.estimated_tuples::varchar || ' estimated tuples from pg_class.reltuples. ' 
			|| i.n_ins_since_vacuum::varchar || ' tuples ins_since_last_vacuum. ' 
			|| ' last_manual_nonfull_vacuum on ' || COALESCE(i.last_manual_nonfull_vacuum::date::varchar, '(never)')
			|| '. last_autovacuum on ' || COALESCE(i.last_autovacuum::date::varchar, '(never)') || '. '
			|| i.n_mod_since_analyze::varchar || ' mod_since_analyze.' 
			|| ' last_analyze on ' || COALESCE(i.last_analyze::date::varchar, '(never)')
			|| '. last_autoanalyze on ' || COALESCE(i.last_autoanalyze::date::varchar, '(never)') AS warning_details,
	'https://smartpostgres.com/problems/outdated-statistics' AS url
	FROM ci_indexes i
    WHERE ABS(i.estimated_tuples::numeric) * 0.1 < GREATEST(i.n_ins_since_vacuum, i.n_mod_since_analyze);



	--150: Vacuum Running Now
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '150: Vacuum Running Now';
	END IF;

    sql_to_execute := '
	INSERT INTO ci_indexes_warnings (table_oid, index_oid, priority, warning_summary, warning_details, url)
	SELECT i.table_oid, i.index_oid, 150, 
		''Vacuum Running Now'' AS warning_summary,
		''The table is online, but maintenance is happening: ''
			|| '' Phase: '' || prog.phase 
			|| '' heap_blks_total: '' || prog.heap_blks_total
			|| '' heap_blks_scanned: '' || prog.heap_blks_scanned
			|| '' heap_blks_vacuumed: '' || prog.heap_blks_vacuumed
			|| '' index_vacuum_count: '' || prog.index_vacuum_count '
			|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
					        WHERE c.table_schema = 'pg_catalog'
					          AND c.table_name = 'pg_stat_progress_vacuum'
					          AND c.column_name = 'max_dead_tuple_bytes')
					THEN ' || '' max_dead_tuple_bytes: '' || prog.max_dead_tuple_bytes '
					ELSE '' END
			|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
					        WHERE c.table_schema = 'pg_catalog'
					          AND c.table_name = 'pg_stat_progress_vacuum'
					          AND c.column_name = 'dead_tuple_bytes')
					THEN ' || '' dead_tuple_bytes: '' || prog.dead_tuple_bytes '
					ELSE '' END
			|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
					        WHERE c.table_schema = 'pg_catalog'
					          AND c.table_name = 'pg_stat_progress_vacuum'
					          AND c.column_name = 'num_dead_item_ids')
					THEN ' || '' num_dead_item_ids: '' || prog.num_dead_item_ids '
					ELSE '' END
			|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
					        WHERE c.table_schema = 'pg_catalog'
					          AND c.table_name = 'pg_stat_progress_vacuum'
					          AND c.column_name = 'indexes_total')
					THEN ' || '' indexes_total: '' || prog.indexes_total '
					ELSE '' END
			|| CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
					        WHERE c.table_schema = 'pg_catalog'
					          AND c.table_name = 'pg_stat_progress_vacuum'
					          AND c.column_name = 'indexes_processed')
					THEN ' || '' indexes_processed: '' || prog.indexes_processed '
					ELSE '' END
			|| ' AS warning_details,
	''https://smartpostgres.com/problems/vacuum-running-now'' AS url
	FROM ci_indexes i
		JOIN pg_catalog.pg_stat_progress_vacuum prog
			on i.table_oid = prog.relid;';

	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'sql_to_execute: %', sql_to_execute;
	END IF;

	EXECUTE sql_to_execute;







	--200: Autovacuum Settings Specified
	IF v_debug_level >= 2 THEN
		RAISE NOTICE '200: Autovacuum Settings Specified';
	END IF;

	INSERT INTO ci_indexes_warnings (table_oid, index_oid, priority, warning_summary, warning_details, url)
	SELECT i.table_oid, i.index_oid, 200, 
		'Autovacuum Settings Specified' AS warning_summary,
		'See the reloptions column for details. Someone set the settings for this specific object.' AS warning_details,
	'https://smartpostgres.com/problems/autovacuum-settings-specified' AS url
	FROM ci_indexes i
    WHERE array_to_string(i.reloptions, ', ') like '%autovacuum%';


    -- Return the result set
	IF v_debug_level >= 2 THEN
		RAISE NOTICE 'Return the result set';
	END IF;

    RETURN QUERY
    SELECT quote_ident(ci.schema_name) as schema_name, 
		quote_ident(ci.table_name) as table_name,
		quote_ident(ci.index_name) as index_name, 
		ci.index_type, ci.index_definition, ci.size_kb, ci.estimated_tuples,
		ci.estimated_tuples_as_of, 
		ci.dead_tuples, ci.last_autovacuum, ci.last_manual_nonfull_vacuum,
		ci.fill_factor,
		ci.is_unique, ci.is_primary,
		ci.table_oid, ci.index_oid,
		w.priority, w.warning_summary, w.warning_details, w.url,
		ci.reloptions,
		ci.drop_object_command
    FROM ci_indexes ci
	LEFT OUTER JOIN ci_indexes_warnings w 
		ON ci.table_oid = w.table_oid
		AND (ci.index_oid = w.index_oid OR (ci.index_oid IS NULL AND w.index_oid IS NULL))
    ORDER BY 1, 2, 3, w.priority, w.warning_summary;

    DROP TABLE ci_indexes;
    DROP TABLE ci_indexes_warnings;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: badges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.badges (
    id integer NOT NULL,
    userid integer,
    name character varying(50),
    date timestamp without time zone,
    class smallint
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id integer NOT NULL,
    postid integer,
    score integer,
    text character varying(600),
    creationdate timestamp without time zone,
    userdisplayname character varying(40),
    userid integer,
    contentlicense character varying(12)
);


--
-- Name: postlinks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.postlinks (
    id integer NOT NULL,
    creationdate timestamp without time zone,
    postid integer,
    relatedpostid integer,
    linktypeid smallint
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id integer NOT NULL,
    posttypeid smallint NOT NULL,
    acceptedanswerid integer,
    parentid integer,
    creationdate timestamp without time zone NOT NULL,
    deletiondate timestamp without time zone,
    score integer,
    viewcount integer,
    body text,
    owneruserid integer DEFAULT 0,
    ownerdisplayname character varying(40),
    lasteditoruserid integer,
    lasteditordisplayname character varying(40),
    lasteditdate timestamp without time zone,
    lastactivitydate timestamp without time zone,
    title character varying(250),
    tags character varying(250),
    answercount integer,
    commentcount integer,
    favoritecount integer,
    closeddate timestamp without time zone,
    communityowneddate timestamp without time zone,
    contentlicense character varying(12)
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id integer NOT NULL,
    tagname character varying(35) NOT NULL,
    count integer NOT NULL,
    excerptpostid integer,
    wikipostid integer,
    ismoderatoronly bit(1),
    isrequired bit(1)
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    reputation integer,
    creationdate timestamp without time zone,
    displayname character varying(40),
    lastaccessdate timestamp without time zone,
    websiteurl character varying(200),
    location character varying(100),
    aboutme text,
    views integer,
    upvotes integer,
    downvotes integer,
    profileimageurl character varying(200),
    emailhash character varying(32),
    accountid integer
);


--
-- Name: votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.votes (
    id integer NOT NULL,
    postid integer,
    votetypeid smallint,
    userid integer,
    creationdate timestamp without time zone,
    bountyamount integer
);


--
-- Name: badges pk_badges__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT pk_badges__id PRIMARY KEY (id);


--
-- Name: comments pk_comments__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT pk_comments__id PRIMARY KEY (id);


--
-- Name: postlinks pk_postlinks__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postlinks
    ADD CONSTRAINT pk_postlinks__id PRIMARY KEY (id);


--
-- Name: posts pk_posts__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT pk_posts__id PRIMARY KEY (id);


--
-- Name: tags pk_tags__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT pk_tags__id PRIMARY KEY (id);


--
-- Name: users pk_users__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users__id PRIMARY KEY (id);


--
-- Name: votes pk_votes__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT pk_votes__id PRIMARY KEY (id);


--
-- Name: badges_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX badges_userid ON public.badges USING btree (userid);


--
-- Name: comments_postid_creationdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comments_postid_creationdate ON public.comments USING btree (postid, creationdate);


--
-- Name: comments_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comments_userid ON public.comments USING btree (userid);


--
-- Name: postlinks_postid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX postlinks_postid ON public.postlinks USING btree (postid);


--
-- Name: posts_owneruserid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_owneruserid ON public.posts USING btree (owneruserid);


--
-- Name: posts_parentid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_parentid ON public.posts USING btree (parentid);


--
-- Name: posts_posttypeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_posttypeid ON public.posts USING btree (posttypeid);


--
-- Name: posts_score_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_score_tags ON public.posts USING btree (score, tags);


--
-- Name: posts_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_tags ON public.posts USING btree (tags);


--
-- Name: posts_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_title ON public.posts USING btree (title);


--
-- Name: users_creationdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_creationdate ON public.users USING btree (creationdate);


--
-- Name: users_displayname; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_displayname ON public.users USING btree (displayname);


--
-- Name: users_location_displayname; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_location_displayname ON public.users USING btree (location, displayname);


--
-- Name: users_reputation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_reputation ON public.users USING btree (reputation);


--
-- PostgreSQL database dump complete
--

\unrestrict rEmIeaVWrP0n5roECT4gTrCQXSUvlhAy3vxiSjrZBTluL9GQ0wiLXiOhG3byoki

