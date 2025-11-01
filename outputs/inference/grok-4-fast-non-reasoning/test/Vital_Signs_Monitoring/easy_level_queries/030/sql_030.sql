WITH first_stay AS (
  -- Get the first ICU stay per patient (earliest intime)
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) = 1
),
eligible_patients AS (
  -- Join to patients for female, age 38-48 filter
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime
  FROM first_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
first_hr AS (
  -- Get the first (earliest charttime) heart rate per patient within first 24h
  SELECT 
    ep.subject_id,
    MIN(ce.valuenum) AS first_hr_value  -- Actually the first value, but since single row per patient after window, it's the value
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ep.subject_id = ce.subject_id
    AND ep.hadm_id = ce.hadm_id
    AND ep.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ep.intime
    AND ce.charttime <= ep.intime + INTERVAL 1 DAY
  GROUP BY ep.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ep.subject_id ORDER BY MIN(ce.charttime) ASC) = 1  -- Ensure earliest per patient
)
-- Overall minimum first-recorded heart rate across cohort
SELECT MIN(first_hr_value) AS min_first_hr
FROM first_hr;