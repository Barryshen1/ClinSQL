WITH cellulitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (CAST(icd_version AS STRING) = 'ICD-9' AND (icd_code LIKE '681%' OR icd_code LIKE '682%'))
     OR (CAST(icd_version AS STRING) = 'ICD-10' AND icd_code LIKE 'L03%')
),
index_cohort AS (
  SELECT 
    p.subject_id,
    adm.hadm_id AS index_hadm_id,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS index_los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
      WHERE readm.subject_id = adm.subject_id
        AND readm.hadm_id != adm.hadm_id
        AND readm.admittime >= adm.dischtime
        AND readm.admittime <= DATE_ADD(adm.dischtime, INTERVAL 30 DAY)
        AND readm.hospital_expire_flag = 0
      LIMIT 1
    ) THEN 1 ELSE 0 END AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN cellulitis_codes cc
    ON diag.icd_code = cc.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'MC - Medicare'
    AND adm.hospital_expire_flag = 0
)
SELECT 
  -- 30-day readmission rate (patient-level)
  SAFE_DIVIDE(SUM(readmitted), COUNT(DISTINCT subject_id)) * 100 AS readmission_rate_pct,
  
  -- Median index LOS by readmitted status
  PERCENTILE_CONT(index_los_days, 0.5) OVER (PARTITION BY readmitted) AS median_los_readmitted,
  PERCENTILE_CONT(index_los_days, 0.5) OVER (PARTITION BY readmitted = 0) AS median_los_non_readmitted,
  
  -- % index stays >7 days (overall and by status)
  SAFE_DIVIDE(SUM(CASE WHEN index_los_days > 7 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS pct_long_stay_overall,
  SAFE_DIVIDE(SUM(CASE WHEN readmitted = 1 AND index_los_days > 7 THEN 1 ELSE 0 END), SUM(readmitted)) * 100 AS pct_long_stay_readmitted,
  SAFE_DIVIDE(SUM(CASE WHEN readmitted = 0 AND index_los_days > 7 THEN 1 ELSE 0 END), SUM(CASE WHEN readmitted = 0 THEN 1 ELSE 0 END)) * 100 AS pct_long_stay_non_readmitted
  
FROM index_cohort;