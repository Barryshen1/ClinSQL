WITH sepsis_admissions AS (
  SELECT 
    adm.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_adm,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 40 AND 50
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('99592', '78552'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R652%'))
    )
)
SELECT
  q1,
  q3,
  q3 - q1 AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS q1,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS q3
  FROM sepsis_admissions
);