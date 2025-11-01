WITH sepsis_cohort AS (
  -- Base cohort: males aged 64-74 with primary sepsis diagnosis (ICD-10), exclude septic shock
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CAST(a.hospital_expire_flag AS INT64) AS hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- CKD flag: any CKD diagnosis in admission
    CASE WHEN SUM(CASE WHEN di.icd_version = '10' AND REGEXP_CONTAINS(di.icd_code, r'^N18|N19') THEN 1 END) OVER (PARTITION BY a.hadm_id) > 0 
         THEN 1 ELSE 0 END AS has_ckd,
    -- Diabetes flag: any diabetes diagnosis in admission
    CASE WHEN SUM(CASE WHEN di.icd_version = '10' AND REGEXP_CONTAINS(di.icd_code, r'^E10|E11|E13') THEN 1 END) OVER (PARTITION BY a.hadm_id) > 0 
         THEN 1 ELSE 0 END AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.hospital_expire_flag IS NOT NULL  -- Ensure outcome available
    AND CAST(d.seq_num AS INT64) = 1  -- Primary diagnosis
    AND d.icd_version = '10'  -- ICD-10 for modern codes
    AND REGEXP_CONTAINS(d.icd_code, r'^A40|A41|R65\.2[01]')  -- Sepsis codes (severe sepsis without shock)
    AND NOT REGEXP_CONTAINS(d.icd_code, r'^R65\.21')  -- Exclude septic shock
    AND EXTRACT(YEAR FROM a.admittime) >= 2016  -- ICD-10 era
    AND a.admittime < a.dischtime  -- Valid admission
  QUALIFY los_days > 0  -- Exclude same-day, ensure valid LOS
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM sepsis_cohort
)
SELECT 
  los_quartile AS quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_percent,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_percent
FROM quartiles
GROUP BY los_quartile
ORDER BY los_quartile;