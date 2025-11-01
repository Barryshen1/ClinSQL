WITH
-- Define heart failure ICD codes (I50.*)
heart_failure_icd AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50%'
),

-- Get male patients aged 53-63 with heart failure
hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN heart_failure_icd hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
),

-- Get admissions for these patients with LOS and discharge info
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Approximate Charlson by counting common comorbidities
    (SELECT COUNT(DISTINCT d.icd_code)
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
     WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
     AND di.icd_code IN (
       -- Example comorbidities (expand as needed)
       'E11%', 'E13%', 'E14%', -- Diabetes
       'J44%', 'J45%', -- COPD
       'N18%', 'N19%', -- CKD
       'I25%', -- CAD
       'I63%', 'I64%' -- Stroke
     )) AS charlson_proxy
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_patients p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),

-- Categorize LOS and Charlson
categorized_admissions AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE 'Other'
    END AS los_category,
    CASE
      WHEN charlson_proxy <= 3 THEN '0-3'
      WHEN charlson_proxy BETWEEN 4 AND 5 THEN '4-5'
      WHEN charlson_proxy > 5 THEN '6+'
      ELSE 'Unknown'
    END AS charlson_category,
    hospital_expire_flag,
    discharge_location
  FROM hf_admissions
)

-- Final aggregation
SELECT
  los_category,
  charlson_category,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  -- Discharge destination percentages
  ROUND(SUM(CASE WHEN discharge_location = 'HOME' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS home_percentage,
  ROUND(SUM(CASE WHEN discharge_location = 'REHAB' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS rehab_percentage,
  ROUND(SUM(CASE WHEN discharge_location = 'SNF' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS snf_percentage,
  ROUND(SUM(CASE WHEN discharge_location = 'HOSPICE' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS hospice_percentage
FROM categorized_admissions
GROUP BY los_category, charlson_category
ORDER BY los_category, charlson_category;