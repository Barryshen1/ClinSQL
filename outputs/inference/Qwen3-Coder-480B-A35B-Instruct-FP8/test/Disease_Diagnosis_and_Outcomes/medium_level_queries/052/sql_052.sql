with stroke_patients as (
  select distinct
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_location,
    a.admission_type,
    datetime_diff(a.dischtime, a.admittime, day) as los_days,
    case when i.stay_id is not null then 1 else 0 end as icu_flag
  from physionet-data.mimiciv_3_1_hosp.admissions a
  inner join physionet-data.mimiciv_3_1_hosp.patients p
    on a.subject_id = p.subject_id
  inner join physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    on a.hadm_id = d.hadm_id
  inner join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
  left join physionet-data.mimiciv_3_1_icu.icustays i
    on a.hadm_id = i.hadm_id
  where
    p.gender = 'M'
    and p.anchor_age between 52 and 62
    and (
      (dd.icd_version = 9 and dd.icd_code like '43%') or
      (dd.icd_version = 10 and dd.icd_code like 'I6%')
    )
),

comorbidities as (
  select
    sp.hadm_id,
    sp.subject_id,
    sp.los_days,
    sp.icu_flag,
    sp.hospital_expire_flag,
    max(case when dd.long_title like '%Chronic Kidney Disease%' then 1 else 0 end) as ckd,
    max(case when dd.long_title like '%Diabetes%' then 1 else 0 end) as diabetes
  from stroke_patients sp
  inner join physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    on sp.hadm_id = d.hadm_id
  inner join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
  group by sp.hadm_id, sp.subject_id, sp.los_days, sp.icu_flag, sp.hospital_expire_flag
),

comorbidity_scores as (
  select
    *,
    ckd + diabetes as comorbidity_count
  from comorbidities
),

tertiles as (
  select
    *,
    ntile(3) over (order by comorbidity_count) as comorbidity_tertile
  from comorbidity_scores
)

select
  icu_flag,
  case when los_days <= 5 then '0-5' else '6+' end as los_group,
  comorbidity_tertile,
  count(*) as patient_count,
  avg(hospital_expire_flag) * 100 as in_hospital_mortality_pct,
  avg(ckd) * 100 as ckd_prevalence_pct,
  avg(diabetes) * 100 as diabetes_prevalence_pct
from tertiles
group by icu_flag, los_group, comorbidity_tertile
order by icu_flag, los_group, comorbidity_tertile;