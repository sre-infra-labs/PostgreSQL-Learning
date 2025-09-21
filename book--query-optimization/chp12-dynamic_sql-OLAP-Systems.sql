/* Dynamic SQL for OLAP (Large Input)
**
** In cases of large input, or inaccurate stats, we might create function which returns part of the code as text.
**
** Let’s imagine that for statistical analysis, we need to sort passengers by age.
**
*/

--Listing 12-8. A function that assigns the age category
CREATE OR REPLACE FUNCTION age_category (p_age int)
RETURNS TEXT
AS
$body$
BEGIN
    RETURN (case
            WHEN p_age <= 2 then 'Infant'
            WHEN p_age <=12 then 'Child'
            WHEN p_age < 65 then 'Adult'
            ELSE 'Senior' END);
END; 
$body$
language plpgsql;


-- calculate age category for all passengers.
    -- Method 01 using function
    -- Takes long time
SELECT passenger_id, age_category(age) 
FROM passenger
LIMIT 50000;

-- calculate age category for all passengers.
    -- Method 02 Inline case statement
    -- Takes much short time
SELECT passenger_id, 
        CASE
            WHEN age <= 2 then 'Infant'
            WHEN age <=12 then 'Child'
            WHEN age < 65 then 'Adult'
            ELSE 'Senior'
       END 
FROM passenger
LIMIT 50000;


-- Listing 12-9. A function that builds a part of dynamic SQL
CREATE OR REPLACE FUNCTION age_category_dyn (p_age text)
RETURNS text language plpgsql AS
$body$
BEGIN
    RETURN ($$CASE
            WHEN $$||p_age ||$$ <= 2 THEN 'Infant'
            WHEN $$||p_age ||$$<= 12 THEN 'Child'
            WHEN $$||p_age ||$$< 65 THEN 'Adult'
            ELSE 'Senior'
END$$);
END; $body$;

-- this returns age category
SELECT age_category(25);
-- this returns code block for age category
SELECT age_category_dyn('35')

-- Listing 12-10. Using a new age_category_dyn function to build dynamic SQL query
CREATE TYPE passenger_age_cat_record AS (
    passenger_id int,
    age_category text
);

CREATE OR REPLACE FUNCTION passenger_age_category_select (p_limit int)
RETURNS setof passenger_age_cat_record
AS
$body$
BEGIN
    RETURN QUERY
    EXECUTE $$SELECT passenger_id,
                    $$||age_category_dyn('age')||$$ AS age_category
    FROM passenger LIMIT $$ ||p_limit::text;
END;
$body$ 
LANGUAGE plpgsql;

EXPLAIN
(analyze, buffers, verbose, COSTs)
SELECT * FROM passenger_age_category_select (50000);



