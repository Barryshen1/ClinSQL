WITH cohort AS (
  SELECT
    adm.hadm_id,
    p.gender,
    adm.admission_location,
    adm.hospital_expire_flag,
    -- Calculate age at the time of admission
    (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    -- Calculate LOS in days using hours for precision.
    -- Set to NULL if dischtime is not after admittime.
    CASE
        WHEN adm.dischtime > adm.admittime
        THEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0
        ELSE NULL
    END AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
),
filtered_cohort AS (
  SELECT
    -- Create a descriptive mortality status for stratification
    CASE
        WHEN hospital_expire_flag = 1 THEN 'Died in hospital'
        ELSE 'Discharged alive'
    END AS mortality_status,
    los_days
  FROM
    cohort
  WHERE
    -- Apply all filters to define the final patient cohort
    gender = 'M'
    AND age_at_admission BETWEEN 41 AND 51
    AND admission_location = 'EMERGENCY ROOM'
    -- Exclude rows with an invalid LOS calculation
    AND los_days IS NOT NULL
)
SELECT
  mortality_status,
  COUNT(los_days) AS number_of_admissions,
  -- Calculate mean LOS and round for cleaner output
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- Calculate median (50th percentile) LOS using APPROX_QUANTILES
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  -- Calculate the percentage of stays that are 5 days or shorter
  ROUND(AVG(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100, 2) AS percent_los_le_5_days
FROM
  filtered_cohort
GROUP BY
  mortality_status
ORDER BY
  mortality_status;