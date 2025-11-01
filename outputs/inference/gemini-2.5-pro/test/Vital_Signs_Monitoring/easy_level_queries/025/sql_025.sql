WITH patient_cohort AS (
  -- First, select the specific patient demographic
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
), mean_rr_per_stay AS (
  -- Next, calculate the average respiratory rate for each ICU stay of the selected patients
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    -- Join to icustays to link events to patients
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.stay_id = icu.stay_id
    -- Ensure the stay belongs to a patient in our cohort
  INNER JOIN
    patient_cohort AS pc
    ON icu.subject_id = pc.subject_id
  WHERE
    -- Filter for common respiratory rate itemids
    ce.itemid IN (
      220210, -- Respiratory Rate
      224690, -- Respiratory Rate (Total)
      618 -- Respiratory Rate (from MetaVision)
    )
    -- Filter out null or non-physiological values
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
  GROUP BY
    ce.stay_id
)
-- Finally, calculate the 75th percentile of these per-stay averages
SELECT
  APPROX_QUANTILES(avg_respiratory_rate, 100)[OFFSET(75)] AS p75_mean_respiratory_rate
FROM
  mean_rr_per_stay;