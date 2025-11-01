WITH
-- Define our patient cohort: men 64-74 with diabetes and acute HF
patient_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admission_type = 'INPATIENT'
    -- Diabetes ICD-10 codes (E11.x, E13.x)
    AND (d1.icd_code LIKE 'E11%' OR d1.icd_code LIKE 'E13%')
    -- Acute HF ICD-10 codes
    AND (d2.icd_code IN ('I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'))
    AND d1.subject_id = d2.subject_id
),

-- Define medication classes with their identifying patterns
medication_classes AS (
  SELECT 'Insulin' AS class, 'insulin' AS pattern UNION ALL
  SELECT 'Metformin', 'metformin' UNION ALL
  SELECT 'Sulfonylureas', 'sulfonylurea' UNION ALL
  SELECT 'DPP-4', 'dpp-4' UNION ALL
  SELECT 'SGLT2', 'sglt2' UNION ALL
  SELECT 'GLP-1', 'glp-1' UNION ALL
  SELECT 'TZDs', 'thiazolidinedione'
),

-- Get all prescriptions for our cohort
cohort_prescriptions AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pr.starttime,
    pr.drug,
    pr.drug_type,
    pr.ndc,
    pr.route
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),

-- Identify first initiation of each medication class
first_initiations AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    m.class,
    MIN(TIMESTAMP_DIFF(c.starttime, c.admittime, HOUR)) AS hours_after_admission
  FROM cohort_prescriptions c
  CROSS JOIN medication_classes m
  WHERE LOWER(c.drug) LIKE '%' || m.pattern || '%'
     OR LOWER(c.drug_type) LIKE '%' || m.pattern || '%'
     OR LOWER(c.ndc) LIKE '%' || m.pattern || '%'
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, m.class
),

-- Calculate time windows for each admission
time_windows AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) AS first_12h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AS final_48h_start
  FROM patient_cohort
),

-- Classify initiations into time windows
classified_initiations AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.class,
    CASE
      WHEN f.hours_after_admission <= 12 THEN 'First 12h'
      WHEN f.hours_after_admission >= TIMESTAMP_DIFF(t.final_48h_start, t.admittime, HOUR) THEN 'Final 48h'
      ELSE 'Other'
    END AS time_window
  FROM first_initiations f
  JOIN time_windows t ON f.hadm_id = t.hadm_id
  WHERE f.hours_after_admission <= TIMESTAMP_DIFF(t.dischtime, t.admittime, HOUR)
),

-- Count initiations by class and time window
initiation_counts AS (
  SELECT
    class,
    time_window,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM classified_initiations
  WHERE time_window IN ('First 12h', 'Final 48h')
  GROUP BY class, time_window
),

-- Get total number of patients in cohort
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total
  FROM patient_cohort
)

-- Calculate percentages
SELECT
  i.class,
  i.time_window,
  i.patient_count,
  ROUND(i.patient_count * 100.0 / t.total, 1) AS percentage
FROM initiation_counts i
CROSS JOIN total_patients t
ORDER BY i.class, i.time_window;