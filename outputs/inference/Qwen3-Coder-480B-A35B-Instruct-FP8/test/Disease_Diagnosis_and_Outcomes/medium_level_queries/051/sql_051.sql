with postop_admissions as (
  select distinct
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    datetime_diff(a.dischtime, a.admittime, day) as los_days,
    case
      when icu.hadm_id is not null then 'ICU'
      else 'Non-ICU'
    end as icu_status
  from physionet-data.mimiciv_3_1_hosp.admissions a
  join physionet-data.mimiciv_3_1_hosp.patients p
    on a.subject_id = p.subject_id
  left join physionet-data.mimiciv_3_1_icu.icustays icu
    on a.hadm_id = icu.hadm_id
  where p.gender = 'M'
    and p.anchor_age between 51 and 61
    and exists (
      select 1
      from physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
      where d.hadm_id = a.hadm_id
        and lower(dd.long_title) like '%postoperative complication%'
    )
),

-- Charlson Comorbidity Index (Quan et al.)
cci_calc as (
  select
    d.hadm_id,
    sum(case
      when dd.long_title like '%Myocardial infarction%' then 1
      when dd.long_title like '%Congestive heart disease%' then 1
      when dd.long_title like '%Peripheral vascular disease%' then 1
      when dd.long_title like '%Cerebrovascular disease%' then 1
      when dd.long_title like '%Dementia%' then 1
      when dd.long_title like '%Chronic pulmonary disease%' then 1
      when dd.long_title like '%Rheumatologic disease%' then 1
      when dd.long_title like '%Peptic ulcer disease%' then 1
      when dd.long_title like '%Mild liver disease%' then 1
      when dd.long_title like '%Diabetes without chronic complication%' then 1
      when dd.long_title like '%Diabetes with chronic complication%' then 2
      when dd.long_title like '%Hemiplegia or paraplegia%' then 2
      when dd.long_title like '%Renal disease%' then 2
      when dd.long_title like '%Any malignancy%' then 2
      when dd.long_title like '%Moderate or severe liver disease%' then 3
      when dd.long_title like '%Metastatic solid tumor%' then 6
      when dd.long_title like '%AIDS/HIV%' then 6
      else 0
    end) as charlson_score
  from physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
  where d.hadm_id in (select hadm_id from postop_admissions)
  group by d.hadm_id
),

admission_with_strata as (
  select
    pa.*,
    cci.charlson_score,
    case
      when pa.los_days between 1 and 2 then '1-2'
      when pa.los_days between 3 and 5 then '3-5'
      when pa.los_days between 6 and 9 then '6-9'
      when pa.los_days >= 10 then '>=10'
      else '<1'
    end as los_group,
    case
      when cci.charlson_score between 0 and 1 then '0-1'
      when cci.charlson_score = 2 then '2'
      when cci.charlson_score >= 3 then '>=3'
      else '0'
    end as cci_group,
    case
      when exists (
        select 1
        from physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
        join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
          on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
        where d.hadm_id = pa.hadm_id
          and (dd.long_title like '%Chronic kidney disease%' or dd.long_title like '%Renal disease%')
      ) then 1 else 0
    end as has_ckd,
    case
      when exists (
        select 1
        from physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
        join physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
          on d.icd_code = dd.icd_code and d.icd_version = dd.icd_version
        where d.hadm_id = pa.hadm_id
          and dd.long_title like '%Diabetes%'
      ) then 1 else 0
    end as has_diabetes
  from postop_admissions pa
  left join cci_calc cci
    on pa.hadm_id = cci.hadm_id
)

select
  icu_status,
  los_group,
  cci_group,
  count(*) as n_patients,
  round(avg(hospital_expire_flag) * 100, 2) as mortality_percent,
  approx_quantiles(los_days, 2)[ordinal(2)] as median_los,
  round(avg(has_ckd) * 100, 2) as ckd_prevalence_percent,
  round(avg(has_diabetes) * 100, 2) as diabetes_prevalence_percent
from admission_with_strata
group by icu_status, los_group, cci_group
order by icu_status, los_group, cci_group;