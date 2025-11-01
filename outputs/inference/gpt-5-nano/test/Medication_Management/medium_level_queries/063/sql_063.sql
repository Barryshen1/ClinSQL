with eligible as (
  select
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  from `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  join `physionet-data.mimiciv_3_1_hosp.patients` AS p
    on a.subject_id = p.subject_id
  where
    LOWER(p.gender) in ('m', 'male')
    and p.anchor_age between 45 and 55
    -- Diabetes present for this admission
    and exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      join `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        on di.icd_code = dd.icd_code and di.icd_version = dd.icd_version
      where di.hadm_id = a.hadm_id
        and LOWER(dd.long_title) like '%diabetes%'
    )
    -- Heart failure present for this admission
    and exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      join `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        on di2.icd_code = dd2.icd_code and di2.icd_version = dd2.icd_version
      where di2.hadm_id = a.hadm_id
        and LOWER(dd2.long_title) like '%heart failure%'
    )
)

, flags as (
  select
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      where p.subject_id = e.subject_id
        and p.hadm_id = e.hadm_id
        and p.starttime between e.admittime and TIMESTAMP_ADD(e.admittime, interval 12 hour)
        and REGEXP_CONTAINS(LOWER(p.drug), 'insulin')
    ) as insulin_first12,
    exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      where p.subject_id = e.subject_id
        and p.hadm_id = e.hadm_id
        and p.starttime between e.admittime and TIMESTAMP_ADD(e.admittime, interval 12 hour)
        and REGEXP_CONTAINS(LOWER(p.drug), '(metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|acarbose|miglitol|sitagliptin|linagliptin|alogliptin|dapagliflozin|empagliflozin|canagliflozin|ertugliflozin)')
        and NOT REGEXP_CONTAINS(LOWER(p.drug), 'insulin')
    ) as oral_first12,
    exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      where p.subject_id = e.subject_id
        and p.hadm_id = e.hadm_id
        and p.starttime between TIMESTAMP_SUB(e.dischtime, interval 72 hour) and e.dischtime
        and REGEXP_CONTAINS(LOWER(p.drug), 'insulin')
    ) as insulin_final72,
    exists (
      select 1
      from `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      where p.subject_id = e.subject_id
        and p.hadm_id = e.hadm_id
        and p.starttime between TIMESTAMP_SUB(e.dischtime, interval 72 hour) and e.dischtime
        and REGEXP_CONTAINS(LOWER(p.drug), '(metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|acarbose|miglitol|sitagliptin|linagliptin|alogliptin|dapagliflozin|empagliflozin|canagliflozin|ertugliflozin)')
        and NOT REGEXP_CONTAINS(LOWER(p.drug), 'insulin')
    ) as oral_final72
  from eligible e
)

select
  round(100 * avg(IF(insulin_first12, 1, 0)), 2) as insulin_first12_rate,
  round(100 * avg(IF(insulin_final72, 1, 0)), 2) as insulin_final72_rate,
  round((100 * avg(IF(insulin_first12, 1, 0))) - (100 * avg(IF(insulin_final72, 1, 0))), 2) as insulin_pp_diff,
  round(100 * avg(IF(oral_first12, 1, 0)), 2) as oral_first12_rate,
  round(100 * avg(IF(oral_final72, 1, 0)), 2) as oral_final72_rate,
  round((100 * avg(IF(oral_first12, 1, 0))) - (100 * avg(IF(oral_final72, 1, 0))), 2) as oral_pp_diff
from flags;