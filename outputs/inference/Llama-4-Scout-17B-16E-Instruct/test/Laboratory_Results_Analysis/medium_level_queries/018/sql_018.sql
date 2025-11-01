WITH 
-- Identify ACS admissions
acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  WHERE d.icd_code LIKE 'I24%'  -- ACS ICD codes
    AND a.admission_type IN ('elective', 'urgent', 'emergency')  -- Assuming ACS can be elective or not, adjust as needed
),

-- Patient demographics and admission details
patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND a.dischtime IS NOT NULL
),

-- Troponin T lab results
troponin_results AS (
  SELECT 
    subject_id,
    hadm_id,
    charttime,
    value,
    valuenum,
    valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 4569  -- Troponin T
),

-- Categorize Troponin T results
troponin_categories AS (
  SELECT 
    tr.subject_id,
    tr.hadm_id,
    tr.valuenum,
    CASE
      WHEN tr.valuenum < 0.01 THEN 'normal'
      WHEN tr.valuenum BETWEEN 0.01 AND 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM troponin_results tr
)

-- Final analysis
SELECT 
  tc.troponin_category,
  COUNT(DISTINCT pd.hadm_id) AS count,
  COUNT(DISTINCT pd.hadm_id) / SUM(COUNT(DISTINCT pd.hadm_id)) OVER () AS percentage,
  AVG(pd.los) AS mean_los
FROM patient_data pd
JOIN troponin_categories tc ON pd.hadm_id = tc.hadm_id AND pd.subject_id = tc.subject_id
GROUP BY tc.troponin_category;