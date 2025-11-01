WITH sepsis_cases AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON diag.icd_code = ddi.icd_code
    AND diag.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%sepsis%'
    AND LOWER(ddi.long_title) NOT LIKE '%septic shock%'
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN sepsis_cases s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),
icu_day1 AS (
  SELECT DISTINCT icu.hadm_id, 1 AS day1_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE icu.intime < TIMESTAMP_ADD(adm.admittime, INTERVAL 1 DAY)
)
SELECT
  CASE WHEN c.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
  COALESCE(i.day1_icu, 0) AS day1_icu,
  COUNT(*) AS total_cases,
  ROUND(100 * SUM(c.hospital_expire_flag) / COUNT(*), 1) AS mortality_percent,
  APPROX_QUANTILES(c.los_days, 2)[OFFSET(1)] AS median_los_days
FROM cohort c
LEFT JOIN icu_day1 i
  ON c.hadm_id = i.hadm_id
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;