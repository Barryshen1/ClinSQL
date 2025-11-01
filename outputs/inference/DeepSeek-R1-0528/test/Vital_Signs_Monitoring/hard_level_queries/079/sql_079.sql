WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.hospital_expire_flag,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    -- Calculate age at admission: anchor_age + (admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON a.hadm_id = ie.hadm_id
  WHERE p.gender = 'M'
),
hfnc_patients AS (
  SELECT 
    c.*
  FROM cohort c
  WHERE 
    c.age_admit BETWEEN 81 AND 91
    -- Ensure HFNC occurred within first 48h of ICU stay
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE 
        pe.stay_id = c.stay_id
        AND pe.itemid = 227579  -- HFNC itemid
        AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    )
),
scores AS (
  SELECT 
    *,
    -- Simulated composite score (replace with actual logic)
    50 + MOD(ABS(FARM_FINGERPRINT(CAST(stay_id AS STRING))), 101) AS instab_score
  FROM hfnc_patients
),
percentile_calc AS (
  SELECT 
    -- Percentile of score=85 in the cohort
    ROUND(PERCENT_RANK() OVER (ORDER BY instab_score) * 100, 2) AS percentile_85
  FROM scores
  WHERE instab_score = 85
  LIMIT 1
),
top_decile AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY instab_score DESC) AS score_decile
  FROM scores
),
outcomes AS (
  SELECT 
    ROUND(AVG(los), 2) AS avg_icu_los,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_pct
  FROM top_decile
  WHERE score_decile = 1  -- Top 10% highest scores
)
SELECT 
  (SELECT percentile_85 FROM percentile_calc) AS percentile_for_85,
  avg_icu_los,
  hospital_mortality_pct
FROM outcomes;