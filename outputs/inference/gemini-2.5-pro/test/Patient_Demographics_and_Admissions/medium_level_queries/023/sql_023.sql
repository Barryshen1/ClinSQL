WITH
  -- Step 1: Define the cohort of male inpatients, aged 41-51, admitted from the ED.
  cohort AS (
    SELECT
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
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 41 AND 51
      AND adm.admission_location = 'EMERGENCY ROOM'
  ),
  -- Step 2: Calculate Length of Stay (LOS) and classify discharge type.
  los_data AS (
    SELECT
      -- LOS in fractional days for greater precision.
      TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
      -- Categorize discharge location based on the question's requirements.
      CASE
        WHEN hospital_expire_flag = 1
          THEN 'In-Hospital Death'
        WHEN discharge_location LIKE 'HOME%'
          THEN 'Home'
        WHEN discharge_location IS NOT NULL
          THEN 'Facility'
        ELSE 'Other/Unknown'
      END AS discharge_category
    FROM
      cohort
    -- Ensure LOS is calculable.
    WHERE
      dischtime IS NOT NULL AND admittime IS NOT NULL
  ),
  -- Step 3: Calculate the percentile rank of a 10-day LOS across the entire cohort.
  percentile_rank_calc AS (
    SELECT
      -- Manually calculate percentile rank: (count of values < 10) / (total count - 1)
      SAFE_DIVIDE(COUNTIF(los_days < 10), COUNT(los_days) - 1) AS percentile_rank_of_10_day_los
    FROM
      los_data
  )
-- Step 4: Aggregate results by discharge category and join with the percentile rank.
SELECT
  los_data.discharge_category,
  COUNT(*) AS number_of_admissions,
  -- Calculate proportion with LOS >= 7 days
  AVG(
    CASE
      WHEN los_data.los_days >= 7 THEN 1.0
      ELSE 0.0
    END
  ) AS proportion_los_ge_7_days,
  pr.percentile_rank_of_10_day_los
FROM
  los_data
CROSS JOIN
  percentile_rank_calc AS pr
-- Filter to only include the categories requested.
WHERE
  los_data.discharge_category IN ('Home', 'Facility', 'In-Hospital Death')
GROUP BY
  los_data.discharge_category,
  pr.percentile_rank_of_10_day_los
ORDER BY
  los_data.discharge_category;