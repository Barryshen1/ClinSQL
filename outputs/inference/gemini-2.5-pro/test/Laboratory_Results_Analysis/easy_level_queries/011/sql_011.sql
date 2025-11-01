WITH target_patient AS (
  -- Step 1: Select a single 56-year-old male patient as a representative example
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age = 56
  LIMIT 1
), peak_potassium_per_stay AS (
  -- Step 2: For the selected patient, find the peak serum potassium for each of their ICU stays
  SELECT
    icu.stay_id,
    MAX(le.valuenum) AS peak_potassium
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON le.subject_id = icu.subject_id AND le.hadm_id = icu.hadm_id
  WHERE
    le.subject_id = (SELECT subject_id FROM target_patient)
    AND le.itemid = 50971 -- itemid for Potassium, Serum/Plasma
    AND le.valuenum IS NOT NULL -- Exclude null or invalid measurements
    AND le.charttime BETWEEN icu.intime AND icu.outtime -- Ensure the lab was taken during the ICU stay
  GROUP BY
    icu.stay_id
)
-- Step 3: Calculate the standard deviation of the peak potassium values from each stay
SELECT
  STDDEV(peak_potassium) AS stddev_of_peak_potassium_meq_l
FROM
  peak_potassium_per_stay;