WITH 
-- Identify heart rate itemid from d_items
heart_rate_item AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Heart Rate%' 
  OR label = 'Heart Rate'
),

-- Select relevant patient and ICU stay information
patient_info AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Select first chartevents for heart rate
first_heart_rate AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    heart_rate_item hri ON ce.itemid = hri.itemid
  WHERE 
    ce.valuenum IS NOT NULL 
    AND ce.valueuom = 'bpm'
)

-- Join patient info with first heart rate
SELECT 
  MIN(fhr.valuenum) AS min_first_heart_rate
FROM 
  patient_info pi
JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` icu ON pi.subject_id = icu.subject_id
JOIN 
  first_heart_rate fhr ON icu.stay_id = fhr.stay_id
WHERE 
  fhr.charttime = (SELECT MIN(charttime) FROM first_heart_rate WHERE stay_id = icu.stay_id);