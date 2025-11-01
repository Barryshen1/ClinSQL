WITH patient_cohort AS (
  -- First, select the subject_ids for male patients aged 90-100
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
prescription_durations AS (
  -- Next, find the relevant prescriptions for this cohort and calculate their duration
  SELECT
    -- Calculate the duration in whole days
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  INNER JOIN
    patient_cohort pc
    ON pres.subject_id = pc.subject_id
  WHERE
    -- Filter for spironolactone or eplerenone prescriptions, ignoring case
    (
      LOWER(pres.drug) LIKE '%spironolactone%'
      OR LOWER(pres.drug) LIKE '%eplerenone%'
    )
    -- Ensure we have valid start and stop times to calculate a duration
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime > pres.starttime -- Ensure a positive duration
)
-- Finally, calculate the median duration from the filtered set of prescriptions
SELECT
  -- APPROX_QUANTILES(..., 2)[OFFSET(1)] is the standard way to calculate median
  APPROX_QUANTILES(pd.duration_days, 2)[OFFSET(1)] AS median_prescription_duration_days
FROM
  prescription_durations AS pd;