set search_path to postgres_air;

-- drop table if EXISTS postgres_air.boarding_pass_large;

create table postgres_air.boarding_pass_large
    (like postgres_air.boarding_pass);

truncate table postgres_air.boarding_pass_large;

-- Execute 3 times
INSERT INTO postgres_air.boarding_pass_large
SELECT * FROM postgres_air.boarding_pass;


-- create required index
create index boarding_pass_large__update_ts on boarding_pass_large (update_ts);

-- update stats
vacuum full postgres_air.boarding_pass_large;