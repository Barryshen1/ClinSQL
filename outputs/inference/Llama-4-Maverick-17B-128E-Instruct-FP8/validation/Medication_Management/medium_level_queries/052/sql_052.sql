WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS stay_duration_hours
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATETIME_DIFF(icu.outtime, icu.intime, HOUR) >= 48
),
-- Step 2: Identify patients with type 2 diabetes and heart failure
diagnoses AS (
  SELECT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    (LOWER(d.long_title) LIKE '%type 2 diabetes%' OR LOWER(d.long_title) LIKE '%type ii diabetes%')
    AND di.icd_version = 10
  INTERSECT DISTINCT
  SELECT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%heart failure%'
    AND di.icd_version = 10
),
-- Step 3: Medication administration in the first 48 hours and last 24 hours
medication_use AS (
  SELECT 
    c.stay_id,
    c.intime,
    c.outtime,
    CASE 
      WHEN ie.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR) THEN 'First 48h'
      WHEN ie.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 24 HOUR) AND c.outtime THEN 'Last 24h'
    END AS time_frame,
    CASE 
      WHEN LOWER(di.label) LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Other'
    END AS medication_type
  FROM 
    cohort c
  JOIN 
    diagnoses d ON c.hadm_id = d.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie ON c.stay_id = ie.stay_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE 
    (ie.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
     OR ie.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 24 HOUR) AND c.outtime)
  UNION ALL
  SELECT 
    c.stay_id,
    c.intime,
    c.outtime,
    CASE 
      WHEN p.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR) THEN 'First 48h'
      WHEN p.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 24 HOUR) AND c.outtime THEN 'Last 24h'
    END AS time_frame,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%' 
           OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' THEN 'Oral'
      ELSE 'Other'
    END AS medication_type
  FROM 
    cohort c
  JOIN 
    diagnoses d ON c.hadm_id = d.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE 
    p.drug_type = 'RX'
    AND (p.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
         OR p.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 24 HOUR) AND c.outtime)
),
-- Step 4: Calculate percentages
percentages AS (
  SELECT 
    time_frame,
    medication_type,
    COUNT(DISTINCT stay_id) AS num_patients
  FROM 
    medication_use
  WHERE 
    medication_type IN ('Insulin', 'Oral')
  GROUP BY 
    time_frame, medication_type
),
total_counts AS (
  SELECT 
    time_frame,
    COUNT(DISTINCT stay_id) AS total_patients
  FROM 
    medication_use
  WHERE 
    medication_type IN ('Insulin', 'Oral')
  GROUP BY 
    time_frame
)

SELECT 
  p.time_frame,
  p.medication_type,
  (p.num_patients * 100.0 / tc.total_patients) AS percentage
FROM 
  percentages p
JOIN 
  total_counts tc ON p.time_frame = tc.time_frame
ORDER BY 
  p.time_frame, p.medication_type;