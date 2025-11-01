with cohort_subjects as (
  -- 65-year-old man inpatients with primary pneumonia, age 60-70, male
  select distinct a.subject_id
  from `physionet-data.mimiciv_3_1_hosp.admissions` as a
  join `physionet-data.mimiciv_3_1_hosp.patients` as p
    on p.subject_id = a.subject_id
  join `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` as di
    on di.subject_id = a.subject_id and di.hadm_id = a.hadm_id
  join `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` as dd
    on dd.icd_code = di.icd_code and dd.icd_version = di.icd_version
  where p.gender = 'M'
    and p.anchor_age between 60 and 70
    and di.seq_num = 1
    and LOWER(dd.long_title) LIKE '%pneumonia%'
),
cohort_hads as (
  select a.hadm_id
  from `physionet-data.mimiciv_3_1_hosp.admissions` a
  join cohort_subjects c on c.subject_id = a.subject_id
),
-- Part 2: 72-hour laboratory instability score per hadm_id
lab_range_stats as (
  select le.hadm_id,
         le.itemid,
         max(le.valuenum) as maxv,
         min(le.valuenum) as minv,
         count(*) as cnt
  from `physionet-data.mimiciv_3_1_hosp.labevents` le
  join `physionet-data.mimiciv_3_1_hosp.admissions` a
    on le.hadm_id = a.hadm_id
  where le.charttime between a.admittime and TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    and le.valuenum is not null
  group by le.hadm_id, le.itemid
),
lab_instability_by_hadm as (
  select hadm_id,
         sum(case when cnt >= 2 then (maxv - minv) else 0 end) as instability72h
  from lab_range_stats
  group by hadm_id
),
cohort_instability as (
  select h.hadm_id,
         coalesce(li.instability72h, 0) as instability72h
  from cohort_hads h
  left join lab_instability_by_hadm li on li.hadm_id = h.hadm_id
),
icu_counts_subject as (
  select s.subject_id, count(i.stay_id) as icu_stays
  from cohort_subjects s
  left join `physionet-data.mimiciv_3_1_icu.icustays` i
    on i.subject_id = s.subject_id
  group by s.subject_id
),
icu_counts_all_subjects as (
  select s.subject_id, count(i.stay_id) as icu_stays
  from (select distinct subject_id from `physionet-data.mimiciv_3_1_hosp.admissions`) s
  left join `physionet-data.mimiciv_3_1_icu.icustays` i
    on i.subject_id = s.subject_id
  group by s.subject_id
),
mean_icu_cohort as (
  select avg(icu_stays) as mean_icu_cohort
  from icu_counts_subject
),
mean_icu_all as (
  select avg(icu_stays) as mean_icu_all
  from icu_counts_all_subjects
),
cohort_los as (
  select avg(timestamp_diff(a.dischtime, a.admittime, second) / 3600.0) as mean_los_hours
  from `physionet-data.mimiciv_3_1_hosp.admissions` a
  join cohort_hads ch on a.hadm_id = ch.hadm_id
),
cohort_mortality as (
  select avg(case when a.hospital_expire_flag = 1 then 1.0 else 0.0 end) as mortality_rate
  from `physionet-data.mimiciv_3_1_hosp.admissions` a
  join cohort_hads ch on a.hadm_id = ch.hadm_id
),
p75_instability as (
  select (approx_quantiles(instability72h, 4))[offset(3)] as p75_instability72h
  from cohort_instability
)
select
  p75_instability.p75_instability72h as p75_instability72h_72h_lab,
  mean_icu_cohort.mean_icu_cohort,
  mean_icu_all.mean_icu_all,
  cohort_los.mean_los_hours,
  cohort_mortality.mortality_rate
from p75_instability
cross join mean_icu_cohort
cross join mean_icu_all
cross join cohort_los
cross join cohort_mortality;