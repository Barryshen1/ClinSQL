WITH pneumonia_hadm AS (
  -- admissions that have any diagnosis whose long_title mentions "pneumonia"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%pneumonia%'
),

cohort_los AS (
  -- compute LOS (days) for each admission for female patients aged 49-59 with pneumonia diagnosis
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_hadm ph
    ON a.hadm_id = ph.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)

SELECT
  -- approximate 25th percentile (1% resolution via 100 quantiles, offset 25)
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  COUNT(*) AS n_admissions
FROM cohort_los;