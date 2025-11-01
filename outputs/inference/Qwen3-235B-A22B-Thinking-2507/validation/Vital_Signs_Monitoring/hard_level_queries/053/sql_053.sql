WITH icu_stays AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,  -- Added to include ICU length of stay
    EXTRACT(YEAR FROM icu.intime) - (pat.anchor_year - pat.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND EXTRACT(YEAR FROM icu.intime) - (pat.anchor_year - pat.anchor_age) BETWEEN 59 AND 69
),
shock_diagnosis AS (
  SELECT 
    icu.hadm_id,
    MAX(CASE WHEN d.icd_code IN ('R570','R571','R572','R578','R579') THEN 1 ELSE 0 END) AS has_shock
  FROM icu_stays icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.hadm_id = d.hadm_id
  GROUP BY icu.hadm_id
),
vital_signs AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum ELSE NULL END) AS map_value,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS hr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN icu_stays icu ON ce.stay_id = icu.stay_id
  WHERE ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220052, 220045)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, ce.charttime
),
vital_intervals AS (
  SELECT 
    vs.stay_id,
    vs.charttime,
    icu.intime,
    LEAD(vs.charttime) OVER (PARTITION BY vs.stay_id ORDER BY vs.charttime) AS next_charttime,
    vs.map_value,
    vs.hr_value
  FROM vital_signs vs
  INNER JOIN icu_stays icu ON vs.stay_id = icu.stay_id
),
burden_intervals AS (
  SELECT 
    stay_id,
    charttime,
    intime,
    LEAST(
      COALESCE(next_charttime, TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)),
      TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
    ) AS end_interval,
    map_value,
    hr_value,
    TIMESTAMP_DIFF(
      LEAST(
        COALESCE(next_charttime, TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)),
        TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
      ),
      charttime,
      MINUTE
    ) AS duration_minutes
  FROM vital_intervals
),
burden_metrics AS (
  SELECT 
    stay_id,
    SUM(CASE WHEN map_value < 65 THEN duration_minutes ELSE 0 END) AS hypotension_minutes,
    SUM(CASE WHEN hr_value > 100 THEN duration_minutes ELSE 0 END) AS tachycardia_minutes,
    SUM(CASE WHEN map_value < 65 OR hr_value > 100 THEN duration_minutes ELSE 0 END) AS composite_minutes
  FROM burden_intervals
  GROUP BY stay_id
),
outcomes AS (
  SELECT 
    icu.stay_id,
    icu.los AS icu_los_days,
    adm.hospital_expire_flag AS mortality
  FROM icu_stays icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
)
SELECT 
  sd.has_shock,
  AVG(bm.composite_minutes) AS mean_composite_minutes,
  APPROX_QUANTILES(bm.composite_minutes, 100)[OFFSET(50)] AS median_composite_minutes,
  APPROX_QUANTILES(bm.composite_minutes, 100)[OFFSET(25)] AS p25_composite_minutes,
  APPROX_QUANTILES(bm.composite_minutes, 100)[OFFSET(75)] AS p75_composite_minutes,
  
  AVG(bm.hypotension_minutes) AS mean_hypotension_minutes,
  APPROX_QUANTILES(bm.hypotension_minutes, 100)[OFFSET(50)] AS median_hypotension_minutes,
  APPROX_QUANTILES(bm.hypotension_minutes, 100)[OFFSET(25)] AS p25_hypotension_minutes,
  APPROX_QUANTILES(bm.hypotension_minutes, 100)[OFFSET(75)] AS p75_hypotension_minutes,
  
  AVG(bm.tachycardia_minutes) AS mean_tachycardia_minutes,
  APPROX_QUANTILES(bm.tachycardia_minutes, 100)[OFFSET(50)] AS median_tachycardia_minutes,
  APPROX_QUANTILES(bm.tachycardia_minutes, 100)[OFFSET(25)] AS p25_tachycardia_minutes,
  APPROX_QUANTILES(bm.tachycardia_minutes, 100)[OFFSET(75)] AS p75_tachycardia_minutes,
  
  AVG(o.icu_los_days) AS mean_icu_los_days,
  APPROX_QUANTILES(o.icu_los_days, 100)[OFFSET(50)] AS median_icu_los_days,
  APPROX_QUANTILES(o.icu_los_days, 100)[OFFSET(25)] AS p25_icu_los_days,
  APPROX_QUANTILES(o.icu_los_days, 100)[OFFSET(75)] AS p75_icu_los_days,
  
  AVG(o.mortality) AS mortality_rate
FROM icu_stays icu
INNER JOIN shock_diagnosis sd ON icu.hadm_id = sd.hadm_id
LEFT JOIN burden_metrics bm ON icu.stay_id = bm.stay_id
INNER JOIN outcomes o ON icu.stay_id = o.stay_id
GROUP BY sd.has_shock;