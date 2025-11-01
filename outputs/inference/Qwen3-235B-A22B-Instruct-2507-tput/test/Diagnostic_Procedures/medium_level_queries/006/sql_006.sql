WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
    AND LOWER(long_title) NOT LIKE '%shock%'
    AND LOWER(long_title) NOT LIKE '%severe sepsis%'
),
shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('R65.20', 'R65.21')
    OR LOWER(long_title) LIKE '%septic shock%'
    OR LOWER(long_title) LIKE '%severe sepsis%'
),
patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
sepsis_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN sepsis_codes sc ON di.icd_code = sc.icd_code AND di.icd_version = 10
    WHERE di.hadm_id = pa.hadm_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN shock_codes sh ON di.icd_code = sh.icd_code AND di.icd_version = 10
    WHERE di.hadm_id = pa.hadm_id
  )
),
ultrasound_procs AS (
  SELECT pe.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultrasound%'
    OR LOWER(di.category) LIKE '%ultrasound%'
  GROUP BY pe.hadm_id
),
admissions_with_us AS (
  SELECT
    sa.hadm_id,
    sa.los_days,
    sa.had_icu,
    COALESCE(up.ultrasound_count, 0) AS ultrasound_count
  FROM sepsis_admissions sa
  LEFT JOIN ultrasound_procs up ON sa.hadm_id = up.hadm_id
  WHERE sa.los_days BETWEEN 1 AND 8
),
stratified AS (
  SELECT
    had_icu,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    ultrasound_count
  FROM admissions_with_us
)
SELECT
  had_icu,
  los_group,
  COUNT(*) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM stratified
GROUP BY had_icu, los_group
ORDER BY had_icu, los_group;