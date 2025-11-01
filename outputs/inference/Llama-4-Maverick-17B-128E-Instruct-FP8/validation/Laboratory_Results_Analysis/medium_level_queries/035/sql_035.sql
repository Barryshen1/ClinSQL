WITH 
-- Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 73 AND 83
),

-- Get admissions for eligible patients
eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
),

-- Get the first Troponin T measurement for each admission
troponin_t AS (
  SELECT le.hadm_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE di.label LIKE '%Troponin T%' AND le.valuenum IS NOT NULL
)

-- Main query to summarize cohort statistics
SELECT 
  COUNT(*) AS num_patients,
  AVG(DATETIME_DIFF(ea.dischtime, ea.admittime, HOUR) / 24) AS avg_los_days,
  SUM(ea.hospital_expire_flag) / COUNT(*) AS in_hospital_mortality
FROM eligible_admissions ea
JOIN troponin_t tt ON ea.hadm_id = tt.hadm_id
WHERE tt.rn = 1 AND tt.valuenum > 0.1;