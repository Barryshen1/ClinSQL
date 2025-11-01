WITH
-- Get male patients aged 49-59
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),

-- Get admissions with AMI diagnosis
ami_admissions AS (
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
    AND di.icd_code LIKE 'I21.%' OR di.icd_code LIKE 'I22.%' -- AMI codes
),

-- Get first troponin T > 0.04 ng/mL per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    l.subject_id IN (SELECT subject_id FROM ami_admissions)
    AND l.hadm_id IN (SELECT hadm_id FROM ami_admissions)
    AND d.label = 'Troponin T' -- Verify itemid for Troponin T
    AND l.valuenum > 0.04
)

-- Calculate median and IQR
SELECT
  PERCENTILE_CONT(troponin_value, 0.5) OVER() AS median_troponin,
  PERCENTILE_CONT(troponin_value, 0.25) OVER() AS q1_troponin,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() AS q3_troponin,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() - PERCENTILE_CONT(troponin_value, 0.25) OVER() AS iqr_troponin
FROM
  first_troponin
WHERE
  rn = 1 -- Only the first troponin T per admission
LIMIT 1; -- Only need one row for the summary statistics;