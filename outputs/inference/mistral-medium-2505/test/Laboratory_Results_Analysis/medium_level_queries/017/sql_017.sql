WITH
-- Get male patients aged 47-57
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 47 AND 57
),

-- Get admissions with ischemic heart disease (ICD-10: I20-I25)
ischemic_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
    AND di.icd_code BETWEEN 'I20' AND 'I25'  -- Ischemic heart disease codes
),

-- Get first Troponin-T > 0.014 ng/mL per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM ischemic_admissions)
    AND dl.label = 'Troponin T'
    AND l.valuenum > 0.014
    AND l.valueuom = 'ng/mL'
)

-- Calculate median and IQR
SELECT
  PERCENTILE_CONT(valuenum, 0.5) OVER() AS median_troponin,
  PERCENTILE_CONT(valuenum, 0.25) OVER() AS q1,
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS q3,
  PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr
FROM
  first_troponin
WHERE
  rn = 1  -- Only the first Troponin-T per admission
LIMIT 1;