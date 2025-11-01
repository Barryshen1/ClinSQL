WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  -- Filter for male and age 88-98
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 88 AND 98
    -- Ensure RRT occurred within first 72 hours of ICU stay
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = ie.stay_id
        AND pe.itemid IN (225802, 225803, 225804, 225809)  -- RRT procedure codes
        AND pe.starttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
    )
),

scores AS (
  SELECT 
    stay_id,
    -- Placeholder: Replace with actual instability score calculation
    RAND() * 100 AS instability_score
  FROM cohort
),

percentile_of_85 AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_85
  FROM scores
  WHERE instability_score = 85
  LIMIT 1
),

quartiles AS (
  SELECT 
    stay_id,
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM scores
),

top_quartile_data AS (
  SELECT 
    q.stay_id,
    i.los AS icu_los,
    adm.hospital_expire_flag
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON q.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON i.hadm_id = adm.hadm_id
  WHERE q.instability_quartile = 1  -- Most unstable quartile
)

SELECT 
  (SELECT percentile_85 FROM percentile_of_85) AS percentile_for_85,
  ROUND(AVG(icu_los), 2) AS avg_icu_los_top_quartile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_percent_top_quartile
FROM top_quartile_data;