WITH
-- Female patients aged 40-50
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- Admissions with AMI diagnosis
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- ICD-9 codes for AMI
      (d.icd_version = 9 AND d.icd_code LIKE '410.%')
      OR
      -- ICD-10 codes for AMI
      (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    )
),

-- First Troponin T measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM ami_admissions)
    AND di.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
)

-- Categorize Troponin T values
SELECT
  COUNT(CASE WHEN ft.valuenum < 0.01 THEN 1 END) AS normal_count,
  COUNT(CASE WHEN ft.valuenum BETWEEN 0.01 AND 0.03 THEN 1 END) AS borderline_count,
  COUNT(CASE WHEN ft.valuenum > 0.03 THEN 1 END) AS elevated_count
FROM
  first_troponin ft
WHERE
  ft.rn = 1  -- Only first measurement per admission;