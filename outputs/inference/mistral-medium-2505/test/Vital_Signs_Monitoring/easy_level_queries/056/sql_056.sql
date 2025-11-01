WITH
-- Get male patients aged 46-56 at ICU admission
patient_icu_stays AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    TIMESTAMP_DIFF(i.intime, TIMESTAMP(DATE(p.anchor_year, 1, 1)), YEAR) AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND TIMESTAMP_DIFF(i.intime, TIMESTAMP(DATE(p.anchor_year, 1, 1)), YEAR) BETWEEN 46 AND 56
),

-- Get temperature measurements in the first 24 hours of ICU stay
temperature_measurements AS (
  SELECT
    psi.subject_id,
    psi.stay_id,
    ce.valuenum AS temperature_f,
    ce.charttime
  FROM
    patient_icu_stays psi
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON psi.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Temperature F'
    AND ce.charttime BETWEEN psi.intime AND TIMESTAMP_ADD(psi.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate median temperature per patient
patient_medians AS (
  SELECT DISTINCT
    subject_id,
    PERCENTILE_CONT(temperature_f, 0.5) OVER (PARTITION BY subject_id) AS median_temp_f
  FROM
    temperature_measurements
)

-- Final median across all patients
SELECT
  PERCENTILE_CONT(median_temp_f, 0.5) AS overall_median_temp_f
FROM
  patient_medians
WHERE
  median_temp_f IS NOT NULL;