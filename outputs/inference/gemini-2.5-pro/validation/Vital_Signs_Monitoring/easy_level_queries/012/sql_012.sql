WITH MeanDBPPerStay AS (
  -- Step 1: Calculate the mean diastolic blood pressure for each qualifying ICU stay
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS avg_diastolic_bp
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- Filter for male patients aged 49-59
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    -- Filter for stays in step-down or intermediate care units
    AND (
      icu.first_careunit LIKE '%Intermediate%'
      OR icu.first_careunit LIKE '%Stepdown%'
      OR icu.last_careunit LIKE '%Intermediate%'
      OR icu.last_careunit LIKE '%Stepdown%'
    )
    -- Filter for diastolic blood pressure itemids
    AND ce.itemid IN (
      220051, -- Arterial Blood Pressure diastolic
      220180, -- Non Invasive Blood Pressure diastolic
      225310, -- ART BP Diastolic
      8368,   -- Arterial Blood Pressure diastolic (CareVue)
      224643, -- Manual Blood Pressure Diastolic Left
      224644, -- Manual Blood Pressure Diastolic Right
      227242  -- Manual Blood Pressure Diastolic R
    )
    -- Filter out erroneous values
    AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY
    icu.stay_id
)
-- Step 2: Calculate the IQR of the mean diastolic BPs calculated in the CTE
SELECT
  -- APPROX_QUANTILES returns an array of quantile values.
  -- [OFFSET(3)] is the 3rd quartile (75th percentile).
  -- [OFFSET(1)] is the 1st quartile (25th percentile).
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr_of_mean_diastolic_bp
FROM (
  SELECT
    APPROX_QUANTILES(avg_diastolic_bp, 4) AS quartiles
  FROM
    MeanDBPPerStay
);