-- Pass rate of the code checks, by touch and country
select touch, country,
       count(*)                                     as emails,
       count(*) filter (where status <> 'failed')   as passed,
       round(100.0 * count(*) filter (where status <> 'failed') / count(*), 0) as pass_pct
from emails
group by touch, country
order by touch, country;

-- Which checks fail most often
select key as check_name, count(*) as failures
from emails, jsonb_each(checks)
where value = 'false'::jsonb
group by key
order by failures desc;

-- Where every lead is in the sequence
select status, current_touch, count(*) as leads
from leads
group by status, current_touch
order by status, current_touch;
