WITH cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 67 AND 77
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
    AND icd_code IN ('I500', 'I501', 'I509')
  )
),
mortality_comorbidities AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    a.hospital_expire_flag,
    CASE WHEN d.icd_code IN ('N18', 'N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189') THEN 1 ELSE 0 END AS ckd,
    CASE WHEN d.icd_code IN ('E10', 'E11', 'E13', 'E14') THEN 1 ELSE 0 END AS diabetes
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id AND d.icd_version = 10
),
los_icu_status AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    icu.stay_id IS NOT NULL AS icu_admission,
    CASE WHEN icu.intime IS NOT NULL AND DATETIME_DIFF(icu.intime, a.admittime, HOUR) <= 24 THEN 1 ELSE 0 END AS day1_icu
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.hadm_id = icu.hadm_id
)
SELECT 
  CASE 
    WHEN l.hospital_los <= 7 THEN 'LOS <= 7'
    ELSE 'LOS > 7'
  END AS los_group,
  l.day1_icu,
  COUNT(*) AS total_patients,
  SUM(mc.hospital_expire_flag) / COUNT(*) * 100 AS in_hospital_mortality,
  SUM(mc.ckd) / COUNT(*) * 100 AS ckd_prevalence,
  SUM(mc.diabetes) / COUNT(*) * 100 AS diabetes_prevalence
FROM mortality_comorbidities mc
JOIN los_icu_status l ON mc.hadm_id = l.hadm_id
GROUP BY los_group, l.day1_icu
ORDER BY los_group, l.day1_icu;