WITH pneumonia_admissions AS (
  -- Step 1: admissions for 61-year-old males with pneumonia
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 61
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
creatinine_labs AS (
  -- Step 2: identify serum creatinine labs during those admissions
  SELECT
    pa.hadm_id,
    le.valuenum AS creat_val
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.hadm_id = le.hadm_id
     AND le.charttime BETWEEN pa.admittime AND pa.dischtime
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
  WHERE
    di.fluid = 'Blood'
    AND LOWER(di.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
),
nadir_per_admission AS (
  -- Step 3: compute nadir (minimum) creatinine per admission
  SELECT
    hadm_id,
    MIN(creat_val) AS nadir_creatinine
  FROM
    creatinine_labs
  GROUP BY
    hadm_id
)
-- Step 4: compute the IQR (25th and 75th percentiles) across all these nadirs
SELECT
  quantiles[OFFSET(1)] AS creatinine_p25,
  quantiles[OFFSET(3)] AS creatinine_p75
FROM (
  SELECT
    APPROX_QUANTILES(nadir_creatinine, 4) AS quantiles
  FROM
    nadir_per_admission
);