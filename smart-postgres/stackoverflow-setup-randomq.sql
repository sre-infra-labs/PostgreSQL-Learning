--show search_path;

--drop function usp_q7521
create or replace function usp_q7521 (p_userid INT)
returns table (
    accepted_answers bigint,
    scored_answers bigint,
    unscored_answers bigint,
    percentage_unscored NUMERIC
)
as
$BODY$
begin
    return query
    select
        count(a.id) as accepted_answers,
        sum(case when a.score = 0 then 0 else 1 end) as scored_answers,  
        sum(case when a.score = 0 then 1 else 0 end) as unscored_answers,
        sum(case when a.score = 0 then 1 else 0 end)*100.0 / count(a.id) as percentage_unscored
    from
        posts q
    inner join
        posts a
    on a.id = q.acceptedanswerid
    where
        a.communityowneddate is null
    and a.owneruserid = p_userid
    and q.owneruserid != p_userid
    and a.posttypeid = 2;
end;
$BODY$
LANGUAGE plpgsql;

select *
from usp_q7521(26837)