WITH non_icu_admissions AS (
  -- First, select the cohort of hospital admissions for female patients aged 75-85
  -- who were never admitted to an ICU during their stay.
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND icu.stay_id IS NULL  -- This is the key filter for "non-ICU"
),
outcomes AS (
  -- Next, for this cohort, calculate length of stay and stratify by outcome.
  SELECT
    hadm_id,
    -- Calculate LOS in fractional days for accurate statistics
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    -- Create the outcome categories based on the question's criteria
    CASE
      WHEN hospital_expire_flag = 1
        THEN 'In-Hospital Mortality'
      WHEN discharge_location = 'HOSPICE'
        THEN 'Discharged to Hospice'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Discharged Home'
      ELSE NULL
    END AS outcome_category
  FROM
    non_icu_admissions
)
-- Finally, aggregate the results to get the mean and standard deviation for each outcome category.
SELECT
  outcome_category,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS stddev_los_days
FROM
  outcomes
WHERE
  outcome_category IS NOT NULL -- Exclude admissions that do not match the specified outcomes
GROUP BY
  outcome_category
ORDER BY
  outcome_category;