WITH 
-- Define the population of interest
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 44 AND 54
),

-- Get admissions and first 24 hours
admissions_info AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    patients_of_interest p ON a.subject_id = p.subject_id
),

-- Find itemid for heart rate
heart_rate_itemid AS (
  SELECT 
    itemid
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE 
    label = 'Heart Rate'
),

-- Get heart rate records within first 24 hours
heart_rate_records AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.stay_id, 
    c.charttime, 
    c.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    heart_rate_itemid h ON c.itemid = h.itemid
  JOIN 
    admissions_info a ON c.hadm_id = a.hadm_id
  WHERE 
    c.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
)

-- Find the minimum heart rate
SELECT 
  MIN(valuenum) AS min_heart_rate
FROM 
  heart_rate_records;