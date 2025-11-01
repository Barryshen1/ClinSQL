WITH cohort_los AS (
  SELECT
    -- Categorize discharge outcome based on destination and death flag
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOME IV PROVIDER') THEN 'Home'
      -- Grouping various facility types together
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM ACUTE CARE',
        'HOSPICE',
        'OTHER FACILITY',
        'ACUTE HOSPITAL' -- Transfer to another acute care hospital is a form of facility discharge
      ) THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome,

    -- Calculate length of stay in fractional days for more accuracy
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- 1. Filter for female patients
    pat.gender = 'F'
    -- 2. Filter for patients aged 43-53 (inclusive)
    AND pat.anchor_age BETWEEN 43 AND 53
    -- 3. Filter for admissions originating from the Emergency Room
    AND adm.admission_location = 'EMERGENCY ROOM'
    -- 4. Ensure LOS can be calculated and is non-negative
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
    AND adm.dischtime > adm.admittime
)

-- Final aggregation to calculate statistics for each discharge outcome
SELECT
  discharge_outcome,
  -- Median (50th percentile) LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  -- Interquartile Range (IQR) = 75th percentile - 25th percentile
  (APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]) AS iqr_los_days,
  -- Percentile rank of a 14-day stay. This is the proportion of stays <= 14 days.
  -- Calculated as (count of stays <= 14 days) / (total count of stays) * 100
  COUNTIF(los_days <= 14) * 100.0 / COUNT(los_days) AS percentile_rank_of_14_day_los
FROM
  cohort_los
WHERE
  -- Only include the requested discharge outcomes
  discharge_outcome IN ('Home', 'Facility', 'Death')
GROUP BY
  discharge_outcome
ORDER BY
  -- Order results for consistent presentation
  discharge_outcome;