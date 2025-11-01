WITH eligible_stays AS (
  -- Select female ICU stays aged 75-85
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

bp_measurements AS (
  -- Systolic BP in first 48 hours
  SELECT 
    es.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    es.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220045, 220179)  -- Systolic BP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg'
    AND TIMESTAMP_DIFF(ce.charttime, es.intime, HOUR) <= 48
),

mean_sbp_per_stay AS (
  -- Compute mean SBP per stay (only stays with data)
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_sbp
  FROM 
    bp_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) > 0  -- At least one measurement
)

-- Compute percentile rank of 140 mmHg in the cohort
SELECT 
  PERCENT_RANK() OVER (ORDER BY mean_sbp) * 100 AS percentile_140
FROM 
  mean_sbp_per_stay
CROSS JOIN 
  (SELECT 140.0 AS target_sbp) t
ORDER BY 
  mean_sbp
LIMIT 1;  -- Single scalar result;