WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.hadm_id,
    adm.admittime,
    -- Calculate approximate age at hospital admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),

first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN cohort
    ON icu.subject_id = cohort.subject_id
    AND icu.hadm_id = cohort.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) = 1  -- First ICU stay per admission
),

first_spo2 AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS spo2_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS measurement_rank
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_icu
    ON ce.stay_id = first_icu.stay_id
  WHERE ce.itemid = 220277  -- SpO2 measurement item ID
    AND ce.valuenum IS NOT NULL  -- Ensure numeric value exists
)

SELECT STDDEV(spo2_value) AS spo2_stddev
FROM first_spo2
WHERE measurement_rank = 1;  -- First SpO2 per ICU stay;