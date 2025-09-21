-- https://data.stackexchange.com/stackoverflow/query/785/how-many-upvotes-do-i-have-for-each-tag

-- How many upvotes do I have for each tag?
-- how long before I get tag badges?

DO $$
DECLARE
    userid INTEGER := 26837;
BEGIN
    SELECT 
        tagname,
        COUNT(*) AS upvotes
    FROM public.tags
    INNER JOIN public.posttags ON posttags.tagid = tags.id
    INNER JOIN public.posts ON posts.parentid = posttags.postid
    INNER JOIN vvotes ON votes.postid = posts.id AND votes.votetypeid = 2
    WHERE posts.owneruserid = userid
    GROUP BY tagname
    ORDER BY upvotes DESC
    LIMIT 20;
END $$;

