WITH population AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 49 AND 59
),
vital_signs AS (
  SELECT 
    c.stay_id,
    AVG(CASE WHEN c.itemid = 220045 AND c.valuenum IS NOT NULL 
             THEN ABS(c.valuenum - 80) 
             ELSE NULL END) AS hr_deviation,
    AVG(CASE WHEN c.itemid = 220179 AND c.valuenum IS NOT NULL 
             THEN ABS(c.valuenum - 105) 
             ELSE NULL END) AS sbp_deviation,
    AVG(CASE WHEN c.itemid = 220210 AND c.valuenum IS NOT NULL 
             THEN ABS(c.valuenum - 16) 
             ELSE NULL END) AS rr_deviation,
    AVG(CASE WHEN c.itemid = 220277 AND c.valuenum IS NOT NULL 
             THEN ABS(97.5 - c.valuenum) 
             ELSE NULL END) AS spo2_deviation
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN population p
    ON c.stay_id = p.stay_id
  WHERE c.charttime BETWEEN p.intime AND TIMESTAMP_ADD(p.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
scored_population AS (
  SELECT 
    p.stay_id,
    p.los,
    p.hospital_expire_flag,
    COALESCE(vs.hr_deviation, 0) + 
    COALESCE(vs.sbp_deviation, 0) + 
    COALESCE(vs.rr_deviation, 0) + 
    COALESCE(vs.spo2_deviation, 0) AS vital_instability_score
  FROM population p
  LEFT JOIN vital_signs vs
    ON p.stay_id = vs.stay_id
  WHERE vs.stay_id IS NOT NULL
),
with_decile AS (
  SELECT *,
    NTILE(10) OVER (ORDER BY vital_instability_score DESC) AS decile
  FROM scored_population
)
SELECT 
  SUM(CASE WHEN vital_instability_score <= 70 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_70,
  AVG(CASE WHEN decile = 1 THEN los END) AS mean_los_top_decile,
  AVG(CASE WHEN decile = 1 THEN hospital_expire_flag END) * 100 AS mortality_pct_top_decile
FROM with_decile;