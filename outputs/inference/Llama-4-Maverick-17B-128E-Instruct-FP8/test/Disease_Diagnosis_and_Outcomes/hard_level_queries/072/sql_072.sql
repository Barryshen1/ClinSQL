WITH 
acs_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Acute coronary syndrome%' OR d_icd.long_title LIKE '%Myocardial infarction%'
),
cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN acs_patients ON a.hadm_id = acs_patients.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
),
mortality AS (
  SELECT c.hadm_id, 
         CASE WHEN a.dischtime <= DATE_ADD(a.admittime, INTERVAL 30 DAY) AND a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS died_within_30_days
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),
los AS (
  SELECT c.hadm_id, 
         DATE_DIFF(icu.outtime, icu.intime, DAY) AS los
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  WHERE a.deathtime IS NULL OR a.deathtime > icu.outtime
)
SELECT 
  AVG(NULL) AS mean_risk_score,  
  AVG(m.died_within_30_days) AS thirty_day_mortality,
  AVG(l.los) AS mean_los_survivors
FROM cohort c
LEFT JOIN mortality m ON c.hadm_id = m.hadm_id
LEFT JOIN los l ON c.hadm_id = l.hadm_id;