WITH
-- Get 76-year-old female patients
female_76yo_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 76
),

-- Get sepsis admissions (using common sepsis ICD codes)
sepsis_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM female_76yo_patients)
    AND (
      -- ICD-9 codes for sepsis
      (d.icd_version = 9 AND d.icd_code IN ('99591', '78552'))
      OR
      -- ICD-10 codes for sepsis
      (d.icd_version = 10 AND d.icd_code IN ('R6520', 'R6521'))
    )
),

-- Get platelet count itemid (using label 'Platelets')
platelet_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Platelets'
),

-- Get platelet counts within first 24 hours of admission
platelet_counts AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN sepsis_admissions s ON l.subject_id = s.subject_id AND l.hadm_id = s.hadm_id
  JOIN platelet_itemid p ON l.itemid = p.itemid
  WHERE l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL
),

-- Calculate average platelet count per patient over first 24 hours
avg_platelet_counts AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(platelet_count) AS avg_platelet_count
  FROM platelet_counts
  GROUP BY subject_id, hadm_id
)

-- Compute median of average platelet counts
SELECT
  PERCENTILE_DISC(avg_platelet_count, 0.5) AS median_platelet_count
FROM avg_platelet_counts
LIMIT 1;