/* Using SET operations
** EXCEPT, INTERSECT, UNION
**
*/

SELECT flight_id FROM flight f
  EXCEPT
  SELECT flight_id FROM booking_leg

SELECT flight_id FROM flight f
  INTERSECT
  SELECT flight_id FROM booking_leg

EXPLAIN
(ANALYZE, COSTS, VERBOSE, BUFFERS)
SELECT *
FROM flight f
LEFT JOIN booking_leg bl USING (flight_id)
WHERE bl.flight_id is null;



