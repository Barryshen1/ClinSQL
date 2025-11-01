WITH patient_cohort AS (
  -- Step 1: Identify males aged 51-61 who had an ICU stay
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_rr AS (
  -- Step 2 & 3: Find the first recorded respiratory rate for each patient in the cohort
  SELECT
    ce.subject_id,
    ce.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    patient_cohort AS pc
    ON ce.subject_id = pc.subject_id
  WHERE
    ce.itemid IN (
      220210, -- Respiratory Rate
      224690  -- Respiratory Rate (Total)
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Exclude erroneous values
)
-- Step 4: Calculate the standard deviation of these first measurements
SELECT
  STDDEV(valuenum) AS sd_first_respiratory_rate
FROM
  first_rr
WHERE
  rn = 1;