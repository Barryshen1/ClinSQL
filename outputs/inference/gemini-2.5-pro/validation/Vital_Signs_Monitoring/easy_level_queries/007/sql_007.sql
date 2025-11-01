WITH patient_cohort AS (
  -- Step 1: Identify female patients aged 73-83
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 73 AND 83
),
first_rr_measurements AS (
  -- Step 2: Find the first respiratory rate measurement for each hospital admission
  SELECT
    ce.valuenum,
    ROW_NUMBER() OVER(PARTITION BY ce.subject_id, ce.hadm_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    patient_cohort pc ON ce.subject_id = pc.subject_id
  WHERE
    ce.itemid = 220210 -- Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Filter out non-physiological values
)
-- Step 3: Calculate the standard deviation of the first recorded respiratory rates
SELECT
  STDDEV(valuenum) AS stddev_first_respiratory_rate
FROM
  first_rr_measurements
WHERE
  rn = 1;