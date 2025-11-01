WITH ami_cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
      (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')) OR
      (di.icd_version = 9 AND di.icd_code LIKE '410%')
    )
),
major_complications AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT di.icd_code) AS comp_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    (di.icd_version = 10 AND (
        dd.long_title LIKE '%Cardiogenic shock%' OR 
        dd.long_title LIKE '%Ventricular fibrillation%' OR
        dd.long_title LIKE '%Acute renal failure%'
    )) OR
    (di.icd_version = 9 AND (
        dd.long_title LIKE '%Cardiogenic shock%' OR 
        dd.long_title LIKE '%Ventricular fibrillation%' OR
        dd.long_title LIKE '%Acute renal failure%'
    ))
  GROUP BY hadm_id
),
cohort_with_comp AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.hospital_expire_flag,
    c.los_days,
    COALESCE(mc.comp_count, 0) AS comp_count,
    c.anchor_age + COALESCE(mc.comp_count, 0) AS risk_score
  FROM ami_cohort c
  LEFT JOIN major_complications mc
    ON c.hadm_id = mc.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM cohort_with_comp
),
quintile_agg AS (
  SELECT 
    quintile,
    COUNT(*) AS n_patients,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(100.0 * SUM(CASE WHEN comp_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS complication_percent
  FROM quintiles
  GROUP BY quintile
),
survivor_los AS (
  SELECT 
    quintile,
    ROUND(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY quintile), 2) AS median_los_survivors
  FROM quintiles
  WHERE hospital_expire_flag = 0
)
SELECT 
  qa.quintile,
  qa.n_patients,
  qa.mortality_percent,
  qa.complication_percent,
  sl.median_los_survivors
FROM quintile_agg qa
LEFT JOIN (
  SELECT DISTINCT quintile, median_los_survivors 
  FROM survivor_los
) sl ON qa.quintile = sl.quintile
ORDER BY qa.quintile;