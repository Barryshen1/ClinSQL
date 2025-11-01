with cohort as (
  select
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.los as hosp_los,
    case
      when i.stay_id is not null then 'ICU'
      else 'Non-ICU'
    end as icu_status
  from `physionet-data.mimiciv_3_1_hosp.admissions` a
  left join `physionet-data.mimiciv_3_1_icu.icustays` i
    on a.hadm_id = i.hadm_id
),

-- Charlson Comorbidity Index (simplified version)
charlson_codes as (
  select
    subject_id,
    hadm_id,
    sum(case
      when icd_version = 10 and icd_code in ('I10', 'I110', 'I119', 'I120', 'I129', 'I130', 'I131', 'I132', 'I139') then 1 -- Hypertension
      when icd_version = 9 and icd_code between '4010' and '40599' then 1
      when icd_version = 10 and icd_code like 'C%' then 1 -- Any malignancy
      when icd_version = 9 and icd_code between '1400' and '23999' then 1
      when icd_version = 10 and icd_code in ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') then 1 -- Diabetes with complications
      when icd_version = 9 and icd_code in ('25040', '25041', '25042', '25043', '25050', '25051', '25052', '25053', '25060', '25061', '25062', '25063', '25070', '25071', '25072', '25073', '25080', '25081', '25082', '25083', '25090', '25091', '25092', '25093') then 1
      else 0
    end) as charlson_score
  from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  group by subject_id, hadm_id
),

-- Add Charlson to cohort
cohort_with_charlson as (
  select
    c.*,
    coalesce(cc.charlson_score, 0) as charlson_score
  from cohort c
  left join charlson_codes cc
    on c.hadm_id = cc.hadm_id
),

-- Stratify by LOS and Charlson
stratified_cohort as (
  select
    *,
    case
      when hosp_los <= 3 then '<=3'
      when hosp_los between 4 and 6 then '4-6'
      when hosp_los between 7 and 10 then '7-10'
      else '>10'
    end as los_group,
    case
      when charlson_score <= 3 then '<=3'
      when charlson_score between 4 and 5 then '4-5'
      else '>5'
    end as charlson_group
  from cohort_with_charlson
),

-- Mechanical ventilation
mv as (
  select distinct hadm_id
  from `physionet-data.mimiciv_3_1_icu.chartevents` ce
  join `physionet-data.mimiciv_3_1_icu.d_items` di
    on ce.itemid = di.itemid
  where di.label in (
    'Ventilator Mode', 'Ventilator Type', 'PEEP', 'FiO2', 'Tidal Volume', 'Minute Volume',
    'Ventilator Rate', 'Ventilator', 'Mechanical Ventilation', 'Ventilator Status'
  )
),

-- Vasopressors
vaso as (
  select distinct hadm_id
  from `physionet-data.mimiciv_3_1_hosp.prescriptions`
  where lower(drug) in (
    'norepinephrine', 'epinephrine', 'dopamine', 'dobutamine', 'phenylephrine', 'vasopressin'
  )
),

-- RRT (Renal Replacement Therapy)
rrt as (
  select distinct hadm_id
  from `physionet-data.mimiciv_3_1_icu.chartevents` ce
  join `physionet-data.mimiciv_3_1_icu.d_items` di
    on ce.itemid = di.itemid
  where di.label in (
    'Dialysis', 'CRRT', 'Hemodialysis', 'Peritoneal Dialysis', 'CVVH', 'CVVHD', 'SLED'
  )
),

-- Final cohort with flags
final_cohort as (
  select
    s.*,
    case when mv.hadm_id is not null then 1 else 0 end as mech_vent,
    case when vaso.hadm_id is not null then 1 else 0 end as vasopressor,
    case when rrt.hadm_id is not null then 1 else 0 end as rrt
  from stratified_cohort s
  left join mv on s.hadm_id = mv.hadm_id
  left join vaso on s.hadm_id = vaso.hadm_id
  left join rrt on s.hadm_id = rrt.hadm_id
)

-- Aggregate results
select
  icu_status,
  los_group,
  charlson_group,
  count(*) as n,
  avg(hospital_expire_flag) as mortality_rate,
  avg(mech_vent) as pct_mech_vent,
  avg(vasopressor) as pct_vasopressor,
  avg(rrt) as pct_rrt
from final_cohort
group by icu_status, los_group, charlson_group
order by icu_status, los_group, charlson_group;