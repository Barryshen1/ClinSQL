WITH cohort_stays AS (
  -- Filter female ICU stays aged 38-48
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND i.los > 0  -- Valid ICU stays
),

first_24h_sbp AS (
  -- Extract SBP measurements in first 24 hours
  SELECT 
    cs.stay_id,
    ce.valuenum
  FROM 
    cohort_stays cs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    cs.subject_id = ce.subject_id
    AND cs.hadm_id = ce.hadm_id
    AND cs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220045, 220179)  -- Systolic BP (arterial or NIBP)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= cs.intime
    AND ce.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
),

per_stay_avg_sbp AS (
  -- Compute average SBP per stay, exclude stays with no measurements
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM 
    first_24h_sbp
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) > 0  -- At least one valid measurement
),

ranked_sbp AS (
  -- Compute percentile rank for each stay's average
  SELECT 
    stay_id,
    avg_sbp,
    PERCENT_RANK() OVER (ORDER BY avg_sbp) AS percent_rank
  FROM 
    per_stay_avg_sbp
)

-- Get the percentile for avg_sbp = 120 mmHg (average rank if ties)
SELECT 
  120 AS target_sbp,
  AVG(percent_rank) * 100 AS percentile  -- Convert to percentage (0-100)
FROM 
  ranked_sbp
WHERE 
  avg_sbp = 120;