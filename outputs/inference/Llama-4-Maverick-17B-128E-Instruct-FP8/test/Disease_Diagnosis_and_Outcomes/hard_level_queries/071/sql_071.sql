WITH ami_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
  AND dicd.long_title LIKE '%Myocardial infarction%'  
  AND a.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`)
),
ami_outcomes AS (
  SELECT 
    ac.subject_id,
    a.admittime,
    a.dischtime,
    p.dod,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN p.dod <= DATE_ADD(a.dischtime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_90d
  FROM ami_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ac.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ac.subject_id = p.subject_id
),
general_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
  AND dicd.long_title NOT LIKE '%Myocardial infarction%'  
  AND a.hadm_id NOT IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`)  
),
general_outcomes AS (
  SELECT 
    gc.subject_id,
    a.admittime,
    a.dischtime,
    p.dod,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN p.dod <= DATE_ADD(a.dischtime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_90d
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON gc.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON gc.subject_id = p.subject_id
)
SELECT 
  'AMI Cohort' AS cohort,
  APPROX_QUANTILES(ao.los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(ao.died_90d, 100)[OFFSET(50)] AS median_died_90d,
FROM ami_outcomes ao
UNION ALL
SELECT 
  'General Cohort' AS cohort,
  APPROX_QUANTILES(go.los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(go.died_90d, 100)[OFFSET(50)] AS median_died_90d,
FROM general_outcomes go;