WITH valid_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM i.intime) - p.anchor_age AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_age BETWEEN 81 AND 91
    AND i.first_careunit IS NOT NULL
    AND i.los >= 1
),
stay_temps AS (
  SELECT 
    vs.stay_id,
    vs.hadm_id,
    vs.hospital_expire_flag,
    vs.age,
    AVG(c.valuenum) AS mean_temp
  FROM 
    valid_stays vs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON vs.stay_id = c.stay_id
  WHERE 
    c.itemid IN (676, 677, 678, 679, 223762)
    AND c.valueuom = 'C'
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 20 AND 45
    AND c.charttime >= vs.intime
    AND c.charttime < TIMESTAMP_ADD(vs.intime, INTERVAL 1 DAY)
  GROUP BY 
    vs.stay_id, vs.hadm_id, vs.hospital_expire_flag, vs.age
  HAVING 
    COUNT(*) > 0  -- Ensure at least one valid temperature
)
SELECT 
  temp_category,
  N,
  mean,
  median,
  IQR,
  ROUND(MI_rate_percent, 2) AS MI_rate_percent
FROM (
  SELECT 
    temp_category,
    COUNT(stay_id) AS N,
    AVG(mean_temp) AS mean,
    PERCENTILE_CONT(0.5) OVER (PARTITION BY temp_category) AS median,
    PERCENTILE_CONT(0.25) OVER (PARTITION BY temp_category) AS q1,
    PERCENTILE_CONT(0.75) OVER (PARTITION BY temp_category) AS q3,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS MI_rate_percent,
    (PERCENTILE_CONT(0.75) OVER (PARTITION BY temp_category) - PERCENTILE_CONT(0.25) OVER (PARTITION BY temp_category)) AS IQR
  FROM (
    SELECT 
      *,
      CASE 
        WHEN mean_temp < 36.0 THEN '<36.0'
        WHEN mean_temp >= 36.0 AND mean_temp <= 37.9 THEN '36.0–37.9'
        ELSE '>=38.0'
      END AS temp_category
    FROM 
      stay_temps
  ) categorized
  GROUP BY 
    temp_category
)
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    ELSE 3
  END;