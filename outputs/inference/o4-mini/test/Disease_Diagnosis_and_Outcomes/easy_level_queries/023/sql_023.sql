WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
      AND d.seq_num    = 1  -- primary diagnosis
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
      ON d.icd_code    = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(diag.long_title) LIKE '%pneumonia%'
)
SELECT
  -- APPROX_QUANTILES with 2 buckets returns [min, median, max], so offset 1 is the median
  (APPROX_QUANTILES(los_days, 2))[OFFSET(1)] AS median_los_days
FROM
  cohort;