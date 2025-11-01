WITH 
  -- Filter patients and calculate ICU length of stay
  icu_patients AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      p.gender,
      p.anchor_age,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 49 AND 59
  ),

  -- Calculate composite vital instability score for the first 24 hours
  vital_scores AS (
    SELECT 
      ce.subject_id,
      ce.stay_id,
      AVG(CASE 
        WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 
        ELSE 0 
      END) AS hr_score,
      AVG(CASE 
        WHEN ce.itemid = 220179 AND ce.valuenum > 20 THEN 1 
        ELSE 0 
      END) AS rr_score,
      AVG(CASE 
        WHEN ce.itemid = 220052 AND ce.valuenum > 140 THEN 1 
        ELSE 0 
      END) AS sbp_score
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      icu_patients ip 
        ON ce.subject_id = ip.subject_id AND ce.stay_id = ip.stay_id
    WHERE 
      ce.charttime BETWEEN ip.intime AND TIMESTAMP_ADD(ip.intime, INTERVAL 24 HOUR)
      AND ce.itemid IN (220050, 220179, 220052)
    GROUP BY 
      ce.subject_id, ce.stay_id
  ),

  -- Combine ICU patient data with vital scores
  patient_scores AS (
    SELECT 
      ip.*,
      COALESCE(vs.hr_score, 0) + COALESCE(vs.rr_score, 0) + COALESCE(vs.sbp_score, 0) AS vital_score
    FROM 
      icu_patients ip
    LEFT JOIN 
      vital_scores vs 
        ON ip.subject_id = vs.subject_id AND ip.stay_id = vs.stay_id
  ),

  -- Calculate statistics
  patient_stats AS (
    SELECT 
      ps.vital_score,
      DATE_DIFF(TIMESTAMP(ps.outtime), TIMESTAMP(ps.intime), DAY) AS icu_los,
      ps.hospital_expire_flag
    FROM 
      patient_scores ps
  )

-- Calculate percentile of vital score 70 and statistics for top decile
SELECT 
  APPROX_QUANTILES(vital_score, 1000)[700] AS percentile_70,
  AVG(icu_los) AS mean_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS hospital_mortality
FROM 
  patient_stats;