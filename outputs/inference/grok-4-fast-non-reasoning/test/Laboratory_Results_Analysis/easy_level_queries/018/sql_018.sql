WITH female_icu_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
),
abg_ph_on_admission AS (
  SELECT 
    f.subject_id,
    f.stay_id,
    c.valuenum AS ph
  FROM 
    female_icu_stays f
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    f.subject_id = c.subject_id 
    AND f.hadm_id = c.hadm_id 
    AND f.stay_id = c.stay_id
  WHERE 
    c.itemid = 3837  -- pH from arterial blood gas
    AND c.valuenum IS NOT NULL
    AND c.charttime >= f.intime 
    AND c.charttime <= f.intime + INTERVAL 1 DAY
),
patient_median_ph AS (
  SELECT 
    subject_id,
    APPROX_QUANTILES(ph, 2)[OFFSET(1)] AS median_ph_per_patient
  FROM abg_ph_on_admission
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(median_ph_per_patient, 2)[OFFSET(1)] AS median_ph
FROM patient_median_ph;