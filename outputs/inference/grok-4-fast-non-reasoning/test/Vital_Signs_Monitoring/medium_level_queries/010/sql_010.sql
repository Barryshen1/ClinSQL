WITH systolic_bp AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON 
    ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ce.subject_id = p.subject_id
  WHERE 
    LOWER(di.label) LIKE '%systolic blood pressure%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND icu.first_careunit LIKE '%ICU%'
    AND ce.charttime >= icu.intime
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum > 50  -- Exclude implausible low values
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_systolic
  FROM 
    systolic_bp
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) >= 1  -- At least one valid measurement
)
SELECT 
  avg_systolic,
  PERCENT_RANK() OVER (ORDER BY avg_systolic DESC) AS percentile_rank
FROM 
  per_stay_avg
WHERE 
  avg_systolic = 160  -- Rank for the specific value
ORDER BY 
  percentile_rank;