WITH
-- Get female patients aged 88-98
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),

-- Get ACS admissions (ICD-10 codes I20-I25)
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p
    ON a.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'I2%'
    AND d.icd_version = 10
),

-- Get first Troponin T measurement per admission (>0.01 ng/mL)
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  JOIN
    acs_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    di.label = 'Troponin T'
    AND l.valuenum > 0.01
    AND l.valueuom = 'ng/mL'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) = 1
)

-- Calculate median and IQR
SELECT
  PERCENTILE_CONT(troponin_value, 0.5) OVER() AS median_troponin,
  PERCENTILE_CONT(troponin_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() - PERCENTILE_CONT(troponin_value, 0.25) OVER() AS iqr
FROM
  first_troponin
LIMIT 1;