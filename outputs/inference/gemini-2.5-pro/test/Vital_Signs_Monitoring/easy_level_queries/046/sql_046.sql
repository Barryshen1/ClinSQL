WITH cohort_stays AS (
  -- First, select the ICU stays for the patient cohort of interest
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
first_spo2 AS (
  -- Next, find the first recorded SpO2 value for each of these ICU stays
  SELECT
    cs.stay_id,
    ce.valuenum,
    -- Assign a row number to each SpO2 measurement within a stay, ordered by time
    ROW_NUMBER() OVER (PARTITION BY cs.stay_id ORDER BY ce.charttime) AS rn
  FROM
    cohort_stays AS cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220277 -- O2 saturation pulseoxymetry
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum <= 100 -- Plausible values for SpO2
)
-- Finally, calculate the IQR from the first SpO2 values
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS spo2_p75,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS spo2_p25,
  (APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]) AS spo2_iqr
FROM
  first_spo2
WHERE
  rn = 1 -- Filter for only the first measurement per stay;