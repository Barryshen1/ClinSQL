WITH
  cohort_los AS (
    SELECT
      -- Categorize the outcome based on discharge location and expire flag
      CASE
        WHEN adm.hospital_expire_flag = 1
        THEN 'In-Hospital Death'
        WHEN adm.discharge_location = 'HOSPICE'
        THEN 'Hospice'
        WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
        ELSE NULL
      END AS outcome_category,
      -- Calculate length of stay in fractional days for precision
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      -- Filter for male patients aged 80-90
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 80 AND 90
      -- Filter for non-emergency admissions
      AND adm.admission_type NOT IN ('EW EMER.', 'DIRECT EMER.', 'AMBULANCE', 'URGENT')
  )
SELECT
  outcome_category,
  AVG(los_days) AS mean_los,
  -- Use APPROX_QUANTILES to calculate distribution percentiles
  APPROX_QUANTILES(los_days, 100) [OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100) [OFFSET(90)] AS p90_los,
  -- Calculate the percentage of stays with LOS <= 14 days
  COUNTIF(los_days <= 14) * 100.0 / COUNT(los_days) AS percent_los_lte_14_days
FROM
  cohort_los
WHERE
  -- Exclude admissions that do not match the requested outcomes and have a valid LOS
  outcome_category IS NOT NULL
  AND los_days IS NOT NULL
GROUP BY
  outcome_category
ORDER BY
  outcome_category;