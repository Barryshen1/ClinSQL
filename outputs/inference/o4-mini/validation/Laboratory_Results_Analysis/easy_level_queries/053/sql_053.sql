WITH stroke_admissions AS (
  -- Identify admissions of 82-year-old female patients with ischemic stroke
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.subject_id = dx.subject_id
      AND a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON dx.icd_code = ddi.icd_code
      AND dx.icd_version = ddi.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 82
    AND LOWER(ddi.long_title) LIKE '%ischemic stroke%'
),
glucose_labs AS (
  -- Extract serum glucose lab values (itemid=50931) in first 24h of admission
  SELECT
    sa.subject_id,
    sa.hadm_id,
    le.valuenum AS glucose_mg_dl
  FROM
    stroke_admissions sa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON sa.subject_id = le.subject_id
      AND sa.hadm_id = le.hadm_id
  WHERE
    le.itemid = 50931
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND le.charttime BETWEEN sa.admittime
                        AND TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
)
-- Compute the 75th percentile of the admission serum glucose values
SELECT
  APPROX_QUANTILES(glucose_mg_dl, 100)[OFFSET(75)] AS p75_serum_glucose_mg_dl
FROM
  glucose_labs;