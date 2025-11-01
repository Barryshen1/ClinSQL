WITH qualifying_admissions AS (
  SELECT DISTINCT
    diag.subject_id,
    diag.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code 
    AND diag.icd_version = d_icd.icd_version
  WHERE 
    LOWER(d_icd.long_title) LIKE '%sepsis%'
)
SELECT 
  PERCENTILE_CONT(0.5) IGNORE NULLS OVER (ORDER BY icu.los) AS median_icu_los_days
FROM 
  `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN 
  qualifying_admissions qa
  ON icu.subject_id = qa.subject_id 
  AND icu.hadm_id = qa.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON icu.subject_id = pat.subject_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON icu.hadm_id = adm.hadm_id
WHERE 
  pat.gender = 'F'
  AND (
    EXTRACT(YEAR FROM adm.admittime) 
    - pat.anchor_year 
    + pat.anchor_age
  ) BETWEEN 58 AND 68
LIMIT 1;