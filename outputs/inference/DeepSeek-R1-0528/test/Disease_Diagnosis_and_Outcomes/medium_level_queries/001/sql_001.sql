WITH base_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'M'
    AND ( 
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
    )
),
cohort_filtered AS (
  SELECT *
  FROM base_cohort
  WHERE age_at_admit BETWEEN 67 AND 77
),
icu_stay_flag AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN icu.intime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS icu_day1
  FROM cohort_filtered c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
  GROUP BY c.hadm_id
),
ckd_flag AS (
  SELECT 
    d.hadm_id,
    1 AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN cohort_filtered c
    ON d.hadm_id = c.hadm_id
  WHERE 
    (d.icd_version = 9 AND (
      d.icd_code LIKE '585%' OR 
      d.icd_code LIKE '586%' OR 
      d.icd_code LIKE '587%' OR 
      d.icd_code LIKE '588%' OR 
      d.icd_code LIKE '589%'
    )) OR
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'N18%' OR 
      d.icd_code LIKE 'N19%' OR 
      d.icd_code LIKE 'I12%' OR 
      d.icd_code LIKE 'I13%'
    ))
  GROUP BY d.hadm_id
),
diabetes_flag AS (
  SELECT 
    d.hadm_id,
    1 AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN cohort_filtered c
    ON d.hadm_id = c.hadm_id
  WHERE 
    (d.icd_version = 9 AND (
      d.icd_code LIKE '250%' OR 
      d.icd_code LIKE '6480%' OR 
      d.icd_code LIKE '6488%'
    )) OR
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'E1%' OR 
      d.icd_code LIKE 'O24%'
    ))
  GROUP BY d.hadm_id
),
cohort_with_flags AS (
  SELECT 
    c.*,
    COALESCE(i.icu_day1, 0) AS icu_day1,
    COALESCE(ck.ckd_flag, 0) AS ckd_flag,
    COALESCE(di.diabetes_flag, 0) AS diabetes_flag
  FROM cohort_filtered c
  LEFT JOIN icu_stay_flag i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN ckd_flag ck
    ON c.hadm_id = ck.hadm_id
  LEFT JOIN diabetes_flag di
    ON c.hadm_id = di.hadm_id
)
SELECT 
  CASE 
    WHEN los_days <= 7 THEN '≤7 days' 
    ELSE '>7 days' 
  END AS los_group,
  CASE 
    WHEN icu_day1 = 1 THEN 'ICU day 1' 
    ELSE 'No ICU day 1' 
  END AS icu_status,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage,
  SUM(ckd_flag) AS ckd_cases,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 2) AS ckd_percentage,
  SUM(diabetes_flag) AS diabetes_cases,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*), 2) AS diabetes_percentage
FROM cohort_with_flags
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;