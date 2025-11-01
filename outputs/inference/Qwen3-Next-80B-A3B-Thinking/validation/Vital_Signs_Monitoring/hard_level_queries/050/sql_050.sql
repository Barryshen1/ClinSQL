WITH patients_rrt AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    i.los,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.subject_id = p.subject_id
        AND ie.stay_id = i.stay_id
        AND ie.itemid IN (225163, 225164, 225165)
    )
),
score_data AS (
  SELECT 
    pr.subject_id,
    pr.los,
    pr.hospital_expire_flag,
    FIRST_VALUE(c.valuenum) OVER (PARTITION BY pr.subject_id ORDER BY c.charttime) AS instability_score
  FROM 
    patients_rrt pr
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON pr.stay_id = c.stay_id
    AND c.itemid = 228245
    AND c.charttime BETWEEN pr.intime AND pr.intime + INTERVAL '72' HOUR
),
score_summary AS (
  SELECT 
    instability_score,
    los,
    hospital_expire_flag
  FROM 
    score_data
  WHERE 
    instability_score IS NOT NULL
),
percentile_90 AS (
  SELECT 
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_score) AS threshold
  FROM 
    score_summary
)
SELECT 
  (SELECT COUNT(*) FROM score_summary WHERE instability_score <= 65) * 100.0 / COUNT(*) AS percentile_65,
  AVG(CASE WHEN s.instability_score >= p.threshold THEN s.los END) AS mean_los_top_decile,
  AVG(CASE WHEN s.instability_score >= p.threshold THEN s.hospital_expire_flag END) AS mortality_top_decile
FROM 
  score_summary s
CROSS JOIN 
  percentile_90 p;