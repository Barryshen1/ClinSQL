with eligible_stays as (
  -- ICU stays for female patients aged 80-90 (anchor_age)
  select s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime
  from `physionet-data.mimiciv_3_1_icu.icustays` s
  join `physionet-data.mimiciv_3_1_hosp.patients` p
    on s.subject_id = p.subject_id
  where p.gender = 'F'
    and p.anchor_age between 80 and 90
),

hr_items as (
  -- identify itemids that correspond to heart rate
  select itemid
  from `physionet-data.mimiciv_3_1_icu.d_items`
  where lower(label) like '%heart rate%'
     or lower(abbreviation) = 'hr'
     or lower(label) = 'hr'
),

hr_per_stay as (
  -- compute per-stay average heart rate (restrict to plausible numeric values and to icu stay window)
  select
    es.subject_id,
    es.hadm_id,
    es.stay_id,
    avg(ch.valuenum) as mean_hr,
    count(1) as n_hr_measurements
  from eligible_stays es
  join `physionet-data.mimiciv_3_1_icu.chartevents` ch
    on ch.subject_id = es.subject_id
   and ch.hadm_id = es.hadm_id
   and ch.stay_id = es.stay_id
  join hr_items hi
    on ch.itemid = hi.itemid
  where ch.valuenum is not null
    and ch.valuenum between 30 and 250  -- filter out extreme artifacts
    and ch.charttime between es.intime and es.outtime
  group by es.subject_id, es.hadm_id, es.stay_id
)

select
  110.0 as target_mean_hr,
  count(*) as n_stays_in_cohort,
  sum(case when mean_hr <= 110 then 1 else 0 end) as n_stays_at_or_below_110,
  round(100.0 * sum(case when mean_hr <= 110 then 1 else 0 end) / count(*), 2) as percentile_of_110
from hr_per_stay;