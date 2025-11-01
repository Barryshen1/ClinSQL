WITH male_52_62 AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    male_52_62 m
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON m.subject_id = a.subject_id
),

valve_procs AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code
      AND pr.icd_version = dp.icd_version
    JOIN admissions_cohort ac
      ON pr.hadm_id = ac.hadm_id
  WHERE
    LOWER(dp.long_title) LIKE '%valve repair%'
    OR LOWER(dp.long_title) LIKE '%valve replace%'
),

proc_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_valve_procs
  FROM
    valve_procs
  GROUP BY
    hadm_id
),

iqr_calc AS (
  SELECT
    -- APPROX_QUANTILES returns an array of length N+1 for N=100 -> 101 entries [0th..100th percentile]
    APPROX_QUANTILES(num_valve_procs, 100) AS quantiles
  FROM
    proc_counts
)

SELECT
  -- 25th percentile is at index 25, 75th percentile at index 75
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS interquartile_range
FROM
  iqr_calc;