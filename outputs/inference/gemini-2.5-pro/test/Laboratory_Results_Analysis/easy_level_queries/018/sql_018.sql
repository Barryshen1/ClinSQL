WITH first_day_ph AS (
  SELECT
    icu.stay_id,
    ce.valuenum,
    -- Assign a rank to each measurement within a stay, ordered by time.
    -- The first measurement will have measurement_rank = 1.
    ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY ce.charttime ASC) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for female patients.
    pat.gender = 'F'
    -- 2. Filter for Arterial pH, identified by its itemid.
    -- The label for itemid 223830 is 'PH (Arterial)'.
    AND ce.itemid = 223830
    -- 3. Filter for measurements taken within the first 24 hours of the ICU stay.
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- 4. Add a sanity check for plausible pH values.
    AND ce.valuenum BETWEEN 6.5 AND 8.5
)
-- 5. Calculate the median from the first measurement of each stay.
SELECT
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_arterial_ph_on_admission
FROM
  first_day_ph
WHERE
  measurement_rank = 1;