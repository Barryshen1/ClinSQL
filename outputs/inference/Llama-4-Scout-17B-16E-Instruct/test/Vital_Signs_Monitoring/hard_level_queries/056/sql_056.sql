WITH 
-- Define itemids for vital signs
vital_itemids AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Vital Signs'
),

-- Filter patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, ic.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 74 AND 84
),

-- Calculate instability
instability AS (
  SELECT 
    poi.stay_id,
    TIMESTAMP_DIFF(ce.charttime, ic.intime, HOUR) AS time_diff,
    CASE 
      WHEN ce.itemid = 220050 AND ce.valuenum > 38.5 THEN 1 
      WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 
      WHEN ce.itemid = 220052 AND ce.valuenum > 20 THEN 1 
      ELSE 0 
    END AS instability_hour
  FROM patients_of_interest poi
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON poi.stay_id = ic.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ic.stay_id = ce.stay_id
  WHERE ce.itemid IN (220050, 220179, 220052)  -- Temperature, SpO2, RR
    AND TIMESTAMP_DIFF(ce.charttime, ic.intime, HOUR) BETWEEN 0 AND 48  -- First 48h
),

-- Calculate total instability hours per patient
total_instability AS (
  SELECT stay_id, SUM(instability_hour) AS total_instability_hours
  FROM instability
  GROUP BY stay_id
),

-- Calculate ICU LOS and mortality
icu_outcomes AS (
  SELECT 
    ic.stay_id,
    TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR) AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ic.hadm_id = a.hadm_id
),

-- Combine instability with outcomes and calculate specific instability hours
combined AS (
  SELECT 
    ti.stay_id,
    ti.total_instability_hours,
    io.icu_los,
    io.mortality,
    SUM(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_hours,
    SUM(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypoxemia_hours,
    SUM(CASE WHEN ce.itemid = 220052 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_hours
  FROM total_instability ti
  JOIN icu_outcomes io ON ti.stay_id = io.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ti.stay_id = ce.stay_id
  WHERE ce.itemid IN (220050, 220179, 220052)
    AND TIMESTAMP_DIFF(ce.charttime, io.icustays.intime, HOUR) BETWEEN 0 AND 48
  GROUP BY ti.stay_id, ti.total_instability_hours, io.icu_los, io.mortality
)

-- Calculate 90th percentile instability and report top decile
SELECT 
  APPROX_QUANTILES(total_instability_hours, 10)[9] AS percentile_90,
  COUNT(*) AS n,
  AVG(icu_los) AS mean_icu_los,
  AVG(mortality) * 100 AS mortality_pct,
  AVG(fever_hours) AS mean_fever_hours,
  AVG(hypoxemia_hours) AS mean_hypoxemia_hours,
  AVG(tachypnea_hours) AS mean_tachypnea_hours
FROM combined;