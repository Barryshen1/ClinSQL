WITH patients_filtered AS (
  SELECT
    subject_id,
    anchor_age,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 53 AND 63
),
admissions_filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
),
sepsis_status AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN MAX(CASE WHEN di.long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) = 1 THEN 'septic shock'
      WHEN MAX(CASE WHEN di.long_title LIKE '%sepsis%' THEN 1 ELSE 0 END) = 1 THEN 'sepsis'
      ELSE NULL
    END AS sepsis_group
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%sepsis%' OR di.long_title LIKE '%septic shock%'
  GROUP BY d.subject_id, d.hadm_id
),
main_data AS (
  SELECT
    s.sepsis_group,
    a.hospital_expire_flag,
    a.deathtime,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM admissions_filtered a
  JOIN sepsis_status s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE s.sepsis_group IS NOT NULL
),
grouped_data AS (
  SELECT
    sepsis_group,
    CASE WHEN los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    COUNT(*) AS N,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(deathtime, admittime, DAY)) AS median_time_to_death_days
  FROM main_data
  GROUP BY sepsis_group, los_group
)
SELECT
  sepsis_group,
  MAX(CASE WHEN los_group = '<=7' THEN N END) AS N_le7,
  MAX(CASE WHEN los_group = '<=7' THEN mortality_percent END) AS mortality_le7,
  MAX(CASE WHEN los_group = '<=7' THEN median_time_to_death_days END) AS median_time_to_death_le7,
  MAX(CASE WHEN los_group = '>7' THEN N END) AS N_gt7,
  MAX(CASE WHEN los_group = '>7' THEN mortality_percent END) AS mortality_gt7,
  MAX(CASE WHEN los_group = '>7' THEN median_time_to_death_days END) AS median_time_to_death_gt7,
  (MAX(CASE WHEN los_group = '<=7' THEN mortality_percent END) - MAX(CASE WHEN los_group = '>7' THEN mortality_percent END)) AS absolute_mortality_difference,
  ((MAX(CASE WHEN los_group = '<=7' THEN mortality_percent END) - MAX(CASE WHEN los_group = '>7' THEN mortality_percent END)) / NULLIF(MAX(CASE WHEN los_group = '>7' THEN mortality_percent END), 0)) AS relative_mortality_difference
FROM grouped_data
GROUP BY sepsis_group;