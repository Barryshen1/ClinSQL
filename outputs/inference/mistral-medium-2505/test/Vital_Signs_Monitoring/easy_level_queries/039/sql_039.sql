WITH
-- Filter for 51-61 year old females
female_patients_51_61 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get ICU admissions for these patients
icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_admission_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients_51_61)
    AND (i.first_careunit = 'ICU' OR i.first_careunit = 'Stepdown')
),

-- Get first respiratory rate for each ICU admission
first_respiratory_rates AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.stay_id,
    ce.valuenum AS first_respiratory_rate
  FROM
    icu_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ia.subject_id = ce.subject_id
    AND ia.hadm_id = ce.hadm_id
    AND ia.stay_id = ce.stay_id
    AND ce.itemid = 220212  -- Hardcoded respiratory rate itemid
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY ia.subject_id, ia.hadm_id, ia.stay_id
      ORDER BY TIMESTAMP_DIFF(ce.charttime, ia.icu_admission_time, SECOND)
    ) = 1
)

-- Calculate 25th percentile of first respiratory rates
SELECT
  PERCENTILE_CONT(first_respiratory_rate, 0.25) OVER() AS percentile_25_respiratory_rate
FROM
  first_respiratory_rates
LIMIT 1;