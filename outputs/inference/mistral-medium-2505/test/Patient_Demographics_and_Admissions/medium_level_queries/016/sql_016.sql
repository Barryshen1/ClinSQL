WITH
-- Get male patients aged 44-54 with general ward stays
general_ward_stays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN (
    -- Identify general ward stays (non-ICU)
    SELECT DISTINCT
      subject_id,
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.transfers`
    WHERE
      careunit = 'General Ward'
  ) t ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.discharge_location IN ('Home', 'Hospice', 'Death')
    AND a.dischtime IS NOT NULL
),

-- Calculate percentiles for each discharge location
los_percentiles AS (
  SELECT
    discharge_location,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p75,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p90,
    APPROX_QUANTILES(los_days, 4)[OFFSET(4)] AS p95
  FROM
    general_ward_stays
  GROUP BY
    discharge_location
),

-- Calculate percentile rank for a 7-day stay in each discharge location
los_rank AS (
  SELECT
    discharge_location,
    PERCENT_RANK() OVER (PARTITION BY discharge_location ORDER BY los_days) AS percentile_rank
  FROM
    general_ward_stays
  WHERE
    los_days = 7
)

-- Final output
SELECT
  lp.discharge_location,
  lp.p50,
  lp.p75,
  lp.p90,
  lp.p95,
  lr.percentile_rank AS percentile_rank_for_7day_stay
FROM
  los_percentiles lp
LEFT JOIN
  los_rank lr ON lp.discharge_location = lr.discharge_location
ORDER BY
  lp.discharge_location;