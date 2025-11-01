WITH pneumonia_admissions AS (
  SELECT
    DISTINCT a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(diag.long_title) LIKE '%pneumonia%'
)
SELECT
  -- 25th percentile of length of stay in days
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days
FROM
  pneumonia_admissions;