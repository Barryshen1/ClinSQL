WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND d.seq_num = 1  -- primary diagnosis
    AND dd.icd_version = 10  -- ICD-10
    AND (dd.icd_code IN ('A40', 'A41', 'R65.2') 
         OR dd.long_title LIKE '%sepsis%'
         OR dd.long_title LIKE '%septic shock%')
    AND a.dischtime IS NOT NULL  -- exclude admissions without discharge time
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 40 AND 50
)
SELECT
  los_quantiles[OFFSET(25)] AS q1,
  los_quantiles[OFFSET(75)] AS q3,
  los_quantiles[OFFSET(75)] - los_quantiles[OFFSET(25)] AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 100) AS los_quantiles
  FROM filtered_admissions
);