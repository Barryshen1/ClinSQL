WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 85 AND 95
),
temp_measurements AS (
  SELECT 
    ch.stay_id,
    AVG(ch.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
  INNER JOIN cohort c
    ON ch.stay_id = c.stay_id
  WHERE 
    ch.itemid = 223762  -- Temperature Celsius
    AND ch.valuenum IS NOT NULL
  GROUP BY ch.stay_id
)
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE (
      (COUNTIF(avg_temp < 36.0) + 0.5 * COUNTIF(avg_temp = 36.0)) 
      / COUNT(*) 
    ) * 100 
  END AS percentile_rank
FROM temp_measurements;