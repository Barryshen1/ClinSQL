WITH FirstHeartRates AS (
  -- This CTE finds the first recorded heart rate for every ICU stay.
  SELECT
    ce.stay_id,
    ce.valuenum,
    -- Assign a row number to each heart rate measurement for a stay, ordered by time.
    ROW_NUMBER() OVER(PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) as rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.itemid IN (
        220045, -- Heart Rate
        211     -- Heart Rate
    )
    AND ce.valuenum IS NOT NULL -- Ensure the value is a number
    AND ce.valuenum > 0 -- Exclude clinically implausible values
)
-- Main query to select the patient cohort and find the minimum first heart rate.
SELECT
  MIN(fhr.valuenum) AS min_first_heart_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  ON p.subject_id = icu.subject_id
INNER JOIN
  FirstHeartRates AS fhr
  ON icu.stay_id = fhr.stay_id
WHERE
  p.gender = 'F' -- Filter for female patients
  -- Calculate age at ICU admission and filter for the 38-48 range.
  AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48
  AND fhr.rn = 1; -- Select only the first recorded heart rate for each stay;