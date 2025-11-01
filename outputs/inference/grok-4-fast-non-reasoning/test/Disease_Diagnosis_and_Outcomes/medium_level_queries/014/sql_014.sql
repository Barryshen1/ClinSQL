WITH cohort AS (
  -- Base cohort: male, age 77-87, HF principal diagnosis
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
    AND d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I50%') OR
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '428%')
    )
    AND a.dischtime IS NOT NULL
    AND (a.deathtime IS NULL OR a.deathtime >= a.dischtime)
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0  -- Exclude zero-day
),

comorbidities AS (
  -- Flag CKD and diabetes per hadm_id (any diagnosis, not just principal)
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN (
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'N18%') OR
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '585%')
    ) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (
      (d.icd_version = 'ICD-10' AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')) OR
      (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '250%' OR d.icd_code LIKE '249%'))
    ) THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),

day1_icu AS (
  -- Flag day-1 ICU: any transfer to ICU within 1 day of admit
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN t.careunit IN ('CCU', 'CSRU', 'MICU', 'SICU', 'NICU', 'Neuro ICU') 
             AND t.intime >= c.admittime
             AND t.intime <= TIMESTAMP_ADD(TIMESTAMP(c.admittime), INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS day1_icu
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  CASE WHEN di.day1_icu = 1 THEN 'ICU' ELSE 'non-ICU' END AS day1_status,
  CASE 
    WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE '>=8 days'
  END AS los_group,
  ROUND(AVG(CAST(c.hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND(PERCENTILE_CONT(CAST(c.los_days AS FLOAT64), 0.5) IGNORE NULLS, 2) AS median_los_days,
  ROUND(AVG(CAST(com.has_ckd AS FLOAT64)) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(CAST(com.has_diabetes AS FLOAT64)) * 100, 2) AS diabetes_prevalence_pct,
  COUNT(*) AS n_admissions
FROM cohort c
LEFT JOIN comorbidities com
  ON c.hadm_id = com.hadm_id
LEFT JOIN day1_icu di
  ON c.hadm_id = di.hadm_id
WHERE c.los_days >= 1  -- Ensure LOS groups populated
GROUP BY di.day1_icu, los_group
ORDER BY day1_status, 
  CASE los_group 
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    ELSE 3
  END;