WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    -- Calculate LOS in days with fractional precision for accuracy
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    -- 1. Filter for elective admissions
    a.admission_type = 'ELECTIVE'
    -- 2. Filter for female patients
    AND p.gender = 'F'
    -- 3. Calculate age at admission and filter for the 44-54 range
    AND (
      p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 44 AND 54
    -- Ensure LOS can be calculated
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT
  -- Stratify by discharged alive vs. in-hospital mortality
  CASE
    WHEN hospital_expire_flag = 1
    THEN 'In-Hospital Mortality'
    ELSE 'Discharged Alive'
  END AS mortality_status,
  -- Calculate distribution statistics
  COUNT(hadm_id) AS n,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days
FROM
  cohort
GROUP BY
  mortality_status
ORDER BY
  mortality_status DESC;