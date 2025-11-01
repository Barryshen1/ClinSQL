WITH sepsis_hosp AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admission_type,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    FLOOR(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400) AS los_days,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS septic_shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY
    a.hadm_id,
    a.subject_id,
    a.admission_type,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
),

-- Step 2: comorbidity count per admission (excluding sepsis codes)
comorb_counts AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  JOIN sepsis_hosp AS s
    ON s.hadm_id = di.hadm_id
  WHERE NOT LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY di.hadm_id
)

-- Step 3: assemble final results by sepsis severity, LOS bucket, and admission type
SELECT
  CASE WHEN s.septic_shock_flag = 1 THEN 'Septic shock' ELSE 'No septic shock' END AS sepsis_severity,
  CASE
    WHEN s.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN s.los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN s.los_days >= 8 THEN '8+'
  END AS los_bucket,
  s.admission_type,
  COUNT(*) AS n_admissions,
  100.0 * SUM(s.hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_percent,
  AVG(IFNULL(cc.comorbidity_count, 0)) AS mean_comorbidity_count
FROM sepsis_hosp AS s
LEFT JOIN comorb_counts AS cc ON cc.hadm_id = s.hadm_id
WHERE s.los_days BETWEEN 1 AND 3
   OR s.los_days BETWEEN 4 AND 7
   OR s.los_days >= 8
GROUP BY sepsis_severity, los_bucket, s.admission_type
ORDER BY sepsis_severity, los_bucket, s.admission_type;