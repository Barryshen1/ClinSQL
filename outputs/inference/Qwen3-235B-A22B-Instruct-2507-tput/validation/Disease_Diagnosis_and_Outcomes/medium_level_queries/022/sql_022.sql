WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),

sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 10 AND (
      icd_code LIKE 'A41%' OR 
      icd_code = 'A409' OR 
      icd_code = 'R6520'
    ))
  )
),

septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10 AND icd_code = 'R6521'
),

sepsis_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN sepsis_codes sc
    ON di.icd_code = sc.icd_code
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2
    JOIN septic_shock_codes ss ON di2.icd_code = ss.icd_code
    WHERE di2.hadm_id = pa.hadm_id
  )
  AND pa.admittime IS NOT NULL
  AND pa.dischtime IS NOT NULL
  AND pa.los_days >= 0
),

icu_status AS (
  SELECT DISTINCT
    sa.hadm_id,
    sa.age,
    sa.gender,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    sa.los_days,
    CASE WHEN i.intime IS NOT NULL THEN 1 ELSE 0 END AS icu_day1
  FROM sepsis_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON sa.hadm_id = i.hadm_id
    AND i.intime <= DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
    AND i.intime >= sa.admittime
),

grouped_data AS (
  SELECT
    CASE WHEN los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_group,
    CASE WHEN icu_day1 = 1 THEN 'ICU Day-1' ELSE 'No ICU Day-1' END AS icu_day1,
    hospital_expire_flag,
    los_days
  FROM icu_status
)

SELECT
  los_group,
  icu_day1,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate,
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los
FROM grouped_data
GROUP BY los_group, icu_day1
ORDER BY los_group DESC, icu_day1;