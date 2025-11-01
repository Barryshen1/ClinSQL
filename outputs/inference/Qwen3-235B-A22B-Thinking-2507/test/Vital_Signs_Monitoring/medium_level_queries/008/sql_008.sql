WITH population AS (
  SELECT 
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'M'
    AND (EXTRACT(YEAR FROM admissions.admittime) - (patients.anchor_year - patients.anchor_age)) BETWEEN 39 AND 49
),
stay_avg_map AS (
  SELECT 
    population.stay_id,
    AVG(chartevents.valuenum) AS avg_map
  FROM population
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON population.stay_id = chartevents.stay_id
    AND chartevents.charttime >= population.intime
    AND chartevents.charttime < population.intime + INTERVAL '24' HOUR
    AND chartevents.itemid IN (52, 457)
    AND chartevents.valuenum IS NOT NULL
  GROUP BY population.stay_id
)
SELECT 
  SAFE_DIVIDE(
    COUNT(CASE WHEN avg_map <= 75 THEN 1 END) * 100.0,
    COUNT(*)
  ) AS percentile
FROM stay_avg_map;