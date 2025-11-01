WITH
-- Get female patients aged 68-78
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 68 AND 78
),

-- Get ACS admissions (using common ACS ICD-10 codes)
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND d.icd_code IN (
      'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
      'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
    )
    AND d.icd_version = 10
),

-- Get Troponin I itemid (using label only)
troponin_item AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    label LIKE '%Troponin I%'
),

-- Get first Troponin I measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    troponin_item t ON l.itemid = t.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL' -- Ensure consistent units
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(valuenum) AS mean_troponin,
  STDDEV(valuenum) AS sd_troponin,
  MIN(valuenum) AS min_troponin,
  MAX(valuenum) AS max_troponin
FROM
  first_troponin
WHERE
  rn = 1 -- Only first measurement per admission
  AND valuenum > 0.04 -- Filter for elevated Troponin I;