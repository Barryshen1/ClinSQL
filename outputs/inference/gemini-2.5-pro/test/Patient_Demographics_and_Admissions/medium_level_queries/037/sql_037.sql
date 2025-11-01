WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    -- Filter for male patients
    p.gender = 'M'
    -- Filter for non-emergency admissions
    AND a.admission_type <> 'EMERGENCY'
    -- Calculate and filter for age at admission between 52 and 62 years
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
    -- Ensure dischtime is available to calculate a valid LOS
    AND a.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged Alive'
    WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
  END AS outcome,
  -- Calculate LOS percentiles using approximate quantiles for efficiency
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_los_days,
  -- Calculate the percentile rank for a 7-day LOS.
  -- This represents the proportion of stays with LOS <= 7 days.
  SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(hadm_id)) * 100 AS percentile_rank_of_7_days
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  outcome DESC;