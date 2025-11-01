WITH patient_stays AS (
  -- Step 1: Identify ICU stays for male patients aged 35-45
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 35 AND 45
),
max_rr_per_stay AS (
  -- Step 2: For each of those stays, find the maximum respiratory rate recorded
  SELECT
    ps.stay_id,
    MAX(ce.valuenum) AS max_respiratory_rate
  FROM
    patient_stays AS ps
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ps.stay_id = ce.stay_id
  WHERE
    -- itemid for 'Respiratory Rate' and 'Respiratory Rate (Total)'
    ce.itemid IN (220210, 224690)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Basic data cleaning
  GROUP BY
    ps.stay_id
)
-- Step 3: Find the minimum value among all the maximum respiratory rates
SELECT
  MIN(max_respiratory_rate) AS min_of_max_respiratory_rate
FROM
  max_rr_per_stay;