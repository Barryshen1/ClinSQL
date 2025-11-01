WITH relevant_stays AS (
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
  WHERE
    -- Filter for female patients aged 73 to 83
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    -- Filter for stays in a step-down/Intermediate Medical Care (IMC) unit.
    -- We use first_careunit as a proxy for the type of stay.
    AND icu.first_careunit = 'Intermediate Medical Care'
)
-- Step 2: For the selected stays, find all MAP measurements and calculate the average per stay.
SELECT
  rs.stay_id,
  AVG(ce.valuenum) AS avg_mean_arterial_pressure
FROM
  relevant_stays AS rs
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON rs.stay_id = ce.stay_id
WHERE
  -- Filter for itemids corresponding to Mean Arterial Pressure (invasive and non-invasive)
  ce.itemid IN (
    220052, -- Arterial Blood Pressure mean
    220181, -- Non Invasive Blood Pressure mean
    225312  -- ART BP mean
  )
  -- Filter for valid, plausible numeric values to ensure a correct average
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
GROUP BY
  rs.stay_id
ORDER BY
  rs.stay_id;