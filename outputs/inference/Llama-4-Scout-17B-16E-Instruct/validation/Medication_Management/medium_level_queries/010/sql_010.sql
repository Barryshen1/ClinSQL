WITH 
-- Define medication classes
medication_classes AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) LIKE '%glibenclamide%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%dpp-4%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%sglt2%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%glp-1%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%tzd%' OR LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE 'Other'
    END AS medication_class
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
),

-- Identify patients with T2DM and HF
patients_with_conditions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code IN (
      SELECT 
        icd_code 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
      WHERE 
        long_title IN ('Type 2 diabetes mellitus', 'Heart failure')
    )
),

-- Medication initiation timing
medication_init_timing AS (
  SELECT 
    pwt.subject_id,
    pwt.hadm_id,
    mc.medication_class,
    pwt.admittime,
    pwt.dischtime,
    mc.starttime
  FROM 
    patients_with_conditions pwt
  JOIN 
    medication_classes mc ON pwt.hadm_id = mc.hadm_id
)

-- Calculate initiation percentages
SELECT 
  medication_class,
  COUNT(CASE WHEN TIMESTAMP_DIFF(mc.starttime, pwt.admittime, HOUR) <= 12 THEN pwt.hadm_id END) * 100.0 / COUNT(DISTINCT pwt.hadm_id) AS init_12h,
  COUNT(CASE WHEN TIMESTAMP_DIFF(pwt.dischtime, mc.starttime, HOUR) <= 48 THEN pwt.hadm_id END) * 100.0 / COUNT(DISTINCT pwt.hadm_id) AS init_final_48h,
  COUNT(CASE WHEN TIMESTAMP_DIFF(pwt.dischtime, mc.starttime, HOUR) <= 48 THEN pwt.hadm_id END) * 100.0 / COUNT(DISTINCT pwt.hadm_id) - 
  COUNT(CASE WHEN TIMESTAMP_DIFF(mc.starttime, pwt.admittime, HOUR) <= 12 THEN pwt.hadm_id END) * 100.0 / COUNT(DISTINCT pwt.hadm_id) AS net_change
FROM 
  medication_init_timing pwt
GROUP BY 
  medication_class;