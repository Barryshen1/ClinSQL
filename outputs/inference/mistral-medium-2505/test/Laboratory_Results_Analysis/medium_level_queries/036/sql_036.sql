WITH
-- Get AMI ICD codes (ICD-9: 410.xx, ICD-10: I21.x)
ami_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '410.%' OR icd_code LIKE 'I21.%'
),

-- Get male patients aged 77-87 with AMI admission
ami_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN ami_codes ac
    ON d.icd_code = ac.icd_code AND d.icd_version = ac.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM ami_patients)
    AND d.label = 'Troponin T, High Sensitivity'
    AND l.valuenum IS NOT NULL
)

-- Categorize and aggregate
SELECT
  CASE
    WHEN valuenum < 14 THEN 'Normal (< 14 ng/L)'
    WHEN valuenum BETWEEN 14 AND 50 THEN 'Borderline (14–50 ng/L)'
    WHEN valuenum > 50 THEN 'Myocardial Injury (> 50 ng/L)'
    ELSE 'Unknown'
  END AS hs_tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM first_hs_tnt
WHERE rn = 1  -- Only first measurement per admission
GROUP BY hs_tnt_category
ORDER BY
  CASE hs_tnt_category
    WHEN 'Normal (< 14 ng/L)' THEN 1
    WHEN 'Borderline (14–50 ng/L)' THEN 2
    WHEN 'Myocardial Injury (> 50 ng/L)' THEN 3
    ELSE 4
  END;