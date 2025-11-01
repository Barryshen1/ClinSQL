WITH
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 88 AND 98
  ),
  first_icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime, 
      i.outtime, 
      i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN eligible_patients e ON i.subject_id = e.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
  ),
  rrt_patients AS (
    SELECT DISTINCT
      s.subject_id, 
      s.hadm_id, 
      s.stay_id
    FROM first_icu_stays s
    JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON s.subject_id = ie.subject_id 
      AND s.hadm_id = ie.hadm_id 
      AND s.stay_id = ie.stay_id
    WHERE ie.itemid IN (222083, 222084, 222085, 222086, 222087)
      AND ie.starttime BETWEEN s.intime AND s.outtime
  ),
  hr_data AS (
    SELECT 
      s.subject_id, 
      s.hadm_id, 
      s.stay_id,
      ce.valuenum AS hr_value
    FROM rrt_patients s
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON s.subject_id = ce.subject_id 
      AND s.hadm_id = ce.hadm_id 
      AND s.stay_id = ce.stay_id
    WHERE ce.itemid = 220045  -- heart rate
      AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
      AND ce.charttime <= s.outtime  -- Ensure within ICU stay
      AND ce.valuenum IS NOT NULL
  ),
  instability_scores AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      STDDEV_SAMP(hr_value) AS instability_score
    FROM hr_data
    GROUP BY subject_id, hadm_id, stay_id
    HAVING COUNT(hr_value) >= 2  -- at least two measurements to compute std dev
  ),
  cohort AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.los,
      a.hospital_expire_flag,
      s.instability_score
    FROM instability_scores s
    JOIN first_icu_stays i 
      ON s.subject_id = i.subject_id 
      AND s.hadm_id = i.hadm_id 
      AND s.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.subject_id = a.subject_id 
      AND i.hadm_id = a.hadm_id
  ),
  percentile_85 AS (
    SELECT 
      (SELECT COUNT(*) FROM cohort WHERE instability_score <= 85) * 100.0 / (SELECT COUNT(*) FROM cohort) AS percentile_85
  ),
  quartile_groups AS (
    SELECT 
      *,
      NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
    FROM cohort
  ),
  top_quartile AS (
    SELECT 
      AVG(los / 24.0) AS avg_icu_los_days,  -- convert to days
      AVG(hospital_expire_flag) AS mortality_rate  -- Directly average the boolean
    FROM quartile_groups
    WHERE quartile = 1  -- top quartile (highest instability)
  )
SELECT 
  (SELECT percentile_85 FROM percentile_85) AS instability_score_percentile_85,
  (SELECT avg_icu_los_days FROM top_quartile) AS avg_icu_los_days_top_quartile,
  (SELECT mortality_rate FROM top_quartile) AS mortality_rate_top_quartile;