WITH female_icu_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 67 AND 77
),
hr_measurements AS (
  SELECT 
    f.stay_id,
    c.valuenum AS hr_value
  FROM 
    female_icu_patients f
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON f.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE 
    d.label IN ('Heart Rate', 'HR')
    AND c.charttime >= f.intime
    AND c.charttime < f.intime + INTERVAL '24' HOUR
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 300
),
per_stay_avg_hr AS (
  SELECT 
    stay_id,
    AVG(hr_value) AS avg_hr_24h
  FROM 
    hr_measurements
  GROUP BY 
    stay_id
),
percentile_calc AS (
  SELECT 
    PERCENTILE_CONT(avg_hr_24h, 0.5) AS median_hr,
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_hr_24h <= 110 THEN 1 ELSE 0 END) AS stays_le_110
  FROM 
    per_stay_avg_hr
)
SELECT 
  (stays_le_110 * 100.0 / total_stays) AS percentile_of_110_bpm
FROM 
  percentile_calc;