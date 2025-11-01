WITH ugib_codes AS (
  -- ICD-10: Gastric/duodenal/peptic ulcer with hemorrhage/perforation
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_version = CAST('10' AS STRING) 
    AND icd_code LIKE 'K25.%' 
    AND (icd_code LIKE 'K25.0%' OR icd_code LIKE 'K25.2%' OR icd_code LIKE 'K25.4%' OR icd_code LIKE 'K25.6%')
  UNION ALL
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_code LIKE 'K26.%' 
    AND (icd_code LIKE 'K26.0%' OR icd_code LIKE 'K26.2%' OR icd_code LIKE 'K26.4%' OR icd_code LIKE 'K26.6%')
  UNION ALL
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_code LIKE 'K27.%' 
    AND (icd_code LIKE 'K27.0%' OR icd_code LIKE 'K27.2%' OR icd_code LIKE 'K27.4%' OR icd_code LIKE 'K27.6%')
  UNION ALL
  -- ICD-9: Similar patterns (e.g., 531.01, 531.21, 531.41, 531.51, 531.61 for gastric; analogous for 532/533/534)
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = CAST('9' AS STRING) 
    AND (
      icd_code LIKE '531.0%' OR icd_code LIKE '531.2%' OR icd_code LIKE '531.4%' OR icd_code LIKE '531.5%' OR icd_code LIKE '531.6%'
      OR icd_code LIKE '532.0%' OR icd_code LIKE '532.2%' OR icd_code LIKE '532.4%' OR icd_code LIKE '532.5%' OR icd_code LIKE '532.6%'
      OR icd_code LIKE '533.0%' OR icd_code LIKE '533.2%' OR icd_code LIKE '533.4%' OR icd_code LIKE '533.5%' OR icd_code LIKE '533.6%'
      OR icd_code LIKE '534.0%' OR icd_code LIKE '534.2%' OR icd_code LIKE '534.4%' OR icd_code LIKE '534.5%' OR icd_code LIKE '534.6%'
    )
),
copd_exac_codes AS (
  -- ICD-10: COPD exacerbation
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = CAST('10' AS STRING) 
    AND (icd_code = 'J44.0' OR icd_code = 'J44.1')
  UNION ALL
  -- ICD-9: COPD exacerbation (obstructive, with acute exacerbation)
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = CAST('9' AS STRING) 
    AND (
      icd_code = '491.21' OR icd_code = '491.22' OR icd_code = '493.21' OR icd_code = '493.22'
    )
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    SAFE.DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_code IN (SELECT icd_code FROM ugib_codes)
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_code IN (SELECT icd_code FROM copd_exac_codes)
    )
)
SELECT 
  PERCENTILE_CONT(0.5, los_days) OVER() AS median_los_days
FROM cohort
WHERE los_days IS NOT NULL;