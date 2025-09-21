-- Listing 11-25. Example of a stored procedure with transactions
    -- Insert records in batches of 50k
CREATE PROCEDURE load_with_transform()
AS 
$load$
DECLARE
    v_cnt int;
    v_record record;
BEGIN
    FOR v_record IN (SELECT * FROM data_source) LOOP
        PERFORM transform (v_rec.id);
        CALL insert_data (v_rec.*);
        v_cnt:=v_cnt+1;
        IF v_cnt>=50000 THEN
            COMMIT;
            v_cnt:=0;
        END IF;
    END LOOP;
COMMIT;
END;
$load$ 
LANGUAGE plpgsql;




-- Listing 11-26. Nested blocks in the procedure body
CREATE PROCEDURE multiple_blocks AS
$mult$
BEGIN
---case #1
  BEGIN
  <...>
  EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'CASE#1";
  END; --case #1
BEGIN
   ---case #2
  BEGIN
  <...>
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CASE#2";
  END; --case #2
BEGIN
---case #3
  BEGIN
  <...>
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CASE#3";
  END; --case #3
END; ---proc
$mult$ LANGUAGE plpbsql;