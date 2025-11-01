WITH ugib_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Hospital length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
   AND d.seq_num    = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dd.long_title) LIKE '%upper gastrointestinal hemorrh%'
)
SELECT
  -- First quartile (25th percentile)
  quartiles[SAFE_OFFSET(1)] AS q1_los_days,
  -- Third quartile (75th percentile)
  quartiles[SAFE_OFFSET(3)] AS q3_los_days
FROM (
  SELECT
    -- Compute quartiles: returns [min, Q1, median, Q3, max]
    APPROX_QUANTILES(los_days, 4) AS quartiles
  FROM
    ugib_admissions
);