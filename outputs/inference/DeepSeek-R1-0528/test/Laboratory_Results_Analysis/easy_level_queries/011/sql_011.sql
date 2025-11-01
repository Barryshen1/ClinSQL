WITH first_admission AS (
  SELECT 
    p.subject_id, 
    MIN(a.admittime) AS first_admittime,
    p.anchor_age,
    p.gender,
    DATE_SUB(MIN(a.admittime), INTERVAL p.anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  GROUP BY p.subject_id, p.anchor_age, p.gender
),
cohort AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN first_admission fa
    ON icu.subject_id = fa.subject_id
  WHERE 
    fa.gender = 'M' 
    AND DATE_DIFF(icu.intime, fa.birth_date, YEAR) = 56
),
potassium_events AS (
  SELECT 
    c.stay_id,
    le.valuenum AS potassium_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.intime AND c.outtime
  WHERE 
    le.itemid = 50971  -- Serum potassium
    AND le.valuenum IS NOT NULL
),
peak_per_stay AS (
  SELECT 
    stay_id,
    MAX(potassium_value) AS peak_potassium
  FROM potassium_events
  GROUP BY stay_id
)
SELECT 
  STDDEV_SAMP(peak_potassium) AS std_dev_peak_potassium
FROM peak_per_stay;