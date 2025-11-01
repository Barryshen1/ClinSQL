WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.admission_location,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND adm.dischtime IS NOT NULL
),
quantiles AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(los_days, 100) AS los_percentiles
  FROM cohort
  GROUP BY hospital_expire_flag
)
SELECT
  CASE hospital_expire_flag WHEN 1 THEN 'In-hospital death' ELSE 'Survived' END AS outcome,
  num_admissions,
  ROUND(los_percentiles[OFFSET(50)], 2) AS p50_los,
  ROUND(los_percentiles[OFFSET(75)], 2) AS p75_los,
  ROUND(los_percentiles[OFFSET(90)], 2) AS p90_los,
  ROUND(los_percentiles[OFFSET(95)], 2) AS p95_los
FROM quantiles
ORDER BY hospital_expire_flag;

-- Part 2: Percentile rank of a 10-day LOS in the same cohort
WITH cohort AS (
  SELECT
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND adm.dischtime IS NOT NULL
)
SELECT
  ROUND(100.0 * COUNTIF(los_days <= 10) / COUNT(*), 2) AS percentile_rank_10d
FROM cohort;