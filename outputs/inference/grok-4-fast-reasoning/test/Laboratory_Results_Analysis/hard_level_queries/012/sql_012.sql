WITH candidates AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),
ami_hadms AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN candidates c ON d.hadm_id = c.hadm_id
  WHERE ((d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%'))
    AND d.seq_num = 1
),
scores AS (
  SELECT 
    le.hadm_id,
    COUNT(CASE WHEN le.flag != '' AND le.flag IS NOT NULL THEN 1 END) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN candidates c ON le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),
summary AS (
  SELECT 
    c.hadm_id,
    COALESCE(s.instability_score, 0) AS score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag,
    CASE WHEN ah.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ami
  FROM candidates c
  LEFT JOIN scores s ON c.hadm_id = s.hadm_id
  LEFT JOIN ami_hadms ah ON c.hadm_id = ah.hadm_id
  WHERE c.dischtime IS NOT NULL  -- Exclude incomplete admissions
),
ami_stats AS (
  SELECT 
    COUNT(*) AS n_ami,
    APPROX_QUANTILES(score, 4)[OFFSET(3)] AS p75_score,
    AVG(score) AS avg_score_ami,
    AVG(los_days) AS avg_los_ami,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mort_rate_ami
  FROM summary 
  WHERE is_ami = 1
),
general_stats AS (
  SELECT 
    COUNT(*) AS n_general,
    AVG(score) AS avg_score_general
  FROM summary 
  WHERE is_ami = 0
)
SELECT 
  p75_score,
  avg_score_ami AS critical_freq_ami,
  avg_score_general AS critical_freq_general,
  avg_los_ami AS avg_los,
  mort_rate_ami AS mortality_rate,
  n_ami,
  n_general
FROM ami_stats, general_stats;