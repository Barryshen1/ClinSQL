WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 70 AND 80
  AND dicd.long_title LIKE '%Hemorrhagic stroke%'
),

-- Step 2: Calculate first-48-hour laboratory instability score
lab_instability AS (
  SELECT c.hadm_id, 
         COUNT(CASE WHEN l.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label IN ('Example Lab 1', 'Example Lab 2')) AND l.valuenum > 10 THEN 1 END) AS score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON icu.hadm_id = l.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, icu.intime, HOUR) <= 48
  GROUP BY c.hadm_id
),

-- Step 3 & 4: Calculate mean LOS and in-hospital mortality
los_mortality AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) AS mean_los,
    SAFE_DIVIDE(SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END), COUNT(DISTINCT a.hadm_id)) AS in_hospital_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort c ON a.hadm_id = c.hadm_id
),

-- Additional CTE to calculate cohort critical lab rate
cohort_critical_lab_rate AS (
  SELECT 
    SAFE_DIVIDE(COUNT(CASE WHEN l.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label IN ('Example Lab 1', 'Example Lab 2')) AND l.valuenum > 10 THEN 1 END), COUNT(DISTINCT c.hadm_id)) AS rate
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON icu.hadm_id = l.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, icu.intime, HOUR) <= 48
)

-- Final query
SELECT 
  PERCENTILE_CONT(lab.score, 0.25) OVER () AS percentile_25_lab_instability,
  cclr.rate AS cohort_critical_lab_rate,
  lm.mean_los,
  lm.in_hospital_mortality
FROM lab_instability lab
JOIN cohort c ON lab.hadm_id = c.hadm_id
CROSS JOIN los_mortality lm
CROSS JOIN cohort_critical_lab_rate cclr
LIMIT 1;