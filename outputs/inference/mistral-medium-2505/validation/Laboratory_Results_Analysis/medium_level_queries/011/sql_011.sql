WITH
-- Define chest pain ICD codes (common codes for chest pain)
chest_pain_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
    OR icd_code IN ('R07.1', 'R07.2', 'R07.89', 'R07.9', 'I20.9', 'I21.9', 'I24.9')
),

-- Get male patients aged 61-71 with chest pain admission
eligible_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN chest_pain_icd c ON d.icd_code = c.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T, High Sensitivity'
    AND le.hadm_id IN (SELECT hadm_id FROM eligible_patients)
    AND le.valuenum IS NOT NULL
),

-- Categorize hs-TnT values
hs_tnt_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN valuenum < 14 THEN 'Normal (<14 ng/L)'
      WHEN valuenum BETWEEN 14 AND 50 THEN 'Borderline (14-50 ng/L)'
      WHEN valuenum > 50 THEN 'Myocardial Injury (>50 ng/L)'
      ELSE 'Unknown'
    END AS hs_tnt_category
  FROM first_hs_tnt
  WHERE rn = 1  -- Only first measurement per admission
)

-- Calculate percentage distribution
SELECT
  hs_tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM hs_tnt_categories
GROUP BY hs_tnt_category
ORDER BY
  CASE hs_tnt_category
    WHEN 'Normal (<14 ng/L)' THEN 1
    WHEN 'Borderline (14-50 ng/L)' THEN 2
    WHEN 'Myocardial Injury (>50 ng/L)' THEN 3
    ELSE 4
  END;