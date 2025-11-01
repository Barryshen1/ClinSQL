WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN icu_exists.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_icu,
    (SELECT COUNT(DISTINCT d.icd_code) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.subject_id = a.subject_id 
       AND d.hadm_id = a.hadm_id 
       AND d.icd_code NOT LIKE 'I50%'
       AND d.icd_version = 'ICD-10') AS comorbidity_count,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id
    AND a.hadm_id = diag.hadm_id
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id, stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu_exists
    ON a.subject_id = icu_exists.subject_id
    AND a.hadm_id = icu_exists.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND diag.seq_num = 1
    AND diag.icd_code LIKE 'I50%'
    AND diag.icd_version = 'ICD-10'
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
),
summary AS (
  SELECT 
    is_icu,
    -- LOS buckets
    SUM(CASE WHEN los_days <= 3 THEN 1 ELSE 0 END) AS n_leq3,
    SUM(CASE WHEN los_days BETWEEN 4 AND 6 THEN 1 ELSE 0 END) AS n_4to6,
    SUM(CASE WHEN los_days BETWEEN 7 AND 10 THEN 1 ELSE 0 END) AS n_7to10,
    SUM(CASE WHEN los_days > 10 THEN 1 ELSE 0 END) AS n_gt10,
    COUNT(*) AS total_admissions,
    -- Mortality and avg comorbidities
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(comorbidity_count AS FLOAT64)) AS avg_comorbidity_count
  FROM cohort
  GROUP BY is_icu
)
SELECT 
  is_icu,
  total_admissions,
  ROUND((n_leq3 * 100.0 / total_admissions), 1) AS pct_los_leq3,
  ROUND((n_4to6 * 100.0 / total_admissions), 1) AS pct_los_4to6,
  ROUND((n_7to10 * 100.0 / total_admissions), 1) AS pct_los_7to10,
  ROUND((n_gt10 * 100.0 / total_admissions), 1) AS pct_los_gt10,
  ROUND(mortality_rate * 100.0, 1) AS in_hospital_mortality_pct,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY is_icu) AS median_los_days,
  ROUND(avg_comorbidity_count, 1) AS avg_comorbidity_count
FROM (
  SELECT 
    c.is_icu,
    s.*,
    c.los_days
  FROM summary s
  JOIN cohort c ON s.is_icu = c.is_icu
)
GROUP BY is_icu, total_admissions, n_leq3, n_4to6, n_7to10, n_gt10, mortality_rate, avg_comorbidity_count
ORDER BY is_icu DESC;