WITH NadirCreatininePerStay AS (
  -- First, find the nadir (minimum) serum creatinine for each hospital admission for all male patients.
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON le.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND le.itemid = 50912 -- 50912 is the itemid for Creatinine in labevents
    AND le.valuenum IS NOT NULL -- Ensure we only consider numeric, non-null values
    AND le.valuenum > 0 -- Creatinine cannot be zero or negative; this removes erroneous values
  GROUP BY
    le.hadm_id
)
-- Now, calculate the interquartile range (75th percentile - 25th percentile) of these nadir values.
SELECT
  APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(75)] - APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(25)] AS interquartile_range_of_nadir_creatinine
FROM
  NadirCreatininePerStay;