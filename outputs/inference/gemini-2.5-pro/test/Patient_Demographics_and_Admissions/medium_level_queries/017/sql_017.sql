WITH admission_cohort AS (
  -- First, select the unique hospital admissions that match the cohort criteria
  SELECT DISTINCT
    adm.hadm_id,
    -- Calculate LOS in fractional days for higher precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge destination based on flags and location descriptions
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM CARE',
        'HOSPICE',
        'LONG TERM CARE HOSPITAL'
      )
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Use an INNER JOIN to ensure that the admission has at least one ICU stay
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at admission and filter
    AND (
      DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age
    ) BETWEEN 38 AND 48
    -- Ensure dischtime is after admittime to avoid negative LOS
    AND adm.dischtime > adm.admittime
)
-- Aggregate the LOS data by the defined discharge groups
SELECT
  discharge_group,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days
FROM
  admission_cohort
WHERE
  discharge_group IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY
  discharge_group
ORDER BY
  -- Custom sort order for readability
  CASE
    WHEN discharge_group = 'Home' THEN 1
    WHEN discharge_group = 'Facility' THEN 2
    WHEN discharge_group = 'In-hospital Death' THEN 3
  END;