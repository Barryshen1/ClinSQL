WITH 
  heart_rate_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%Heart Rate%'
      AND category = 'Vital Signs'
      AND unitname = 'bpm'
  ),
  icu_stays_filtered AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_year IS NOT NULL
      AND p.anchor_age IS NOT NULL
      AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 55 AND 65
  ),
  heart_rate_measurements AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      ce.valuenum AS heart_rate
    FROM icu_stays_filtered i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON i.subject_id = ce.subject_id
      AND i.hadm_id = ce.hadm_id
      AND i.stay_id = ce.stay_id
      AND ce.charttime BETWEEN i.intime AND i.outtime
    INNER JOIN heart_rate_items hri
      ON ce.itemid = hri.itemid
    WHERE ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
  ),
  max_hr_per_stay AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      MAX(heart_rate) AS max_hr
    FROM heart_rate_measurements
    GROUP BY subject_id, hadm_id, stay_id
  )
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY max_hr) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY max_hr) AS q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY max_hr) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY max_hr) AS iqr
FROM max_hr_per_stay;