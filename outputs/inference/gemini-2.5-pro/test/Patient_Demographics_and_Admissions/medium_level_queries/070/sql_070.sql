WITH cohort_los AS (
  SELECT
    hadm_id,
    -- Calculate LOS in fractional days for more precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge outcome, prioritizing death flag
    CASE
      WHEN adm.hospital_expire_flag = 1
      THEN 'In-hospital Death'
      WHEN adm.discharge_location LIKE '%HOSPICE%'
      THEN 'Discharged to Hospice'
      WHEN adm.discharge_location LIKE 'HOME%' -- Catches 'HOME' and 'HOME HEALTH CARE'
      THEN 'Discharged Home'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    adm.admission_location = 'EMERGENCY ROOM'
    AND pat.gender = 'M'
    -- Calculate age at admission for precise filtering
    AND (
      (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age
    ) BETWEEN 57 AND 67
)
SELECT
  discharge_category,
  COUNT(hadm_id) AS number_of_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- Use APPROX_QUANTILES to get median (50th), 75th, and 90th percentiles
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  -- Calculate the proportion of stays <= 10 days to find its percentile rank
  ROUND(SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(los_days)) * 100, 2) AS percentile_rank_of_10_day_los
FROM
  cohort_los
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;