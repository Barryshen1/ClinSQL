WITH stroke_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.gender,
    EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    diag.seq_num = 1  -- primary diagnosis
    AND diag.icd_code LIKE 'I63%'  -- ischemic stroke
    AND diag.icd_version = 10
    AND pat.gender = 'F'
    AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM stroke_admissions
WHERE age_at_admission BETWEEN 59 AND 69;