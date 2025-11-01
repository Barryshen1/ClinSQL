WITH relevant_stays AS (
  -- First, select the ICU stays for male patients aged 85-95 at admission
  SELECT
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at the time of ICU admission and filter
    AND (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 85 AND 95
),

mean_map_per_stay AS (
  -- Next, calculate the mean arterial pressure during the first 24 hours for each relevant stay
  SELECT
    rs.stay_id,
    AVG(ce.valuenum) AS first_24hr_mean_map
  FROM
    relevant_stays AS rs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON rs.stay_id = ce.stay_id
  WHERE
    -- Filter for Mean Arterial Pressure itemids (both invasive and non-invasive)
    ce.itemid IN (
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    -- Filter for measurements taken within the first 24 hours of the ICU stay
    AND ce.charttime >= rs.intime
    AND ce.charttime <= DATETIME_ADD(rs.intime, INTERVAL 24 HOUR)
    -- Ensure the value is a plausible number
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY
    rs.stay_id
)

-- Finally, calculate the standard deviation of the per-stay average MAPs
SELECT
  STDDEV(first_24hr_mean_map) AS stddev_of_first_24hr_mean_map
FROM
  mean_map_per_stay;