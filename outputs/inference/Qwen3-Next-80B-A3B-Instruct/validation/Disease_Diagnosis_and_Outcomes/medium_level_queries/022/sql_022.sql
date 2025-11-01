WITH sepsis_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.icd_code IN ('995.92', 'A41.9', 'R65.20')  -- sepsis codes
    AND d.icd_code NOT IN ('785.52', 'R65.21')       -- exclude septic shock
),

male_50_60 AS (
  SELECT
    p.subject_id,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),

admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN sepsis_patients sp ON a.hadm_id = sp.hadm_id
  INNER JOIN male_50_60 m ON a.subject_id = m.subject_id
),

icu_day1_flag AS (
  SELECT
    i.hadm_id,
    CASE
      WHEN MIN(i.intime) <= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR) THEN 1
      ELSE 0
    END AS day1_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN admissions_with_los a ON i.hadm_id = a.hadm_id
  GROUP BY i.hadm_id, a.admittime
),

final_data AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.los,
    CASE WHEN a.los <= 7 THEN 1 ELSE 0 END AS los_leq_7,
    COALESCE(i.day1_icu, 0) AS day1_icu  -- if no ICU stay, day1_icu = 0
  FROM admissions_with_los a
  LEFT JOIN icu_day1_flag i ON a.hadm_id = i.hadm_id
)

SELECT
  los_leq_7,
  day1_icu,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  PERCENTILE_CONT(los, 0.5) AS median_los_days
FROM final_data
GROUP BY los_leq_7, day1_icu
ORDER BY los_leq_7, day1_icu;