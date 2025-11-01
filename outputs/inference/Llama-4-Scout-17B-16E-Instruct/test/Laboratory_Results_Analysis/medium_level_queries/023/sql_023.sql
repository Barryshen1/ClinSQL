WITH 
-- Identify female patients aged 67-77
patients_eligible AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 67 AND 77
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9')  -- ICD-9 codes for ACS
    AND a.admission_type = 'elective'  -- Assuming ACS is often an emergency but can be elective for some analyses; adjust as needed
),

-- Link eligible patients with ACS admissions
eligible_acs AS (
  SELECT pa.subject_id, a.hadm_id
  FROM patients_eligible pa
  JOIN acs_admissions a ON pa.subject_id = a.subject_id
),

-- Find initial Troponin T levels
troponin_levels AS (
  SELECT el.subject_id, el.hadm_id, MIN(le.charttime) AS first_troponin_time,
         ANY_VALUE(le.valuenum) AS troponin_value
  FROM eligible_acs el
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON el.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE di.label LIKE '%Troponin%'
  GROUP BY el.subject_id, el.hadm_id
),

-- Categorize Troponin T levels and calculate mortality
troponin_categories AS (
  SELECT 
    CASE 
      WHEN troponin_value <= 0.04 THEN 'normal'
      WHEN troponin_value BETWEEN 0.04 AND 0.1 THEN 'borderline'
      WHEN troponin_value > 0.1 THEN 'elevated'
      ELSE 'unknown'
    END AS troponin_category,
    ea.hadm_id,
    ea.subject_id,
    IF(a.hospital_expire_flag = 1, 1, 0) AS in_hospital_mortality
  FROM troponin_levels tl
  JOIN eligible_acs ea ON tl.subject_id = ea.subject_id AND tl.hadm_id = ea.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ea.hadm_id = a.hadm_id
)

-- Final aggregation
SELECT 
  troponin_category,
  COUNT(DISTINCT hadm_id) AS count_admissions,
  COUNT(DISTINCT hadm_id) / SUM(COUNT(DISTINCT hadm_id)) OVER () AS percent_admissions,
  AVG(in_hospital_mortality) AS in_hospital_mortality_rate
FROM troponin_categories
GROUP BY troponin_category;