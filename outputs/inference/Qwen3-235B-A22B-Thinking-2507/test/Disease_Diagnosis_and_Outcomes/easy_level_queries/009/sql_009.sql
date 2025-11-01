WITH ihd_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code >= 'I20' AND icd_code < 'I26')
    OR 
    (icd_version = 9 AND icd_code >= '410' AND icd_code < '415')
),
copd_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code >= 'J44' AND icd_code < 'J45')
    OR 
    (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '496%'))
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400 AS los_days
  FROM filtered_admissions a
  INNER JOIN ihd_diagnoses ihd 
    ON a.hadm_id = ihd.hadm_id
  INNER JOIN copd_diagnoses copd 
    ON a.hadm_id = copd.hadm_id
  WHERE 
    a.age_at_adm >= 75 
    AND a.age_at_adm <= 85
);