# Fundamentals of Index Tuning

## Remaining Tasks

### Structure to add:

* How to review a new table: columns you filter on, columns you join on, leaderboard columns for order-by. Lab: tackle all tables in the Stack Overflow database.
* Load test: before & after, set of random queries, random parameters. How to measure success with that load test. Why this isn't like real life (because we're going to measure by overall time.)
* How to review an existing table with a bunch of indexes: deduping, measuring space used before/after.

### Load testing

How to get pgbench to load all the scripts in a folder, and run them with equal weighting, from ChatGPT:

```
SCRIPTS=$(ls ./5-workload/*.sql | sed 's/^/--file=/')
pgbench -c 10 -T 60 $SCRIPTS
```

* Proof of concept: write 3 scripts to test with, install pgbench, run proof of concept test to see that it works
* Write select-only load test scenario for Fundamentals of Index Tuning
* Write class module to:
		* Install pgbench
		* Run select-only load test w/o indexes
		* Lab exercise to put in the right indexes
		* Run select-only load test w/indexes
		* Discuss blocking's impact on indexes
		* Run read/write load test w/indexes
		* Revisit whether things got significantly worse, to the point where you may need to cut back on indexes.
		* Lecture: how to understand which indexes are getting used


### Marketing:

* List of DBeaver keyboard shortcuts

## Target Attendee



### Things They Know



### Things They Don't Know

* How to read the BUFFERS output of EXPLAIN - so we wrote this because this knowledge is required for the course: https://smartpostgres.com/posts/how-to-read-the-buffers-numbers-in-explain-plans/
* How to read the output of check_indexes
* How to read the output of EXPLAIN
* How to compare before & after EXPLAINs so they can quantify improvement
* How many indexes is enough, too many, or not enough
* How many columns on an index are enough, too many, not enough
* What order columns should go on an index

## What the Class Will Teach

These are not in order:

* How Postgres chooses one index over another, or multiple indexes
* How to choose the order of key columns in an index
* How Postgres chooses which table to process first in a multi-table query



## Out of Scope

* Any index types other than B-tree
* How to measure wait stats to determine:
  * Whether you have a blocking problem, and thus too many indexes
  * Whether you have a storage read problem, and thus not enough indexes

## Class Takeaways

Now you know:

* How many indexes to create on a table without feeling guilty
* How many columns to use, and on what types of datatypes, on each index without feeling guilty
* How to review indexes on an existing table with check_indexes()
* How to create indexes for a specific query
* How to recognize common index design mistakes and fix them
* How to gauge the success of your work (space used by indexes, query speed)