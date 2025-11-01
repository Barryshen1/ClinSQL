WITH
-- Get male patients aged 79-89
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
),

-- Get admissions with ACS (using ICD-9/10 codes for AMI or unstable angina)
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- ICD-9 codes for ACS
      (d.icd_version = 9 AND d.icd_code LIKE '410.%') OR
      (d.icd_version = 9 AND d.icd_code = '411.1') OR
      -- ICD-10 codes for ACS
      (d.icd_version = 10 AND d.icd_code LIKE 'I21.%') OR
      (d.icd_version = 10 AND d.icd_code = 'I20.0')
    )
),

-- Get the first troponin T result for each admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN
    acs_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
)

-- Categorize troponin levels and count admissions
SELECT
  CASE
    WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
    WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN valuenum > 0.1 THEN 'Elevated (>0.1)'
  END AS troponin_category,
  COUNT(DISTINCT hadm_id) AS admission_count
FROM
  first_troponin
WHERE
  rn = 1  -- Only the first troponin result per admission
GROUP BY
  troponin_category
ORDER BY
  admission_count DESC;