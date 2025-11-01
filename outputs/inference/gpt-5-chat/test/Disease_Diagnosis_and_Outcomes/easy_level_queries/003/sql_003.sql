WITH target_patients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    -- Primary diagnosis for the admission
    AND diag.seq_num = 1
    -- ICD codes for ischemic heart disease / ACS
    AND (
      diag.icd_code LIKE '410%' -- Acute MI
      OR diag.icd_code LIKE '411%' -- Other ACS forms
      OR diag.icd_code LIKE '412%' -- Old MI
      OR diag.icd_code LIKE '413%' -- Angina pectoris
      OR diag.icd_code LIKE '414%' -- Other ischemic heart disease
    )
    -- Ensure LOS calculable
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile_days
FROM target_patients;