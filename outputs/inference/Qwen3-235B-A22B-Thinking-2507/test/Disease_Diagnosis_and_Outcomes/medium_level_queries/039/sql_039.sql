WITH base_cohort AS (
  SELECT 
    adm.hadm_id,
    pat.subject_id,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    adm.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
        )
    )
),
filtered_cohort AS (
  SELECT 
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS hospital_los_days,
    CASE 
      WHEN hospital_expire_flag = 1 
      THEN DATETIME_DIFF(deathtime, admittime, DAY) 
      ELSE NULL 
    END AS time_to_death_days
  FROM base_cohort
  WHERE age_at_admission BETWEEN 66 AND 76
),
grouped_data AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN hospital_los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN hospital_los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN hospital_los_days >= 8 THEN '>=8'
      ELSE NULL 
    END AS los_group,
    CASE 
      WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'emergent'
      WHEN admission_type = 'ELECTIVE' THEN 'non-emergent'
      ELSE NULL 
    END AS admission_category,
    hospital_expire_flag,
    time_to_death_days
  FROM filtered_cohort
)
SELECT 
  los_group,
  admission_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent,
  APPROX_QUANTILES(IF(hospital_expire_flag = 1, time_to_death_days, NULL), 1000)[OFFSET(500)] AS median_time_to_death_days
FROM grouped_data
WHERE los_group IS NOT NULL AND admission_category IS NOT NULL
GROUP BY los_group, admission_category
ORDER BY 
  CASE los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END,
  admission_category;