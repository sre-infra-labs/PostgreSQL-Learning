/* Fundamentals of Index Tuning
 * Module X: Why Varchar Columns Might Need Functional Indexes
 * 
 * v0.1 - 2025-03-26
 * https://smartpostgres.com/fundamentals/index-tuning
 * 
 * This demo works on any version of Postgres,
 * but requires the large users table:
 * https://smartpostgres.com/go/querystack
 * 
 * Licensed under Creative Commons CC BY-SA 4.0
 * Attribution-ShareAlike 4.0 International:
 * https://creativecommons.org/licenses/by-sa/4.0/
 */



/* Note to Brent - do location searching on users.location, talking about case sensitivity. */


/* start with no indexes: */
select * from drop_indexes('public', 'users');

