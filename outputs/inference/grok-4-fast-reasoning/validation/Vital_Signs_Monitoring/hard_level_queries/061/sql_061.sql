WITH cohort AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.hadm_id, 
    i.los, 
    i.intime,
    p.gender, 
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),
vitals AS (
  SELECT 
    ce.stay_id,
    MIN(CASE WHEN ce.itemid IN (51, 442, 455, 6701, 220179, 225309) 
             THEN ce.valuenum END) AS min_sbp,
    MAX(CASE WHEN ce.itemid IN (211, 220045) 
             THEN ce.valuenum END) AS max_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c 
    ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
scored AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    v.min_sbp,
    v.max_hr,
    (CASE 
       WHEN v.min_sbp IS NOT NULL AND v.min_sbp < 90 
       THEN 90 - v.min_sbp 
       ELSE 0 
     END +
     CASE 
       WHEN v.max_hr IS NOT NULL AND v.max_hr > 100 
       THEN v.max_hr - 100 
       ELSE 0 
     END) AS instability_score
  FROM cohort c
  LEFT JOIN vitals v 
    ON c.stay_id = v.stay_id
  WHERE v.min_sbp IS NOT NULL OR v.max_hr IS NOT NULL  -- At least one vital measured
),
quantiles AS (
  SELECT 
    COUNTIF(instability_score <= 70) * 100.0 / COUNT(*) AS percentile_for_70,
    APPROX_QUANTILES(instability_score, 10)[OFFSET(9)] AS score_p90
  FROM scored
),
top_decile AS (
  SELECT 
    s.los,
    s.hospital_expire_flag
  FROM scored s
  CROSS JOIN quantiles q
  WHERE s.instability_score >= q.score_p90
)
SELECT 
  q.percentile_for_70,
  AVG(td.los) AS mean_los_days_top_decile,
  AVG(CAST(td.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct_top_decile
FROM quantiles q
CROSS JOIN top_decile td;