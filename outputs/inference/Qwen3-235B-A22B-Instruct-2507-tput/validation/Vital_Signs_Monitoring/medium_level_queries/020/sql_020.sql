WITH patient_cohort AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.intime,
    s.outtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission
    (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 58 AND 68
),
map_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum,
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'mean blood pressure'
    AND di.unitname = 'mmHg'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
map_in_first_48h AS (
  SELECT 
    pc.stay_id,
    mm.valuenum
  FROM patient_cohort pc
  JOIN map_measurements mm
    ON pc.stay_id = mm.stay_id
  WHERE mm.charttime >= pc.intime
    AND mm.charttime <= DATETIME_ADD(pc.intime, INTERVAL 48 HOUR)
),
mean_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_map
  FROM map_in_first_48h
  GROUP BY stay_id
  HAVING COUNT(*) >= 1
)
SELECT 
  SAFE_DIVIDE(COUNTIF(mean_map <= 85), COUNT(*)) * 100 AS percentile
FROM mean_map_per_stay;