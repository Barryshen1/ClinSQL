WITH vital_items AS (
  SELECT 220045 AS itemid, 60 AS low, 100 AS high UNION ALL  -- Heart Rate
  SELECT 220179, 90, 140 UNION ALL   -- Systolic BP
  SELECT 220180, 60, 90 UNION ALL    -- Diastolic BP
  SELECT 220181, 70, 105 UNION ALL   -- Mean BP
  SELECT 220210, 12, 20 UNION ALL    -- Respiratory Rate
  SELECT 223761, 97, 99 UNION ALL    -- Temperature (F)
  SELECT 223762, 97, 99 UNION ALL    -- Temperature (C to F converted)
  SELECT 220277, 95, 100             -- SpO2
),
cohort_base AS (
  SELECT 
    p.subject_id, 
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
      OR 
      (icd_version = 10 AND (icd_code LIKE 'I63%' OR icd_code = 'I64'))
  ) stroke ON a.hadm_id = stroke.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),
cohort_vitals AS (
  SELECT 
    c.stay_id,
    CASE 
      WHEN ce.itemid = 223762 THEN ce.valuenum * 1.8 + 32  -- Convert °C to °F
      ELSE ce.valuenum 
    END AS value_f,
    v.low,
    v.high,
    CASE 
      WHEN ce.itemid = 223762 AND (ce.valuenum * 1.8 + 32) BETWEEN v.low AND v.high THEN 0
      WHEN ce.itemid != 223762 AND ce.valuenum BETWEEN v.low AND v.high THEN 0
      ELSE 1 
    END AS abnormal
  FROM cohort_base c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  INNER JOIN vital_items v 
    ON ce.itemid = v.itemid
  WHERE ce.valuenum IS NOT NULL
),
cohort_scores AS (
  SELECT 
    stay_id,
    (SUM(abnormal) * 100.0 / COUNT(*)) AS score
  FROM cohort_vitals
  GROUP BY stay_id
),
scores_with_flags AS (
  SELECT 
    cs.stay_id,
    cs.score,
    c.los,
    c.hadm_id,  -- Added for distinct admission counting
    c.hospital_expire_flag
  FROM cohort_scores cs
  INNER JOIN cohort_base c ON cs.stay_id = c.stay_id
),
percentile_80 AS (
  SELECT 
    (COUNT(CASE WHEN score <= 80 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_80
  FROM scores_with_flags
),
q3_value AS (
  SELECT 
    APPROX_QUANTILES(score, 100)[OFFSET(75)] AS q3
  FROM scores_with_flags
),
top_quartile_stats AS (
  SELECT 
    AVG(los) AS avg_icu_los,
    (COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id)) AS mortality_rate_percent
  FROM scores_with_flags
  CROSS JOIN q3_value
  WHERE score >= q3_value.q3
)
SELECT 
  percentile_80.percentile_80,
  80 AS target_score,
  top_quartile_stats.avg_icu_los,
  top_quartile_stats.mortality_rate_percent
FROM percentile_80, top_quartile_stats;