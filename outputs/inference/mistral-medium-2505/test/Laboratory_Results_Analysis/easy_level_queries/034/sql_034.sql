WITH
-- Get male patients aged 65
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age = 65
),

-- Get heart failure hospitalizations (ICD-10 codes starting with I50)
heart_failure_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
    AND d.icd_code LIKE 'I50%'
),

-- Get serum sodium measurements (LOINC code 2951-2)
serum_sodium AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    dl.loinc = '2951-2'
    AND l.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
),

-- Get the first serum sodium measurement per admission
first_sodium_per_admission AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.valuenum,
    ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.charttime) AS rn
  FROM
    serum_sodium s
)

-- Find the minimum admission serum sodium
SELECT
  MIN(valuenum) AS min_admission_serum_sodium
FROM
  first_sodium_per_admission
WHERE
  rn = 1  -- Only the first measurement per admission
;