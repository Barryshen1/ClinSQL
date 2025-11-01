WITH has_mi_per_hadm AS (
  SELECT 
    subject_id, 
    hadm_id, 
    LOGICAL_OR(REGEXP_CONTAINS(icd_code, r'^(410|I21)')) AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  GROUP BY subject_id, hadm_id
),
eligible_stays AS (
  SELECT 
    icu.stay_id, 
    icu.subject_id, 
    icu.hadm_id, 
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 71 AND 81
),
temps AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN eligible_stays es ON ce.stay_id = es.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.category = 'Temperature'
    AND ce.valueuom = 'C'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 45
    AND ce.charttime >= es.intime
    AND ce.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
  HAVING COUNT(ce.valuenum) >= 1
),
stay_data AS (
  SELECT 
    t.avg_temp,
    CASE 
      WHEN t.avg_temp < 36.0 THEN '<36.0'
      WHEN t.avg_temp < 38.0 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS category,
    COALESCE(hm.has_mi, FALSE) AS has_mi
  FROM temps t
  JOIN eligible_stays es ON t.stay_id = es.stay_id
  LEFT JOIN has_mi_per_hadm hm ON es.subject_id = hm.subject_id AND es.hadm_id = hm.hadm_id
)
SELECT 
  category,
  COUNT(*) AS n_stays,
  ROUND(AVG(avg_temp), 1) AS mean_temp,
  ROUND(PERCENTILE_CONT(avg_temp, 0.5), 1) AS median_temp,
  ROUND(PERCENTILE_CONT(avg_temp, 0.25), 1) AS iqr_lower,
  ROUND(PERCENTILE_CONT(avg_temp, 0.75), 1) AS iqr_upper,
  ROUND(PERCENTILE_CONT(avg_temp, 0.75) - PERCENTILE_CONT(avg_temp, 0.25), 1) AS iqr,
  ROUND(AVG(CAST(has_mi AS INT64)) * 100.0, 1) AS mi_rate_percent
FROM stay_data
GROUP BY category
ORDER BY 
  CASE category 
    WHEN '<36.0' THEN 1 
    WHEN '36.0-37.9' THEN 2 
    ELSE 3 
  END;