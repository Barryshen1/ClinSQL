with patients_filtered as (
  select subject_id
  from `physionet-data.mimiciv_3_1_hosp`.patients
  where gender = 'F'
    and anchor_age between 74 and 84
),
pe_admissions as (
  select distinct adm.hadm_id
  from `physionet-data.mimiciv_3_1_hosp`.admissions adm
  join `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    on adm.hadm_id = diag.hadm_id
  join `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    on diag.icd_code = d_diag.icd_code and diag.icd_version = d_diag.icd_version
  join patients_filtered pf
    on adm.subject_id = pf.subject_id
  where lower(d_diag.long_title) like '%pulmonary embolism%'
),
medications_first_24h as (
  select 
    ph.hadm_id,
    ph.pharmacy_id,
    ph.starttime,
    ph.drug
  from `physionet-data.mimiciv_3_1_hosp`.prescriptions ph
  join pe_admissions pe
    on ph.hadm_id = pe.hadm_id
  where datetime_diff(ph.starttime, (select min(admittime) from `physionet-data.mimiciv_3_1_hosp`.admissions a where a.hadm_id = ph.hadm_id), second) <= 86400
),
med_count_per_hadm as (
  select 
    hadm_id,
    count(*) as med_count
  from medications_first_24h
  group by hadm_id
),
los_mort as (
  select 
    adm.hadm_id,
    mc.med_count,
    case when icu.stay_id is not null then 1 else 0 end as had_icu,
    adm.los,
    adm.hospital_expire_flag
  from `physionet-data.mimiciv_3_1_hosp`.admissions adm
  join med_count_per_hadm mc on adm.hadm_id = mc.hadm_id
  left join `physionet-data.mimiciv_3_1_icu`.icustays icu on adm.hadm_id = icu.hadm_id
),
overall_stats as (
  select
    avg(med_count) as mean_complexity,
    min(med_count) as min_complexity,
    max(med_count) as max_complexity,
    std(med_count) as sd_complexity,
    percentile_cont(med_count, 0.75) over() as p75_complexity
  from los_mort
  limit 1
)
select
  os.mean_complexity,
  os.min_complexity,
  os.max_complexity,
  os.sd_complexity,
  os.p75_complexity,
  lm.had_icu,
  avg(lm.med_count) as mean_med_count,
  count(*) as patient_count,
  avg(lm.hospital_expire_flag) as mortality_rate,
  avg(case when lm.los > os.p75_complexity then 1.0 else 0.0 end) as prop_long_los
from los_mort lm
cross join overall_stats os
group by lm.had_icu, os.mean_complexity, os.min_complexity, os.max_complexity, os.sd_complexity, os.p75_complexity;