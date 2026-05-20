# [PostgreSQL for MSSQL Server DBAs | Chandra Pathivada | Postgres World Webinars 2025](https://youtu.be/PiT3Now868E?feature=shared)

## Contrastive Analysis

![contrastive_analysis](images--pg-for-mssql-dba/contrastive_analysis.png)

## Feature for Developers and DBAs
![pg-dev-and-dba-features](images--pg-for-mssql-dba/pg-dev-and-dba-features.png)

## What is O-RDBMS? Inheritence?
![what-is-o-rdbms](images--pg-for-mssql-dba/what-is-o-rdbms.png)

```
create table car (
    id serial primary key,
    make varchar(255),
    model varchar(255),
    year int
);

-- Create the child table 'sedan' inheriting from 'car' and adding specific attributes
create table sedan (
    fuel_type varchar(255),
    seats int
) inherits (car);

-- Create the child table 'suv' inheriting from 'car' and adding specific attributes
create table suv (
    offroad_capability varchar(255),
    cargo_capacity int
) inherits (car);

select * from car;

 id | make | model | year 
----+------+-------+------

select * from sedan;

 id | make | model | year | fuel_type | seats 
----+------+-------+------+-----------+-------

```

## RDBMS vs O-RDBMS

![ordbms-polymorphism](images--pg-for-mssql-dba/ordbms-polymorphism.png)

## Postgres - Extensions

![postgres-extensions](images--pg-for-mssql-dba/postgres-extensions.png)

## Case Sensitivity in Data

![case-sensitivity-in-data](images--pg-for-mssql-dba/case-sensitivity-in-data.png)

## Case in-sensitive searches in PostgreSQL

![case-insensitive-searches](images--pg-for-mssql-dba/case-insensitive-searches.png)

## Case Sensitivity in Schema

![case-sensitivity-in-schema](images--pg-for-mssql-dba/case-sensitivity-in-schema.png)

## Datatype (differences)

![datatypes-diff](images--pg-for-mssql-dba/datatypes-diff.png)

![datatypes-diff-2](images--pg-for-mssql-dba/datatypes-diff-2.png)

## Identity Keys

![identity-keys](images--pg-for-mssql-dba/identity-keys.png)

## Concurrency Control

![concurrency-control](images--pg-for-mssql-dba/concurrency-control.png)

## Transaction Isolation Levels

![transaction-isolation-levels](images--pg-for-mssql-dba/transaction-isolation-levels.png)

## System Databases

![system-databases](images--pg-for-mssql-dba/system-databases.png)

## User Databases

![user-databases](images--pg-for-mssql-dba/user-databases.png)

## Tables

![tables](images--pg-for-mssql-dba/tables.png)

## Indexes

![indexes](images--pg-for-mssql-dba/indexes.png)

## Statistics

![statistics](images--pg-for-mssql-dba/statistics.png)

## Other Objects

![other-objects](images--pg-for-mssql-dba/other-objects.png)

## Why can't I print a message in PostgreSQL

![why-cant-i-print-message-in-postgresql](images--pg-for-mssql-dba/why-cant-i-print-message-in-postgresql.png)

## TSQL vs PL/PgSQL

![tsql-vs-pl-pgsql](images--pg-for-mssql-dba/tsql-vs-pl-pgsql.png)

## TSQL vs PL/PgSQL - Block Structured

![plpgsql-block-structured-programming-language](images--pg-for-mssql-dba/plpgsql-block-structured-programming-language.png)

![plpgsql-block-structured-code](images--pg-for-mssql-dba/plpgsql-block-structured-code.png)

## Print Variable

![print-variable](images--pg-for-mssql-dba/print-variable.png)

## Functions

![functions](images--pg-for-mssql-dba/functions.png)

![functions-2](images--pg-for-mssql-dba/functions-2.png)

## Table Valued Functions

![table-valued-functions](images--pg-for-mssql-dba/table-valued-functions.png)

## Functions vs Procedures
![functions-vs-procedures](images--pg-for-mssql-dba/functions-vs-procedures.png)

## Exception Handling

![exception-handling](images--pg-for-mssql-dba/exception-handling.png)

![exception-handling-example](images--pg-for-mssql-dba/exception-handling-example.png)

![exception-handling-capture-any-error](images--pg-for-mssql-dba/exception-handling-capture-any-error.png)

## Security

![security](images--pg-for-mssql-dba/security.png)

## Backups

![backups](images--pg-for-mssql-dba/backups.png)

## Replication

![replication](images--pg-for-mssql-dba/replication.png)

## Import/Export

![import-export](images--pg-for-mssql-dba/import-export.png)

## Monitoring - Vacuum and Backups

![monitoring-vacuum-and-backups](images--pg-for-mssql-dba/monitoring-vacuum-and-backups.png)

## Monitoring DMVs

![monitoring-dmvs](images--pg-for-mssql-dba/monitoring-dmvs.png)



time-travel-queries-with-postgres