WITH per_stay_mean_hr AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    -- 220045 is the itemid for 'Heart Rate'
    AND ce.itemid = 220045
    -- Data quality filters for plausible heart rates
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
  GROUP BY
    icu.stay_id
)

SELECT
  -- APPROX_QUANTILES with 2 returns a 3-element array: [min, median, max]
  -- We select the element at offset 1 for the median.
  APPROX_QUANTILES(mean_hr, 2)[OFFSET(1)] AS median_of_mean_heart_rate
FROM
  per_stay_mean_hr;