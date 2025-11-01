WITH filtered_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id 
    AND a.hadm_id = i.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.subject_id = t.subject_id 
    AND a.hadm_id = t.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.subject_id = ie.subject_id
    AND i.hadm_id = ie.hadm_id
    AND i.stay_id = ie.stay_id
  WHERE 
    p.anchor_age BETWEEN 44 AND 54
    AND p.gender = 'M'
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.dischtime IS NOT NULL
    AND t.eventtype = 'admit'
    AND t.careunit LIKE '%Renal%'
    AND ie.itemid = 225798  -- Hemodialysis
    AND ie.amount > 0      -- Confirm administration
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  filtered_patients;