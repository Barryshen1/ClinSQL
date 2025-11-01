WITH
  -- Step 1: Define the cohort of interest and calculate LOS for each admission.
  cohort_los AS (
    SELECT
      adm.hospital_expire_flag,
      -- Calculate LOS in days with fractional precision.
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      -- Filter for male patients.
      pat.gender = 'M'
      -- Filter for age at admission between 57 and 67.
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 57 AND 67
      -- Filter for non-elective admissions.
      AND adm.admission_type IN (
        'EMERGENCY', 'URGENT', 'DIRECT EMER.', 'DIRECT URGENT', 'EW EMER.'
      )
      -- Filter for patients who were on a 'MED' service at any point.
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.services` AS s
        WHERE
          s.hadm_id = adm.hadm_id AND s.curr_service = 'MED'
      )
      -- Ensure LOS can be calculated.
      AND adm.dischtime IS NOT NULL
      AND adm.admittime IS NOT NULL
  ),
  -- Step 2: Calculate aggregate LOS statistics, grouped by survival status.
  los_stats AS (
    SELECT
      hospital_expire_flag,
      CASE
        WHEN hospital_expire_flag = 1
        THEN 'In-Hospital Death'
        ELSE 'Discharged Alive'
      END AS outcome,
      AVG(los_days) AS mean_los,
      -- APPROX_QUANTILES is efficient for calculating multiple percentiles.
      APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los_p50,
      APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS p75_los,
      APPROX_QUANTILES(los_days, 100) [OFFSET(90)] AS p90_los
    FROM
      cohort_los
    GROUP BY
      hospital_expire_flag
  ),
  -- Step 3: Calculate the percentile rank of a 5-day stay for the entire cohort.
  percentile_rank_stat AS (
    SELECT
      -- This calculates the proportion of stays <= 5 days (Empirical CDF).
      COUNTIF(los_days <= 5) / COUNT(los_days) AS percentile_rank_of_5_day_stay
    FROM
      cohort_los
  )
-- Final Step: Combine the grouped statistics with the overall percentile rank.
SELECT
  ls.outcome,
  ls.mean_los,
  ls.median_los_p50,
  ls.p75_los,
  ls.p90_los,
  prs.percentile_rank_of_5_day_stay
FROM
  los_stats AS ls
CROSS JOIN
  percentile_rank_stat AS prs
ORDER BY
  ls.hospital_expire_flag;