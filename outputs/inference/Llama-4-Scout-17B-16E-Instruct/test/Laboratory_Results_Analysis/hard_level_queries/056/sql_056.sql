WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' AND
    p.anchor_age BETWEEN 55 AND 65
),

-- Get lab events in the first 48 hours
lab_events_48hrs AS (
  SELECT 
    lo.subject_id,
    lo.hadm_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM 
    patients_of_interest lo
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON 
    lo.subject_id = le.subject_id AND lo.hadm_id = le.hadm_id
  WHERE 
    le.charttime BETWEEN lo.admittime AND TIMESTAMP_ADD(lo.admittime, INTERVAL 48 HOUR)
),

-- Calculate instability score for each patient
lab_instability_score AS (
  SELECT 
    subject_id,
    hadm_id,
    itemid,
    charttime,
    valuenum,
    LAG(valuenum) OVER (PARTITION BY subject_id, hadm_id, itemid ORDER BY charttime) AS prev_valuenum
  FROM 
    lab_events_48hrs
),

-- Calculate absolute differences
lab_diff AS (
  SELECT 
    subject_id,
    hadm_id,
    itemid,
    ABS(valuenum - prev_valuenum) AS instability_score
  FROM 
    lab_instability_score
  WHERE 
    prev_valuenum IS NOT NULL
),

-- Average instability score per patient
patient_instability AS (
  SELECT 
    subject_id,
    hadm_id,
    AVG(instability_score) AS avg_instability_score
  FROM 
    lab_diff
  GROUP BY 
    subject_id, hadm_id
),

-- Calculate 95th percentile of lab instability score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(avg_instability_score, 100)[OFFSET(95)] AS percentile_95
  FROM 
    patient_instability
),

-- Patients with high lab instability score
high_instability_patients AS (
  SELECT 
    pi.subject_id,
    pi.hadm_id,
    a.dischtime,
    a.deathtime,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality,
    DATEDIFF(a.dischtime, a.admittime) AS los
  FROM 
    patient_instability pi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    pi.subject_id = a.subject_id AND pi.hadm_id = a.hadm_id
  WHERE 
    pi.avg_instability_score > (SELECT percentile_95 FROM percentile_score)
),

-- General inpatients for comparison
general_inpatients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality,
    DATEDIFF(a.dischtime, a.admittime) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Final comparison
SELECT 
  'High Instability' AS patient_group,
  AVG(los) AS avg_los,
  AVG(mortality) AS avg_mortality,
  COUNT(*) AS patient_count
FROM 
  high_instability_patients
UNION ALL
SELECT 
  'General Inpatients' AS patient_group,
  AVG(los) AS avg_los,
  AVG(mortality) AS avg_mortality,
  COUNT(*) AS patient_count
FROM 
  general_inpatients;