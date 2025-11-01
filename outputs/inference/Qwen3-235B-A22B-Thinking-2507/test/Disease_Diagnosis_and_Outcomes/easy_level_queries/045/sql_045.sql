WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
filtered_admissions AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60.0) AS los_days
  FROM patient_admissions
  WHERE age_at_adm BETWEEN 77 AND 87
    AND dischtime IS NOT NULL
),
diag_conditions AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'I50%') OR (icd_version = 9 AND icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'J44%') OR (icd_version = 9 AND icd_code = '496') THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM filtered_admissions fa
INNER JOIN diag_conditions dc
  ON fa.hadm_id = dc.hadm_id
WHERE dc.has_hf = 1 AND dc.has_copd = 1;