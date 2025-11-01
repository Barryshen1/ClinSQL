WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id AND p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
),
sbp_data AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.valuenum AS sbp_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.subject_id = ce.subject_id 
    AND c.hadm_id = ce.hadm_id 
    AND c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN ( ... list of SBP itemids ... )
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND c.outtime
),
max_sbp_per_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    MAX(sbp_value) AS max_sbp
  FROM sbp_data
  GROUP BY subject_id, hadm_id, stay_id
)
SELECT 
  APPROX_QUANTILES(max_sbp, 100)[OFFSET(75)] AS p75_max_sbp
FROM max_sbp_per_stay;