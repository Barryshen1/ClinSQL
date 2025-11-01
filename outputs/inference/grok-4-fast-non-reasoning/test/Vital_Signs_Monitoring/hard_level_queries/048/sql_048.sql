WITH cohort AS (
  -- Base cohort: female, 75-85, ICU stays with IMV
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND i.first_careunit != 'NICU'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.subject_id = i.subject_id
        AND pe.hadm_id = i.hadm_id
        AND pe.stay_id = i.stay_id
        AND pe.itemid IN (225477, 225651, 227464)  -- Ventilator modes/setup
        AND pe.starttime BETWEEN i.intime AND i.outtime
    )
),

hourly_instability AS (
  -- Hourly instability proportions in first 48h
  SELECT 
    c.stay_id,
    c.intime,
    TIMESTAMP_DIFF(ce.charttime, c.intime, HOUR) AS hour_num,
    -- Hypotension: MAP < 65
    COUNTIF(ce.itemid = 220052 AND ce.valuenum < 65) * 1.0 / NULLIF(COUNTIF(ce.itemid = 220052), 0) AS prop_hypotension,
    -- Tachycardia: HR > 110
    COUNTIF(ce.itemid = 220045 AND ce.valuenum > 110) * 1.0 / NULLIF(COUNTIF(ce.itemid = 220045), 0) AS prop_tachycardia,
    -- Hypoxemia: SpO2 < 90
    COUNTIF(ce.itemid = 220277 AND ce.valuenum < 90) * 1.0 / NULLIF(COUNTIF(ce.itemid = 220277), 0) AS prop_hypoxemia
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
    AND ce.itemid IN (220052, 220045, 220277)
    AND ce.charttime BETWEEN c.intime AND DATE_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id, c.intime, hour_num
),

stay_scores AS (
  -- Composite score: avg hourly instability (equal weights)
  SELECT 
    stay_id,
    AVG(
      COALESCE(prop_hypotension, 0) * 0.33 + 
      COALESCE(prop_tachycardia, 0) * 0.33 + 
      COALESCE(prop_hypoxemia, 0) * 0.34
    ) AS instability_score,
    los,
    hospital_expire_flag,
    intime,
    hadm_id
  FROM hourly_instability
  GROUP BY stay_id, los, hospital_expire_flag, intime, hadm_id
  UNION ALL
  -- Stays with no data: score=0
  SELECT 
    stay_id,
    0.0 AS instability_score,
    los,
    hospital_expire_flag,
    intime,
    hadm_id
  FROM cohort c2
  WHERE NOT EXISTS (
    SELECT 1 FROM hourly_instability hi WHERE hi.stay_id = c2.stay_id
  )
),

top_25_threshold AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS q75,
    COUNT(*) AS total_stays
  FROM stay_scores
),

top_25_stays AS (
  SELECT s.*
  FROM stay_scores s
  CROSS JOIN top_25_threshold t
  WHERE s.instability_score >= t.q75
),

top_25_metrics AS (
  -- Hypotension and tachycardia means in top 25% (full stay)
  SELECT 
    AVG(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN ce.valuenum END) AS mean_hypotension,
    AVG(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 110 THEN ce.valuenum END) AS mean_tachycardia,
    AVG(t.los) AS mean_icu_los_top25,
    AVG(t.hospital_expire_flag * 1.0) AS mortality_top25
  FROM top_25_stays t
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON t.stay_id = ce.stay_id
    AND t.hadm_id = ce.hadm_id
    AND ce.itemid IN (220052, 220045)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN t.intime AND t.outtime  -- Full stay for hypo/tachy
)

SELECT 
  PERCENTILE_CONT(ss.instability_score, 0.9) OVER() AS p90_instability_score,
  tm.mean_hypotension,
  tm.mean_tachycardia,
  tm.mean_icu_los_top25,
  tm.mortality_top25
FROM stay_scores ss
CROSS JOIN top_25_metrics tm
LIMIT 1;