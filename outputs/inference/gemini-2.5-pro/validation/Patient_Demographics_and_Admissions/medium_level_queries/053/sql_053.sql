WITH cohort_los AS (
  SELECT
    adm.hadm_id,
    -- Create outcome categories based on discharge status.
    -- Prioritize death flag over discharge location.
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN adm.discharge_location = 'HOME'
        THEN 'Discharged Home'
      WHEN adm.discharge_location = 'HOSPICE'
        THEN 'Hospice'
      ELSE NULL
    END AS outcome_category,
    -- Calculate length of stay in days with fractional precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND adm.admission_type = 'EMERGENCY'
)
SELECT
  outcome_category,
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate median and IQR using approximate quantiles for efficiency
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  (APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]) AS iqr_los_days
FROM
  cohort_los
WHERE
  -- Only include admissions that fall into one of our defined outcome categories
  outcome_category IS NOT NULL
GROUP BY
  outcome_category
ORDER BY
  outcome_category;