WITH 
  -- Identify respiratory rate itemid
  respiratory_rate_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Respiratory Rate%'
  ),
  
  -- Select relevant patient information
  patient_info AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 38 AND 48 AND gender = 'F'
  ),
  
  -- Select ICU stay information
  icu_stay AS (
    SELECT subject_id, hadm_id, stay_id, intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Select respiratory rate chart events
  respiratory_rate_events AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id, 
      ce.charttime, 
      ce.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    CROSS JOIN respiratory_rate_itemid rri
    WHERE 
      ce.itemid = rri.itemid AND 
      ce.valuenum IS NOT NULL
  )

-- Find maximum respiratory rate in the first 24 hours for eligible patients
SELECT 
  pi.subject_id,
  MAX(rre.valuenum) AS max_respiratory_rate
FROM 
  patient_info pi
  JOIN icu_stay isy ON pi.subject_id = isy.subject_id
  JOIN respiratory_rate_events rre ON isy.stay_id = rre.stay_id
WHERE 
  rre.charttime BETWEEN isy.intime AND TIMESTAMP_ADD(isy.intime, INTERVAL 24 HOUR)
GROUP BY 
  pi.subject_id;