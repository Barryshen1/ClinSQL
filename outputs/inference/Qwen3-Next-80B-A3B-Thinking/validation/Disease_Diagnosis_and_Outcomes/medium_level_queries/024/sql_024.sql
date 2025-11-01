WITH sepsis_patients AS (
  SELECT hadm_id
  FROM (
    SELECT hadm_id,
           MAX(CASE WHEN icd_code LIKE 'A41%' OR icd_code = 'R65.20' THEN 1 ELSE 0 END) AS has_sepsis,
           MAX(CASE WHEN icd_code = 'R65.21' THEN 1 ELSE 0 END) AS has_septic_shock
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  ) AS s
  WHERE s.has_sepsis = 1 AND s.has_septic_shock = 0
),
icu_day1 AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN i.intime <= a.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END) AS is_icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
),
ckd_diagnoses AS (
  SELECT hadm_id, 1 AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'N18%'
),
diabetes_diagnoses AS (
  SELECT hadm_id, 1 AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'
)
SELECT
  CASE WHEN los <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
  CASE WHEN is_icu_day1 = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
  COUNT(*) AS N,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND(AVG(CAST(COALESCE(has_ckd, 0) AS FLOAT64)) * 100, 2) AS ckd_prevalence,
  ROUND(AVG(CAST(COALESCE(has_diabetes, 0) AS FLOAT64)) * 100, 2) AS diabetes_prevalence
FROM (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    i.is_icu_day1,
    c.has_ckd,
    d.has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_patients s ON a.hadm_id = s.hadm_id
  LEFT JOIN icu_day1 i ON a.hadm_id = i.hadm_id
  LEFT JOIN ckd_diagnoses c ON a.hadm_id = c.hadm_id
  LEFT JOIN diabetes_diagnoses d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
) subquery
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;