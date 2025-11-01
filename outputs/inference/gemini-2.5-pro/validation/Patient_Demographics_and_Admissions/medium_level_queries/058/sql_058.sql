WITH cohort AS (
  SELECT
    adm.hadm_id,
    -- Calculate LOS in fractional days for higher precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge outcome. Check for mortality first.
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-Hospital Mortality'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Home'
      WHEN adm.discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP', 'LONG TERM CARE HOSPITAL')
        THEN 'SNF/Rehab/LTACH'
      ELSE NULL -- Other outcomes are not part of the analysis
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- 1. Filter for male patients
    pat.gender = 'M'
    -- 2. Filter for the specified age range
    AND pat.anchor_age BETWEEN 37 AND 47
    -- 3. Filter for patients transferred from another facility
    AND adm.admission_location IN (
      'TRANSFER FROM HOSPITAL',
      'TRANSFER FROM SKILLED NURSING FACILITY',
      'TRANSFER FROM OTHER HEALTH CARE FACILITY'
    )
    -- Ensure dischtime exists to allow for LOS calculation
    AND adm.dischtime IS NOT NULL
)
-- Final aggregation and calculation of metrics
SELECT
  discharge_category,
  COUNT(hadm_id) AS n,
  AVG(los_days) AS mean_los,
  -- Use APPROX_QUANTILES to extract multiple percentile values efficiently
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_los,
  -- Calculate the percentile rank of a 5-day stay (i.e., % of stays <= 5 days)
  100 * COUNTIF(los_days <= 5) / COUNT(hadm_id) AS percentile_rank_of_5_day_los
FROM
  cohort
WHERE
  -- Exclude admissions that do not match the specified discharge categories
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  -- Order for clear presentation
  discharge_category;