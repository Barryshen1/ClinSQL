WITH pneumonia_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
    AND LOWER(did.long_title) LIKE '%pneumonia%'
)
SELECT
  quantiles[OFFSET(1)] AS p25_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM pneumonia_admissions
) t;