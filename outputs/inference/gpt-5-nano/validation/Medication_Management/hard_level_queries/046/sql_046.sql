with trauma_codes as (
  select
    di.hadm_id,
    CAST(REGEXP_EXTRACT(di.icd_code, '([0-9]{3})') AS INT64) AS icd3
  from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  where di.icd_version = 9
),
trauma_hadm AS (
  select hadm_id
  from trauma_codes
  where icd3 BETWEEN 800 AND 959
  group by hadm_id
  having COUNT(DISTINCT icd3) >= 2
),
age_gender_cohort AS (
  select p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.deathtime
  from `physionet-data.mimiciv_3_1_hosp.patients` AS p
  join `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    on p.subject_id = a.subject_id
  where p.gender = 'F'
    and p.anchor_age BETWEEN 45 AND 55
    and a.hadm_id IN (SELECT hadm_id FROM trauma_hadm)
),
cohort as (
  select ag.subject_id, ag.hadm_id, ag.admittime, ag.dischtime, ag.deathtime, ag.hospital_expire_flag
  from age_gender_cohort AS ag
),
med_counts as (
  select c.hadm_id,
         COUNT(DISTINCT IFNULL(presc.drug, '')) AS med_count
  from cohort AS c
  left join `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    on presc.subject_id = c.subject_id
   and presc.hadm_id = c.hadm_id
   and presc.starttime >= c.admittime
   and presc.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  group by c.hadm_id
),
base as (
  select c.hadm_id,
         c.subject_id,
         c.admittime,
         c.disptime,
         c.dischtime,
         c.deathtime,
         c.hospital_expire_flag,
         coalesce(m.med_count, 0) AS med_count,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 86400.0 AS los_days
  from cohort AS c
  left join med_counts AS m
    on m.hadm_id = c.hadm_id
),
with_readmit as (
  select b.*,
         case when exists (
           select 1
           from `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
           where a2.subject_id = b.subject_id
             and a2.admittime > b.dischtime
             and a2.admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
         ) then 1 else 0 end AS readmit_flag,
         case when b.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality_flag
  from base AS b
)
select
  tertile,
  COUNT(*) AS admissions,
  AVG(med_count) AS med_count_mean,
  MIN(med_count) AS med_count_min,
  MAX(med_count) AS med_count_max,
  AVG(los_days) AS los_mean,
  AVG(mortality_flag) * 100 AS mortality_rate_pct,
  AVG(readmit_flag) * 100 AS readmit_rate_30day_pct
from (
  select w.*,
         NTILE(3) OVER (ORDER BY med_count) AS tertile
  from with_readmit AS w
) AS t
GROUP BY tertile
ORDER BY tertile;