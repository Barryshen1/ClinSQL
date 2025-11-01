WITH cohort_los AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate LOS in fractional days for higher precision in stats
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    -- Ensure dischtime is present and after admittime for a valid LOS
    AND adm.dischtime IS NOT NULL
    AND adm.dischtime >= adm.admittime
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1
    THEN 'In-Hospital Death'
    ELSE 'Discharged Alive'
  END AS discharge_status,
  AVG(los_days) AS mean_los,
  -- APPROX_QUANTILES is efficient for calculating multiple percentiles
  APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los_p50,
  APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(los_days, 100) [OFFSET(90)] AS los_p90,
  -- Calculate the percentile rank of a 5-day LOS.
  -- This is the proportion of stays with LOS <= 5 days.
  SAFE_DIVIDE(COUNTIF(los_days <= 5), COUNT(hadm_id)) AS percentile_rank_of_5_day_los
FROM
  cohort_los
GROUP BY
  discharge_status
ORDER BY
  discharge_status DESC;