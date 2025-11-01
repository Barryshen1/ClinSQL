WITH base_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS approx_age,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime ASC) AS rn_stay,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
),
first_stays AS (
  SELECT * 
  FROM base_stays 
  WHERE rn_stay = 1
),
ich_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%')) OR
    (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
  )
),
cohort AS (
  SELECT fs.*
  FROM first_stays fs
  INNER JOIN ich_hadms ih 
    ON fs.hadm_id = ih.hadm_id
  WHERE fs.gender = 'M' 
    AND fs.approx_age BETWEEN 60 AND 70
),
proc_burden_cohort AS (
  SELECT 
    pe.stay_id,
    COUNT(*) AS procedure_burden
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN cohort c 
    ON pe.stay_id = c.stay_id
  WHERE pe.starttime >= c.intime
    AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY pe.stay_id
),
cohort_metrics AS (
  SELECT 
    PERCENTILE_CONT(COALESCE(pbc.procedure_burden, 0), 0.75) AS p75_procedure_burden,
    AVG(c.los) AS cohort_mean_los,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS cohort_mortality
  FROM cohort c
  LEFT JOIN proc_burden_cohort pbc 
    ON c.stay_id = pbc.stay_id
),
general_metrics AS (
  SELECT 
    (SELECT AVG(los) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS general_mean_los,
    (SELECT AVG(CAST(a.hospital_expire_flag AS FLOAT64))
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
     INNER JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) i
       ON a.hadm_id = i.hadm_id) AS general_mortality
)
SELECT 
  cm.p75_procedure_burden,
  cm.cohort_mean_los,
  cm.cohort_mortality,
  gm.general_mean_los,
  gm.general_mortality
FROM cohort_metrics cm
CROSS JOIN general_metrics gm;