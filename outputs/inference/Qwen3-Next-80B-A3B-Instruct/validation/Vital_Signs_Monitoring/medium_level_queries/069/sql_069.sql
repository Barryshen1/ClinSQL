WITH female_icu_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 41 AND 51
),
rr_measurements AS (
  SELECT 
    f.subject_id,
    f.stay_id,
    f.intime,
    c.charttime,
    c.valuenum AS rr_value
  FROM 
    female_icu_patients f
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    d.label = 'Respiratory Rate'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= f.intime
    AND c.charttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
),
per_stay_avg_rr AS (
  SELECT 
    stay_id,
    AVG(rr_value) AS avg_rr
  FROM 
    rr_measurements
  GROUP BY 
    stay_id
),
stroke_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    LOWER(dd.long_title) LIKE '%stroke%'
),
stay_with_stroke AS (
  SELECT 
    p.stay_id,
    p.avg_rr,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_stroke
  FROM 
    per_stay_avg_rr p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.stay_id = i.stay_id
  LEFT JOIN 
    stroke_diagnoses s
    ON i.hadm_id = s.hadm_id
)
SELECT 
  CASE 
    WHEN avg_rr < 12 THEN '<12'
    WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
    WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
    WHEN avg_rr >= 30 THEN '>=30'
  END AS rr_category,
  COUNT(*) AS stay_count,
  SUM(has_stroke) AS stroke_count,
  ROUND(SUM(has_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM 
  stay_with_stroke
GROUP BY 
  rr_category
ORDER BY 
  rr_category;