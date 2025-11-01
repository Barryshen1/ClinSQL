WITH cohort AS (
  -- Define cohort: male, age 52-62 at admission, primary asthma diagnosis
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'J45%') 
      OR (d.icd_version = 9 AND d.icd_code LIKE '493%')
    )
),
lab_scores AS (
  -- Compute instability score: count of flagged abnormal labs in first 72h
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c 
    ON le.subject_id = c.subject_id 
    AND le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY)
    AND le.flag IN ('abnormal', 'high', 'low')
  GROUP BY le.subject_id, le.hadm_id
),
scores AS (
  -- Attach scores to cohort (0 if no labs)
  SELECT 
    c.*,
    COALESCE(ls.instability_score, 0) AS score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort c
  LEFT JOIN lab_scores ls 
    ON c.hadm_id = ls.hadm_id
),
p90 AS (
  -- Compute 90th percentile score
  SELECT 
    approx_quantiles(score, [0.9])[OFFSET(0)] AS p90_score
  FROM scores
),
classified AS (
  -- Classify into top decile vs rest; cross join for scalar p90
  SELECT 
    s.*,
    CASE 
      WHEN s.score >= p.p90_score THEN 'Top Decile'
      ELSE 'Non-Top Decile'
    END AS group_label,
    p.p90_score
  FROM scores s
  CROSS JOIN p90 p
)
-- Aggregate metrics by group; p90 is constant
SELECT 
  group_label,
  p90_score,
  COUNT(*) AS n_admissions,
  AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(score) AS avg_critical_lab_events
FROM classified
GROUP BY group_label, p90_score
ORDER BY 
  CASE WHEN group_label = 'Top Decile' THEN 1 ELSE 2 END;