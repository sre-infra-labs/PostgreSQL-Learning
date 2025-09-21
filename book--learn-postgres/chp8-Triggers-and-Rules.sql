-- drop table audit_logs;
create table audit_logs (
    table_name varchar(125) not null,
    table_unique_key_name varchar(125) null,
    table_unique_key_value varchar(125) null,
    data_row jsonb not null,
    operation_type varchar(20) not null,
    operation_by varchar(125) not null default current_role,
    operation_time timestamp not null default CURRENT_TIMESTAMP,
    client_app_name TEXT,
    client_host TEXT
);

create index audit_logs__operation_time on audit_logs (operation_time);
cluster audit_logs using audit_logs__operation_time;
alter table audit_logs set (autovacuum_enabled = ON);

-- create table users_new as table users; 
-- alter table users_new add constraint pk_users_new primary key (id);

CREATE OR REPLACE FUNCTION fn_tgr_audit_logs()
RETURNS TRIGGER AS $$
DECLARE
    pk_column_name TEXT := 'id';  -- Default PK column name
    pk_column_value TEXT := NULL; -- Default PK column value
    client_app_name TEXT := current_setting('application_name', true);
    client_host TEXT := inet_client_addr()::TEXT;
BEGIN
    -- Try to fetch the actual primary key column name
    SELECT a.attname INTO pk_column_name
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = TG_RELID
    AND i.indisprimary
    LIMIT 1;

    -- If no PK column is found, default to 'id'
    IF pk_column_name IS NULL THEN
        pk_column_name := 'id';
    END IF;

    -- Try to fetch the primary key value from OLD first, then NEW
    BEGIN
        EXECUTE format('SELECT ($1).%I', pk_column_name) INTO pk_column_value USING OLD;
    EXCEPTION
        WHEN OTHERS THEN
            pk_column_value := NULL;
    END;

    IF pk_column_value IS NULL THEN
        BEGIN
            EXECUTE format('SELECT ($1).%I', pk_column_name) INTO pk_column_value USING NEW;
        EXCEPTION
            WHEN OTHERS THEN
                pk_column_value := NULL;
        END;
    END IF;

    -- Insert audit record
    IF TG_OP IN ('UPDATE','DELETE') THEN
        INSERT INTO audit_logs (
            table_name, table_unique_key_name, table_unique_key_value, data_row, operation_type, operation_by, operation_time, client_app_name, client_host
        ) VALUES (
            TG_TABLE_NAME, pk_column_name, pk_column_value, row_to_json(OLD), TG_OP, current_role, CURRENT_TIMESTAMP, client_app_name, client_host
        );
    ELSE
        INSERT INTO audit_logs (
            table_name, table_unique_key_name, table_unique_key_value, data_row, operation_type, operation_by, operation_time, client_app_name, client_host
        ) VALUES (
            TG_TABLE_NAME, pk_column_name, pk_column_value, row_to_json(NEW), TG_OP, current_role, CURRENT_TIMESTAMP, client_app_name, client_host
        );
    END IF;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Create the trigger
-- DROP TRIGGER IF EXISTS tgr_users_new ON users_new;
CREATE TRIGGER tgr_users_new
AFTER INSERT OR UPDATE OR DELETE ON users_new
FOR EACH ROW EXECUTE FUNCTION fn_tgr_audit_logs();


select * from users_new;
select * from audit_logs;

-- 1,2,3,4,5,6,
update users_new set location = 'Rewa' where id = 1;
update users_new set location = 'Hyderabad' where id = 2;
delete from users_new where id = 3;

/*
prepare update_query(int,text) as update users_new set location = $2 where id = $1;
execute update_query(1,'Bangalore');

prepare delete_query(int) as delete from users_new where id = $1;
execute delete_query(2);

*/
