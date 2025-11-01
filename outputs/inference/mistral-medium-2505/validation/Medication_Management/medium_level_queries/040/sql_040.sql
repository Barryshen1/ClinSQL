WITH
-- Define our patient cohort: males 36-46 with diabetes and heart failure
patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND d1.icd_code LIKE 'E11%'  -- Type 2 diabetes
    AND d2.icd_code LIKE 'I50%'  -- Heart failure
    AND d1.subject_id = d2.subject_id
    AND d1.hadm_id = d2.hadm_id
),

-- Get all admissions for our cohort
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_cohort pc ON a.subject_id = pc.subject_id
),

-- Define drug classes (simplified - in practice would need a more comprehensive mapping)
drug_classes AS (
  SELECT
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Antidiabetic - Biguanides'
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Antidiabetic - Insulin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' THEN 'Antidiabetic - Sulfonylureas'
      WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%lasix%' THEN 'Cardiac - Diuretics'
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' THEN 'Cardiac - ACE Inhibitors'
      WHEN LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%metoprolol%' THEN 'Cardiac - Beta Blockers'
      WHEN LOWER(drug) LIKE '%digoxin%' THEN 'Cardiac - Cardiac Glycosides'
      ELSE 'Other'
    END AS drug_class,
    drug
  FROM (
    SELECT DISTINCT drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    UNION DISTINCT
    SELECT DISTINCT medication FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  )
),

-- Get all prescriptions with drug classes
prescriptions_with_classes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    dc.drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN drug_classes dc ON LOWER(p.drug) = LOWER(dc.drug)
  UNION ALL
  SELECT
    ph.subject_id,
    ph.hadm_id,
    ph.starttime,
    ph.stoptime,
    ph.medication AS drug,
    dc.drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN drug_classes dc ON LOWER(ph.medication) = LOWER(dc.drug)
),

-- Calculate first 48h and last 12h windows for each admission
time_windows AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS last_12h_start
  FROM cohort_admissions
),

-- Identify prescriptions in first 48h
first_48h_prescriptions AS (
  SELECT DISTINCT
    pwc.subject_id,
    pwc.hadm_id,
    pwc.drug_class
  FROM prescriptions_with_classes pwc
  JOIN time_windows tw ON pwc.hadm_id = tw.hadm_id
  WHERE pwc.starttime <= tw.first_48h_end
    AND (pwc.stoptime IS NULL OR pwc.stoptime >= pwc.starttime)
),

-- Identify prescriptions in last 12h
last_12h_prescriptions AS (
  SELECT DISTINCT
    pwc.subject_id,
    pwc.hadm_id,
    pwc.drug_class
  FROM prescriptions_with_classes pwc
  JOIN time_windows tw ON pwc.hadm_id = tw.hadm_id
  WHERE pwc.starttime <= tw.dischtime
    AND (pwc.stoptime IS NULL OR pwc.stoptime >= tw.last_12h_start)
),

-- Count patients with each drug class in each time window
drug_class_counts AS (
  SELECT
    drug_class,
    COUNT(DISTINCT subject_id) AS first_48h_count,
    0 AS last_12h_count
  FROM first_48h_prescriptions
  GROUP BY drug_class

  UNION ALL

  SELECT
    drug_class,
    0 AS first_48h_count,
    COUNT(DISTINCT subject_id) AS last_12h_count
  FROM last_12h_prescriptions
  GROUP BY drug_class
),

-- Pivot the counts for easier calculation
drug_class_stats AS (
  SELECT
    drug_class,
    SUM(first_48h_count) AS first_48h_count,
    SUM(last_12h_count) AS last_12h_count
  FROM drug_class_counts
  GROUP BY drug_class
),

-- Get total number of patients in cohort
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total
  FROM patient_cohort
)

-- Final calculation of prevalence and differences
SELECT
  dcs.drug_class,
  ROUND(100 * dcs.first_48h_count / tp.total, 2) AS first_48h_prevalence,
  ROUND(100 * dcs.last_12h_count / tp.total, 2) AS last_12h_prevalence,
  ROUND(100 * (dcs.first_48h_count - dcs.last_12h_count) / tp.total, 2) AS absolute_difference_pp
FROM drug_class_stats dcs
CROSS JOIN total_patients tp
WHERE dcs.drug_class LIKE 'Antidiabetic%' OR dcs.drug_class LIKE 'Cardiac%'
ORDER BY dcs.drug_class;