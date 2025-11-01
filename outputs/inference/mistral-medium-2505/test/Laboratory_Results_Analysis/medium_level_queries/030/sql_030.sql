WITH
-- Get female patients aged 64-74
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),

-- Get AMI admissions (ICD-10 codes for AMI: I21.x)
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I21%'
    AND a.subject_id IN (SELECT subject_id FROM female_patients)
),

-- Get the first troponin T measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM ami_admissions)
    AND d.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
)

-- Categorize troponin levels and calculate percentages
SELECT
  troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM (
  SELECT
    CASE
      WHEN valuenum <= 0.014 THEN 'Normal (≤0.014)'
      WHEN valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline (0.015–0.052)'
      WHEN valuenum > 0.052 THEN 'Myocardial Injury (>0.052)'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    first_troponin
  WHERE
    rn = 1  -- Only the first measurement per admission
)
GROUP BY
  troponin_category
ORDER BY
  patient_count DESC;