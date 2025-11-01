WITH ich_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
    OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
  )
),
cohort AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN ich_hadm ih ON i.hadm_id = ih.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
procedure_count AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime <= c.intime + INTERVAL 72 HOUR
  GROUP BY c.stay_id
),
cohort_stats AS (
  SELECT 
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY procedure_count) AS p25,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY procedure_count) AS p50,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY procedure_count) AS p90,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS cohort_los,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS cohort_mortality
  FROM procedure_count pc
  JOIN cohort c ON pc.stay_id = c.stay_id
),
general_icu AS (
  SELECT 
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
general_stats AS (
  SELECT 
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS general_los,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS general_mortality
  FROM general_icu
)
SELECT 
  p25, p50, p90,
  cohort_los, cohort_mortality,
  general_los, general_mortality
FROM cohort_stats, general_stats;