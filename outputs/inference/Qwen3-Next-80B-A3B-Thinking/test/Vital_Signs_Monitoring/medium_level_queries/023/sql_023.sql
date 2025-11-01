WITH cohort AS (
  SELECT 
    p.subject_id,
    i.intime,
    i.stay_id,
    i.hadm_id,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 62 AND 72
),

admissions AS (
  SELECT hadm_id, admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

creatinine AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50912
    AND l.valuenum IS NOT NULL
),

baseline_creatinine AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MIN(c.creatinine) AS baseline
  FROM creatinine c
  JOIN admissions a
    ON c.hadm_id = a.hadm_id
  WHERE c.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
  GROUP BY c.subject_id, c.hadm_id
),

aki AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN c.creatinine >= b.baseline + 0.3 THEN 1 ELSE 0 END) AS aki_flag
  FROM creatinine c
  JOIN baseline_creatinine b
    ON c.subject_id = b.subject_id AND c.hadm_id = b.hadm_id
  JOIN admissions a
    ON c.hadm_id = a.hadm_id
  WHERE c.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
  GROUP BY c.subject_id, c.hadm_id
),

temp_measurements AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.hadm_id,
    c.charttime,
    c.valuenum AS temperature,
    CASE 
      WHEN c.valuenum < 36.0 THEN '<36.0'
      WHEN c.valuenum >= 36.0 AND c.valuenum < 38.0 THEN '36.0-37.9'
      ELSE '≥38.0'
    END AS temp_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN cohort co
    ON c.stay_id = co.stay_id
  WHERE LOWER(d.label) LIKE '%temperature%'
    AND c.charttime BETWEEN co.intime AND co.intime + INTERVAL 24 HOUR
    AND c.valuenum IS NOT NULL
),

patient_category AS (
  SELECT 
    t.subject_id,
    t.temp_category,
    COALESCE(MAX(a.aki_flag), 0) AS has_aki
  FROM temp_measurements t
  LEFT JOIN aki a
    ON t.hadm_id = a.hadm_id
  GROUP BY t.subject_id, t.temp_category
)

SELECT 
  temp_category,
  AVG(temperature) AS mean_temp,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY temperature) AS median_temp,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY temperature) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY temperature) AS iqr_temp,
  SUM(has_aki) / COUNT(DISTINCT subject_id) AS aki_rate
FROM (
  SELECT 
    t.temp_category,
    t.temperature,
    pc.has_aki
  FROM temp_measurements t
  JOIN patient_category pc
    ON t.subject_id = pc.subject_id AND t.temp_category = pc.temp_category
) AS combined
GROUP BY temp_category;