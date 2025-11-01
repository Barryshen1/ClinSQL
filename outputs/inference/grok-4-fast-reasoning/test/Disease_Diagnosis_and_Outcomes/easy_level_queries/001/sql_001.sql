WITH patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
copd_adms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN patients p ON diag.subject_id = p.subject_id
  WHERE (
    (icd_version = 10 AND icd_code IN ('J440', 'J441')) OR
    (icd_version = 9 AND icd_code IN ('49121', '49122'))
  )
),
ugib_adms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN patients p ON diag.subject_id = p.subject_id
  WHERE (
    (icd_version = 10 AND icd_code IN ('K250', 'K254', 'K260', 'K264', 'K270', 'K274')) OR
    (icd_version = 9 AND icd_code IN ('53140', '53100', '53240', '53200', '53340', '53300'))
  )
),
qualifying_adms AS (
  SELECT hadm_id
  FROM copd_adms
  
  INTERSECT DISTINCT
  
  SELECT hadm_id
  FROM ugib_adms
)
SELECT
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN qualifying_adms qa ON adm.hadm_id = qa.hadm_id
WHERE dischtime IS NOT NULL
  AND admittime < dischtime;