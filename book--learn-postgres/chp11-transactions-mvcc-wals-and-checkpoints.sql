/* ACID Property of Relational Database

A -> Atomicity
C -> Consistency
I -> Isolation
D -> Durability

*/

/*
Implicit vs Explicit Transactions

Every transaction is assigned a unique number, called the "transaction identifier", or xid.

PostgreSQL stores the "xid" that generates or modified the certain tuple within the tuple itself.
*/

-- get me current transaction
select current_time, txid_current();

-- get transaction (xmin) that created the tuple
select xmin, xmax, cmin, cmax, * from categories;

-- IMPORTANT: When you issue an explicit transaction, psql changes its prompt, adding an asterisk.

/*
forumdb=# 
forumdb=# begin;
BEGIN
forumdb=*# insert into tags (tag) values ('PHP');
INSERT 0 1
forumdb=*# insert into tags (tag) values ('C#');
INSERT 0 1
forumdb=*# commit;
COMMIT
forumdb=# 
*/

/*
As soon as a DML statement fails, PostgreSQL aborts the transaction and refuses to handle any other statement.
The only way you have to clear the situation is by ending the explicit transaction, 
and no matter which way you end it (either COMMIT or ROLLBACK), PostgreSQL will throw away your changes,
rolling back the current transaction.
*/

/*  Time within Transactions
Transactions are "time-discrete": the time does not change during a transaction.


begin;
select current_time;
select pg_sleep_for('5 seconds');
select current_time, clock_timestamp()::time;
commit;
*/

/*  More about transaction identifiers - the XID wraparound problem

xid value can range between -2^31 to +2^31.
In other terms, the "xid" counter is a cyclic value.
With this cyclic value, PostgreSQL makes lot of effort to avoid "xid wraparound problem".

PostgreSQL will start notify about xid wraparound problem in logs, and may eventually shutdown
the system to present data loss due to xid wraparound problem.


To avoid the "xid" wraparound, PostgreSQL implements so called "tuple freezing":
once a tuple is frozen, its xmin has tob e considered always in the past with 
respect to any running transaction, even if its xmin is higher in value than any currently
running transaction xid. In fact, a special bit of information that tells PostgreSQL if the 
tuple has been frozen or not.

Therefore, as the xid overflow approaches, VACCUM performs a wide freeze execution, marking
all the tuples in the past as frozen, so that even if the xid restarts it counting from
lower number, tuples already in the database will always appear in the past.

*/


