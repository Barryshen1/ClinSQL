WITH first_map AS (
  SELECT
    ce.valuenum,
    -- Assign a row number to each MAP measurement within an ICU stay, ordered by time
    ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for male patients aged 55-65
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    -- 2. Filter for MAP itemids (both invasive and non-invasive)
    AND ce.itemid IN (
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    -- 3. Ensure the value is a valid number
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
)
-- 4. Calculate the standard deviation of the first MAP measurement for each stay
SELECT
  STDDEV(valuenum) AS sd_of_first_map
FROM
  first_map
WHERE
  rn = 1;