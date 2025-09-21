/* Parallelism
** 
** Parallelism can be viewed as yet another way to split up the query:
the amount of work needed to execute a query is divided between processing units.
**
** Sometimes an optimizer may replace index-based access (that would be used within sequential execution) with
a parallel table scan. If the happened due to imprecise cost estimation, then parallel execution may be slower
than sequential execution.
**
** IMPORTANT: scalability benefits from parallelism are at best linear, while the cost of nested loops is quadratic.
*/

set max_parallel_workers_per_gather = 0;
set parallel_setup_cost = 1;