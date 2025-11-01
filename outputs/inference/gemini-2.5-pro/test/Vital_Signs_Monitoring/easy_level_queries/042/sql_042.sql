WITH MaxRespRatePerStay AS (
  -- First, find the maximum respiratory rate for each ICU stay for the target patient cohort
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS max_resp_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for female patients aged 63-73
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    -- 2. Filter for respiratory rate measurements
    AND ce.itemid IN (
      220210, -- Respiratory Rate
      224690  -- Respiratory Rate (Total)
    )
    -- 3. Filter for valid numeric values
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY
    icu.stay_id
)
-- Finally, calculate the standard deviation of the collected maximum respiratory rates
SELECT
  STDDEV(max_resp_rate) AS sd_of_max_respiratory_rate
FROM
  MaxRespRatePerStay;