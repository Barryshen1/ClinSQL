WITH cohort AS (
  -- Base ICU cohort: males 84-94, first stay, with ischemic stroke
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn_stay
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND i.los >= 1  -- At least 24h in ICU
  QUALIFY rn_stay = 1  -- First ICU stay
),

stroke_cohort AS (
  -- Filter for ischemic stroke (ICD-10 I63*)
  SELECT 
    c.*,
    COUNTIF(d.icd_code LIKE 'I63%') > 0 AS has_stroke
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id 
    AND d.icd_version = 10  -- Fixed: numeric for INT64 column
  GROUP BY 
    c.subject_id, c.stay_id, c.hadm_id, c.intime, c.outtime, c.los, 
    c.gender, c.anchor_age, c.hospital_expire_flag, c.rn_stay
  HAVING has_stroke = TRUE
),

vitals AS (
  -- Extract and average vitals in first 72h; hourly buckets
  SELECT 
    sc.stay_id,
    sc.subject_id,
    sc.intime,
    TIMESTAMP_DIFF(v.charttime, sc.intime, HOUR) AS hour_num,
    AVG(CASE WHEN v.itemid IN (211, 220045) THEN v.valuenum END) AS avg_hr,
    AVG(CASE WHEN v.itemid IN (618, 220210) THEN v.valuenum END) AS avg_rr,
    AVG(CASE WHEN v.itemid IN (51, 220179) THEN v.valuenum END) AS avg_sbp,
    AVG(CASE WHEN v.itemid IN (8368, 220180) THEN v.valuenum END) AS avg_dbp,
    AVG(CASE WHEN v.itemid IN (676, 223761) THEN v.valuenum END) AS avg_temp
  FROM stroke_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` v 
    ON sc.stay_id = v.stay_id
    AND v.itemid IN (211, 220045, 618, 220210, 51, 220179, 8368, 220180, 676, 223761)
    AND v.charttime >= sc.intime 
    AND v.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR)
    AND v.valuenum IS NOT NULL
  GROUP BY sc.stay_id, sc.subject_id, sc.intime, hour_num
  HAVING hour_num <= 71  -- 0-71 hours
),

hourly_instability AS (
  -- Binary instability per hour
  SELECT 
    stay_id,
    hour_num,
    CASE 
      WHEN (avg_hr > 100 OR avg_hr < 60) OR 
           (avg_rr > 25 OR avg_rr < 12) OR 
           (avg_sbp > 180 OR avg_sbp < 90) OR 
           (avg_dbp > 100 OR avg_dbp < 60) OR 
           (avg_temp > 38.5 OR avg_temp < 36) 
      THEN 1 ELSE 0 
    END AS unstable_hour
  FROM vitals
),

instability_scores AS (
  -- Sum unstable hours per patient (max 72)
  SELECT 
    sc.stay_id,
    sc.subject_id,
    sc.los,
    sc.hospital_expire_flag AS mortality,
    COALESCE(SUM(hi.unstable_hour), 0) AS instability_score
  FROM stroke_cohort sc
  LEFT JOIN hourly_instability hi 
    ON sc.stay_id = hi.stay_id
  GROUP BY sc.stay_id, sc.subject_id, sc.los, sc.mortality
),

ranked_scores AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score DESC) AS percentile_rank,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM instability_scores
),

top_quartile AS (
  -- Identify top quartile (highest scores)
  SELECT 
    stay_id,
    los,
    mortality
  FROM ranked_scores
  WHERE quartile = 1
),

max_score_stats AS (
  SELECT 
    instability_score AS max_observed_score,
    percentile_rank AS percentile_for_max
  FROM ranked_scores
  ORDER BY instability_score DESC
  LIMIT 1
)

-- Final results
SELECT 
  -- Percentile for score=80 (impossible; report for max observed instead)
  (SELECT percentile_for_max * 100 FROM max_score_stats) AS percentile_for_max_observed_score,
  (SELECT max_observed_score FROM max_score_stats) AS max_observed_instability_score,
  -- Top quartile stats
  AVG(tq.los) AS avg_los_top_quartile,
  AVG(tq.mortality) AS mortality_rate_top_quartile,
  COUNT(*) AS top_quartile_n
FROM top_quartile tq;