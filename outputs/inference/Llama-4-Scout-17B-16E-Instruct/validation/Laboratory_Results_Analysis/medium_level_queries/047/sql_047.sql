WITH 
-- Identify Troponin T lab results
troponin_t AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE 
    di.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE 
    a.admission_type = 'ACUTE CORONARY SYNDROME'
),

-- Filter patients by age and gender
eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),

-- Combine criteria
eligible_admissions AS (
  SELECT 
    aa.hadm_id,
    aa.subject_id,
    tt.charttime,
    tt.valuenum
  FROM 
    acs_admissions aa
  JOIN 
    eligible_patients ep ON aa.subject_id = ep.subject_id
  JOIN 
    troponin_t tt ON aa.hadm_id = tt.hadm_id
  WHERE 
    tt.charttime = aa.admittime  -- Assuming initial troponin is at admission time
)

-- Calculate statistics
SELECT 
  COUNT(DISTINCT hadm_id) AS admission_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(valuenum) AS mean_troponin,
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3_troponin
FROM 
  eligible_admissions;