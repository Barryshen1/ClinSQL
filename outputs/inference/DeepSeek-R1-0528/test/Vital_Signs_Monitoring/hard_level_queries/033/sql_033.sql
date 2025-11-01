WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR) >= 48  -- Ensure minimum 48h stay
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 51 AND 61
    -- Invasive ventilation in first 48h
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = ie.stay_id
        AND pe.itemid IN (227194, 225468)  -- Intubation/Tracheostomy
        AND pe.starttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
    )
),

vital_signs AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS max_hr,  -- Heart Rate
    MIN(CASE WHEN ce.itemid = 220050 THEN ce.valuenum END) AS min_sbp  -- Systolic BP
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220045, 220050)  -- HR and SBP items
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

scores AS (
  SELECT 
    c.*,
    (v.max_hr + v.min_sbp) / 10 AS instability_score  -- Simplified score
  FROM cohort c
  LEFT JOIN vital_signs v ON c.stay_id = v.stay_id
  WHERE v.max_hr IS NOT NULL AND v.min_sbp IS NOT NULL  -- Exclude missing vitals
),

scores_with_outcome AS (
  SELECT 
    s.*,
    a.hospital_expire_flag
  FROM scores s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
),

percentile AS (
  SELECT 
    (SUM(CASE WHEN instability_score <= 80 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_of_80
  FROM scores_with_outcome
),

deciles AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM scores_with_outcome
),

most_unstable AS (
  SELECT 
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
  FROM deciles
  WHERE decile = 1  -- Top decile (most unstable)
)

SELECT 
  (SELECT percentile_of_80 FROM percentile) AS percentile_of_80,
  (SELECT avg_icu_los FROM most_unstable) AS avg_icu_los_top_decile,
  (SELECT mortality_rate_percent FROM most_unstable) AS mortality_rate_percent_top_decile;