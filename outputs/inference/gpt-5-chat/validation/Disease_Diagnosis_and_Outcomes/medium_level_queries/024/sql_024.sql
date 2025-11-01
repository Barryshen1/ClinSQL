WITH sepsis_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.anchor_age, p.gender,
    a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%shock%'
),
ckd_flags AS (
  SELECT DISTINCT hadm_id, 1 AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic kidney disease%'
    OR dd.icd_code LIKE 'N18%' OR dd.icd_code LIKE '585%'
),
diab_flags AS (
  SELECT DISTINCT hadm_id, 1 AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%diabetes%'
    OR dd.icd_code LIKE 'E0%' OR dd.icd_code LIKE 'E1%'
    OR dd.icd_code LIKE '250%'
),
icu_day1 AS (
  SELECT hadm_id, MIN(intime) AS first_icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
)
SELECT 
  CASE WHEN DATE_DIFF(s.dischtime, s.admittime, DAY) <= 5 
       THEN 'LOS<=5' ELSE 'LOS>5' END AS los_group,
  CASE WHEN i.first_icu_intime IS NOT NULL 
            AND DATE_DIFF(i.first_icu_intime, s.admittime, DAY) = 0
       THEN 'Day1_ICU' ELSE 'NonICU_Day1' END AS day1_icu_group,
  COUNT(*) AS N,
  ROUND(100 * SUM(CASE WHEN s.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  ROUND(100 * SUM(CASE WHEN ck.has_ckd = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS ckd_percent,
  ROUND(100 * SUM(CASE WHEN db.has_diabetes = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS diabetes_percent
FROM sepsis_cohort s
LEFT JOIN icu_day1 i
  ON s.hadm_id = i.hadm_id
LEFT JOIN ckd_flags ck
  ON s.hadm_id = ck.hadm_id
LEFT JOIN diab_flags db
  ON s.hadm_id = db.hadm_id
GROUP BY los_group, day1_icu_group
ORDER BY los_group, day1_icu_group;