/* Anti Join
** An anti-join between two tables R and S returns rows from table R for which
**   there are no rows from tale S with a matching value in the joining column
**
**
*/

set search_path to postgres_air;


/* Defining an anti-join using the NOT EXISTS keyword */
EXPLAIN 
(ANALYZE, COSTS, VERBOSE, BUFFERS)
SELECT * FROM flight f WHERE NOT EXISTS
    (SELECT flight_id FROM booking_leg WHERE flight_id=f.flight_id);
/*
Gather  (cost=1000.44..192415.96 rows=466505 width=71)
  Workers Planned: 2
  ->  Nested Loop Anti Join  (cost=0.44..144765.46 rows=194377 width=71)
        ->  Parallel Seq Scan on flight f  (cost=0.00..11470.58 rows=284658 width=71)
        ->  Index Only Scan using booking_leg__flight_id on booking_leg  (cost=0.44..1.98 rows=83 width=4)
              Index Cond: (flight_id = f.flight_id)
JIT:
  Functions: 3
  Options: Inlining false, Optimization false, Expressions true, Deforming true
*/



/* Defining an anti-join using NOT IN */
EXPLAIN
--(ANALYZE, COSTS, VERBOSE, BUFFERS)
SELECT * FROM flight f WHERE flight_id not in 
    (SELECT flight_id FROM booking_leg);
/*
Gather  (cost=1000.00..73245041651.76 rows=341589 width=71)
  Workers Planned: 2
  ->  Parallel Seq Scan on flight f  (cost=0.00..73245006492.86 rows=142329 width=71)
        Filter: (NOT (SubPlan 1))
        SubPlan 1
          ->  Materialize  (cost=0.00..469884.49 rows=17893566 width=4)
                ->  Seq Scan on booking_leg  (cost=0.00..310519.66 rows=17893566 width=4)
JIT:
  Functions: 6
  Options: Inlining true, Optimization true, Expressions true, Deforming true
*/


/* Defining anti-join using LEFT JOIN */
EXPLAIN
(ANALYZE, COSTS, VERBOSE, BUFFERS)
SELECT *
FROM flight f
LEFT JOIN booking_leg bl USING (flight_id)
WHERE bl.flight_id is null;
/*
Gather  (cost=1000.44..195884.18 rows=466505 width=92)
  Workers Planned: 2
  ->  Nested Loop Anti Join  (cost=0.44..148233.68 rows=194377 width=92)
        ->  Parallel Seq Scan on flight f  (cost=0.00..11470.58 rows=284658 width=71)
        ->  Index Scan using booking_leg__flight_id on booking_leg bl  (cost=0.44..2.75 rows=83 width=25)
              Index Cond: (flight_id = f.flight_id)
JIT:
  Functions: 5
  Options: Inlining false, Optimization false, Expressions true, Deforming true
*/