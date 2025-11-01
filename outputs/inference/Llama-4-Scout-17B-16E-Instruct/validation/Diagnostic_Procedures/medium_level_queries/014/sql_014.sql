WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
),

-- Identify admissions with ACS
acs_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.admission_type,
         CASE 
           WHEN d.icd_code IN ('I24.9', 'I25.84') AND d.seq_num = 1 THEN 'Primary'
           WHEN d.icd_code IN ('I24.9', 'I25.84') THEN 'Secondary'
           ELSE 'Non-ACS'
         END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code IN ('I24.9', 'I25.84')
  )
),

-- Calculate stay duration and categorize
stay_duration AS (
  SELECT hadm_id, 
         diagnosis_type,  -- Added diagnosis_type to the SELECT clause
         TIMESTAMP_DIFF(dischtime, admittime, DAY) AS stay_days,
         CASE 
           WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
           ELSE 'Out of range'
         END AS stay_category
  FROM acs_admissions
  WHERE diagnosis_type IN ('Primary', 'Secondary')
),

-- Identify ultrasounds
ultrasounds AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (
    -- Look up itemids for ultrasounds in d_items
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Ultrasound%' 
  )
  GROUP BY hadm_id
)

-- Final calculation
SELECT 
  sd.stay_category,
  sd.diagnosis_type,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM stay_duration sd
JOIN ultrasounds u ON sd.hadm_id = u.hadm_id
GROUP BY sd.stay_category, sd.diagnosis_type;