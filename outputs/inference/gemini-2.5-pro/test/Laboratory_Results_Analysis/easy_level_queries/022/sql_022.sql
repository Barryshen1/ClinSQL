WITH peak_patient_ph AS (
  -- First, find the peak (maximum) pH for each male patient recorded during an ICU stay.
  SELECT
    p.subject_id,
    MAX(le.valuenum) AS peak_ph
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON i.hadm_id = le.hadm_id -- Joining on hadm_id is sufficient as it's patient-specific
  WHERE
    p.gender = 'M'
    AND le.itemid = 50820 -- itemid for pH from a Blood Gas
    AND le.valuenum IS NOT NULL
    -- Filter for physiologically plausible pH values to improve data quality
    AND le.valuenum BETWEEN 6.8 AND 8.0
    -- Ensure the lab measurement was taken during the ICU stay
    AND le.charttime BETWEEN i.intime AND i.outtime
  GROUP BY
    p.subject_id
)
-- Now, calculate the Interquartile Range (IQR) of these peak pH values across all patients.
SELECT
  -- APPROX_QUANTILES(value, 4) returns an array: [min, Q1, median, Q3, max]
  -- IQR is Q3 (element at offset 3) - Q1 (element at offset 1)
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(3)] - APPROX_QUANTILES(peak_ph, 4)[OFFSET(1)] AS iqr_of_peak_ph
FROM
  peak_patient_ph;